// 元宝拍拍 - AI 代理（部署于阿里云 ECS / 函数计算）
//
// 职责：
//   1) 服务端持有 DASHSCOPE_API_KEY，浏览器只调本服务，避免 key 泄露 + 绕过 CORS。
//   2) 写真：POST /api/beautify { styleId, imageBase64 } -> { imageBase64 }。
//   3) AI 一键成片（图生视频，异步任务）：
//      - POST /api/ai-video { imageBase64, prompt, negativePrompt, duration, watermark }
//        -> { taskId }（创建任务，不阻塞等待）
//      - GET  /api/ai-video/status?taskId=xxx -> { status, videoUrl?, error? }
//        （PENDING/RUNNING/SUCCEEDED/FAILED/UNKNOWN，15s 间隔轮询）
//      默认模型 wan2.7-i2v（可经 VIDEO_MODEL 切换其他图生视频模型，见 lib/videoAdapter.js）。
//      分辨率固定 720P（前端无控件，由服务端写死，省费用）。
//   4) MOCK_VIDEO=1 时进入模拟模式：不调百炼，返回假 taskId 并按真实时序
//      （0-10s PENDING -> 10-20s RUNNING -> 20s+ SUCCEEDED + 本地 mock/demo.mp4），
//      用于在未接真实模型时走通「提交 -> 轮询 -> 下载 -> 存库」全链路。
//
// 环境变量（务必在 ECS/FC 环境变量中配置，勿写进代码）：
//   DASHSCOPE_API_KEY        必填  百炼/千问 API Key（写真 + 成片模型）
//   MODEL                    可选  写真模型，默认 wan2.7-image-pro（见 lib/adapter.js）
//   VIDEO_MODEL              可选  成片模型，默认 wan2.7-i2v（见 lib/videoAdapter.js）
//   MAAS_BASE_URL            可选  百炼 workspace 专属 base，如
//                                 https://ws-xxxx.cn-beijing.maas.aliyuncs.com/api/v1
//                                 （配置后走 multimodal-generation + base64 内联图）
//   DASHSCOPE_BASE_URL       可选  兼容旧版：wanx2.1-imageedit 图生图端点
//   OUTPUT_SIZE              可选  输出尺寸，默认 1K（1024*1024，响应更快）
//   TENCENT_COS_SECRET_ID/KEY/BUCKET/REGION  可选  仅旧版路径需要
//   PORT                     可选  监听端口，默认 3000
//   ALLOW_ORIGIN             可选  CORS 来源，默认 *（建议设为你的站点域名）
//   RESULT_MODE              可选  image_url / base64，默认 base64
//                                 （base64：后端下载并转字节，前端拿到直接显示）
//   MOCK_VIDEO               可选  1/true 开启成片模拟模式（不调百炼）

require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const COS = require('cos-nodejs-sdk-v5');

const { resolveAdapter } = require('./lib/adapter');
const { resolveVideoAdapter } = require('./lib/videoAdapter');
const STYLE_PROMPTS = require('./prompts');
const { PROMPT_OPTIMIZER } = STYLE_PROMPTS;

const app = express();
app.use(cors({ origin: process.env.ALLOW_ORIGIN || '*' }));
// 80mb：成片首帧图上限 20MB + 成片视频（720P MP4）base64 后可能较大，留足余量。
app.use(express.json({ limit: '80mb' }));

// 腾讯云 COS 客户端（「我的创作」云存储 / 临时图床通用）。
const cos = new COS({
  SecretId: process.env.TENCENT_COS_SECRET_ID || '',
  SecretKey: process.env.TENCENT_COS_SECRET_KEY || '',
});
const putObjectP = (params) =>
  new Promise((resolve, reject) =>
    cos.putObject(params, (err, data) => (err ? reject(err) : resolve(data)))
  );
const getObjectP = (params) =>
  new Promise((resolve, reject) =>
    cos.getObject(params, (err, data) => (err ? reject(err) : resolve(data)))
  );

// ============ COS 上的两份 JSON 清单 ============
//   seed.json   静态种子数据（pets / albums / photos），由迁移脚本生成一次
//   works.json  动态作品清单（拍摄 / 编辑 / AI 生成的图片与视频），每次上传追加
const COS_BUCKET = process.env.TENCENT_COS_BUCKET || '';
const COS_REGION = process.env.TENCENT_COS_REGION || 'ap-guangzhou';
const SEED_KEY = 'seed.json';
const WORKS_KEY = 'works.json';

// 读取 COS 上的 JSON 清单；对象不存在（404/NoSuchKey）时返回 fallback。
async function readJsonFromCos(key, fallback) {
  try {
    const data = await getObjectP({ Bucket: COS_BUCKET, Region: COS_REGION, Key: key });
    const buf = data && data.Body;
    if (!buf) return fallback;
    const text = Buffer.isBuffer(buf) ? buf.toString('utf8') : String(buf);
    return JSON.parse(text);
  } catch (e) {
    if (e && (e.code === 'NoSuchKey' || e.statusCode === 404)) return fallback;
    throw e;
  }
}

async function writeJsonToCos(key, obj) {
  await putObjectP({
    Bucket: COS_BUCKET,
    Region: COS_REGION,
    Key: key,
    Body: Buffer.from(JSON.stringify(obj), 'utf8'),
    ContentType: 'application/json',
    ACL: 'public-read',
  });
}

// 串行化 works.json 的「读-改-写」，避免并发上传互相覆盖。
let worksLock = Promise.resolve();
function withWorksLock(fn) {
  const run = worksLock.then(fn, fn);
  worksLock = run.then(
    () => {},
    () => {}
  );
  return run;
}

// 解析当前模型适配器（可按环境变量切换，无需改代码）。
const adapter = resolveAdapter(process.env);
const videoAdapter = resolveVideoAdapter(process.env);
const RESULT_MODE = (process.env.RESULT_MODE || 'base64').toLowerCase();

// 下载结果图并转成统一输出。
// 统一输出格式：{ imageBase64, imageUrl? }
// 不同适配器返回结构不同，这里统一收敛给前端。
function formatOutput(imageBytes, imageUrl, styleId) {
  if (RESULT_MODE === 'image_url') {
    return { imageBase64: null, imageUrl: imageUrl || null, styleId };
  }
  return { imageBase64: imageBytes.toString('base64'), imageUrl: imageUrl || null, styleId };
}

app.post('/api/beautify', async (req, res) => {
  try {
    const body = req.body || {};
    const imageBase64 = body.imageBase64;
    const styleId = body.styleId || 'oil';
    if (!imageBase64) return res.status(400).json({ error: '缺少 imageBase64' });

    // 根据 styleId 取提示词（提示词由服务端持有，前端无需感知）。
    const prompt = STYLE_PROMPTS[styleId] || STYLE_PROMPTS.oil;
    const sourceBytes = Buffer.from(imageBase64, 'base64');

    // 调用当前模型适配器，统一拿到结果图字节。
    const { imageBytes, imageUrl, cleanup } = await adapter.generate({
      sourceBytes,
      prompt,
      options: { styleId },
    });

    // 生成成功后执行可选的清理（如删 COS 临时图），失败不影响返回。
    if (cleanup) {
      await cleanup();
    }

    res.json(formatOutput(imageBytes, imageUrl, styleId));
  } catch (e) {
    res.status(500).json({ error: String((e && e.message) || e) });
  }
});

app.get('/healthz', (req, res) =>
  res.json({
    ok: true,
    model: adapter.model,
    format: adapter.format || 'n/a',
    syncMode: adapter.syncMode || 'n/a',
    videoModel: videoAdapter.model,
    resultMode: RESULT_MODE,
  })
);

// ============ AI 一键成片（万相2.7 图生视频，异步任务） ============

const MOCK_VIDEO = ['1', 'true', 'yes'].includes(String(process.env.MOCK_VIDEO || '').toLowerCase());

// ============ AI 一键成片：提示词优化（文本大模型） ============
// 复用 DASHSCOPE_API_KEY + MAAS_BASE_URL，走 DashScope 原生文本生成端点。
// 模型默认 qwen-plus-2025-07-28（纯 LLM 快照，经实测最贴合图生视频约束：
// 全程单角色、自动分幕、无越界道具；qwen-max 会出现多只同框、qwen3.7-plus 不存在）。
// 可用 PROMPT_MODEL 环境变量切换（如 qwen-max / qwen-plus / qwen-turbo）。
const PROMPT_MODEL = process.env.PROMPT_MODEL || 'qwen-plus-2025-07-28';

// 用元提示词（prompts.js 的 PROMPT_OPTIMIZER）把用户简短描述扩写为图生视频提示词。
async function optimizePrompt(userPrompt) {
  const key = process.env.DASHSCOPE_API_KEY;
  if (!key) throw new Error('DASHSCOPE_API_KEY 未配置');
  const base = (process.env.MAAS_BASE_URL || 'https://dashscope.aliyuncs.com/api/v1').replace(/\/+$/, '');
  const url = `${base}/services/aigc/text-generation/generation`;
  const system = PROMPT_OPTIMIZER.replace('{{用户输入}}', userPrompt);
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: PROMPT_MODEL,
      input: {
        messages: [{ role: 'user', content: system }],
      },
      parameters: { result_format: 'message', temperature: 0.7, max_tokens: 2048 },
    }),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`提示词优化调用失败 ${resp.status} ${text}`);
  }
  const data = await resp.json();
  if (data.code) {
    throw new Error(`提示词优化业务错误：${data.code} ${data.message || ''}`);
  }
  const text = data.output && data.output.choices && data.output.choices[0]
    && data.output.choices[0].message && data.output.choices[0].message.content;
  if (!text || !String(text).trim()) throw new Error('提示词优化返回为空');
  return String(text).trim();
}

// AI 优化：{ prompt: 用户简短场景描述 } -> { optimizedPrompt: 完整图生视频提示词 }
app.post('/api/ai-video/optimize-prompt', async (req, res) => {
  try {
    const userPrompt = String((req.body || {}).prompt || '').trim();
    if (!userPrompt) return res.status(400).json({ error: '缺少 prompt' });
    const optimizedPrompt = await optimizePrompt(userPrompt);
    console.log(`[ai-video][optimize] ${userPrompt.slice(0, 30)} -> ${optimizedPrompt.length} chars | model=${PROMPT_MODEL}`);
    res.json({ optimizedPrompt });
  } catch (e) {
    res.status(500).json({ error: String((e && e.message) || e) });
  }
});

// 模拟模式：内存任务表 + 静态演示视频。
// 时序模拟真实异步：0-10s PENDING -> 10-20s RUNNING -> 20s+ SUCCEEDED。
const mockTasks = new Map();
const MOCK_MEDIA_DIR = path.join(__dirname, 'mock');
if (MOCK_VIDEO) {
  app.use('/mock', express.static(MOCK_MEDIA_DIR));
}

function mockStatusFor(taskId, host) {
  const t = mockTasks.get(taskId);
  if (!t) return { status: 'UNKNOWN' };
  const elapsedSec = (Date.now() - t.createdAt) / 1000;
  if (elapsedSec < 10) return { status: 'PENDING' };
  if (elapsedSec < 20) return { status: 'RUNNING' };
  // 绝对 URL：前端部署域名与代理域名不同，相对路径会 404。
  const base = `http://${host}`;
  return { status: 'SUCCEEDED', videoUrl: `${base}/mock/demo.mp4` };
}

// 创建成片任务。请求体：{ imageBase64, prompt?, negativePrompt?, duration?, watermark? }
// 响应：{ taskId }。分辨率固定 720P。
app.post('/api/ai-video', async (req, res) => {
  try {
    const body = req.body || {};
    const imageBase64 = body.imageBase64;
    if (!imageBase64) return res.status(400).json({ error: '缺少 imageBase64' });
    if (!Buffer.from(imageBase64, 'base64').length) {
      return res.status(400).json({ error: 'imageBase64 不是有效 base64' });
    }

    if (MOCK_VIDEO) {
      const taskId = `mock-${Date.now()}`;
      mockTasks.set(taskId, { createdAt: Date.now() });
      console.log(`[ai-video][mock] create ${taskId}`);
      return res.json({ taskId });
    }

    // 真实模式：委托给视频模型适配器（可按 VIDEO_MODEL 切换不同模型）。
    const taskId = await videoAdapter.submit({
      imageBase64,
      prompt: body.prompt,
      options: {
        negativePrompt: body.negativePrompt,
        duration: body.duration,
        watermark: body.watermark,
      },
    });
    console.log(`[ai-video] create ${taskId} | model=${videoAdapter.model}`);
    res.json({ taskId });
  } catch (e) {
    res.status(500).json({ error: String((e && e.message) || e) });
  }
});

// 查询成片任务状态。响应：{ status, videoUrl?, error? }
app.get('/api/ai-video/status', async (req, res) => {
  try {
    const taskId = req.query.taskId;
    if (!taskId) return res.status(400).json({ error: '缺少 taskId' });

    if (MOCK_VIDEO) return res.json(mockStatusFor(taskId, req.get('host')));

    // 真实模式：委托给视频模型适配器查询状态。
    const result = await videoAdapter.pollStatus(taskId);
    res.json(result);
  } catch (e) {
    res.status(500).json({ error: String((e && e.message) || e) });
  }
});

// ============ 通用 COS 上传（作品云存储 + 登记清单） ============
// 前端保存生成结果/拍摄照片时，先把字节传到这里：
//   1) 上传到 COS works/ 目录，拿到公网 URL
//   2) 把 {id, type, url, label, petId} 追加进 works.json 清单（供刷新后拉取）
// 请求体：{ dataBase64, type, ext?, contentType?, label?, petId? }
// 响应：{ url, item }   （清单写入失败时仍返回 url + warning，不丢文件）
const WORK_TYPES = [
  'captured_photo', // 拍摄的照片
  'edited_photo', // 美颜/编辑后保存的图片
  'created_image', // AI 写真 / AI 编辑结果
  'created_video', // AI 成片
];

app.post('/api/upload', async (req, res) => {
  try {
    const body = req.body || {};
    const dataBase64 = body.dataBase64;
    if (!dataBase64) return res.status(400).json({ error: '缺少 dataBase64' });
    const buffer = Buffer.from(String(dataBase64), 'base64');
    if (!buffer.length) return res.status(400).json({ error: 'dataBase64 不是有效 base64' });
    if (!COS_BUCKET) {
      return res.status(500).json({ error: '服务端未配置 COS（TENCENT_COS_BUCKET）' });
    }

    const ext = String(body.ext || 'bin').replace(/[^a-zA-Z0-9]/g, '').slice(0, 8) || 'bin';
    const contentType =
      body.contentType ||
      (ext === 'mp4'
        ? 'video/mp4'
        : ext === 'png'
          ? 'image/png'
          : ext === 'jpg' || ext === 'jpeg'
            ? 'image/jpeg'
            : 'application/octet-stream');
    const type = WORK_TYPES.includes(body.type) ? body.type : 'created_image';

    const key = `works/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
    await putObjectP({
      Bucket: COS_BUCKET,
      Region: COS_REGION,
      Key: key,
      Body: buffer,
      ContentType: contentType,
      ACL: 'public-read',
    });

    const url = `https://${COS_BUCKET}.cos.${COS_REGION}.myqcloud.com/${key}`;
    const item = {
      id: `w-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      type,
      url,
      label: typeof body.label === 'string' ? body.label.slice(0, 100) : '',
      petId: typeof body.petId === 'string' ? body.petId.slice(0, 64) : '',
      createdAt: new Date().toISOString(),
    };

    // 追加进 works.json（串行化，避免并发覆盖）。清单失败不回滚已上传文件。
    try {
      await withWorksLock(async () => {
        const doc = await readJsonFromCos(WORKS_KEY, { version: 1, updatedAt: null, items: [] });
        doc.version = 1;
        doc.items = Array.isArray(doc.items) ? doc.items : [];
        doc.items.unshift(item); // 最新作品排最前
        doc.updatedAt = new Date().toISOString();
        await writeJsonToCos(WORKS_KEY, doc);
      });
    } catch (e) {
      console.error('[upload] 追加 works.json 失败（文件已上传）:', e);
      return res.json({ url, item, warning: '文件上传成功，但作品清单更新失败' });
    }

    res.json({ url, item });
  } catch (e) {
    console.error('[upload] error:', e);
    res.status(500).json({ error: String((e && e.message) || e) });
  }
});

// 种子数据（pets / albums / photos），从 COS 读 seed.json。
app.get('/api/seed', async (_req, res) => {
  try {
    if (!COS_BUCKET) return res.status(500).json({ error: '服务端未配置 COS' });
    const data = await readJsonFromCos(SEED_KEY, {
      version: 1,
      pets: [],
      albums: [],
      photos: [],
    });
    res.json(data);
  } catch (e) {
    console.error('[seed] error:', e);
    res.status(500).json({ error: String((e && e.message) || e) });
  }
});

// 作品清单（拍摄 / 编辑 / AI 生成的图片与视频），从 COS 读 works.json。
app.get('/api/works', async (_req, res) => {
  try {
    if (!COS_BUCKET) return res.status(500).json({ error: '服务端未配置 COS' });
    const data = await readJsonFromCos(WORKS_KEY, {
      version: 1,
      updatedAt: null,
      items: [],
    });
    res.json(data);
  } catch (e) {
    console.error('[works] error:', e);
    res.status(500).json({ error: String((e && e.message) || e) });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () =>
  console.log(
    `[ai-portrait-proxy] listening on :${PORT} | model=${adapter.model} | format=${adapter.format || 'n/a'} | videoModel=${videoAdapter.model} | mockVideo=${MOCK_VIDEO}`
  )
);
