// 元宝拍拍图像与相册代理。AI生成视频已下线，旧入口返回410。
// 写真、图像提示词优化、相册/COS上传接口保持可用。
// API Key仅从服务端环境读取，不进入客户端。
require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const COS = require('cos-nodejs-sdk-v5');

const { resolveAdapter } = require('./lib/adapter');
const { resolveSpeciesAdapter } = require('./lib/models/petSpecies');
const STYLE_PROMPTS = require('./prompts');
const { PROMPT_OPTIMIZER_IMAGE } = STYLE_PROMPTS;

const app = express();
app.use(cors({ origin: process.env.ALLOW_ORIGIN || '*' }));
// 80mb：成片首帧图上限 20MB + 成片视频（720P MP4）base64 后可能较大，留足余量。
app.use(express.json({ limit: '80mb' }));

// AI生成视频已下线，拦截所有旧客户端入口，防止产生模型算力费用。
app.use('/api/ai-video', (_req, res) => {
  res.status(410).json({ error: 'AI生成视频已停用，请使用客户端本机模板成片' });
});

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
// 物种识别适配器。未配置供应商时 provider=off、ready=false，
// 接口会如实返回 available:false，前端据此降级为用户手选。
const speciesAdapter = resolveSpeciesAdapter(process.env);
const SPECIES_CONFIDENCE_MIN = Number(process.env.SPECIES_CONFIDENCE_MIN || '0.5');
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

    // 提示词：前端可传自定义 prompt（用户改过/优化过）；未传则按 styleId 取
    // 服务端内置默认（与 lib/data/ai_portrait_service.dart 的 kPortraitStyles 一致）。
    const prompt =
      String(body.prompt || '').trim() || STYLE_PROMPTS[styleId] || STYLE_PROMPTS.oil;
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

// ============ 宠物物种识别（自动识别，减少用户手选） ============
// 前端：POST /api/pet-species { imageBase64 }
//   -> { species, confidence, matchedLabel, provider, available }
//   species 为 null 表示没识别出来，前端退化为「沿用当前物种 + 提示确认」。
// 供应商 API Key 只存在服务端，见 lib/models/petSpecies.js 的说明。
app.post('/api/pet-species', async (req, res) => {
  try {
    const body = req.body || {};
    const imageBase64 = body.imageBase64;
    if (!imageBase64) return res.status(400).json({ error: '缺少 imageBase64' });

    if (!speciesAdapter.ready) {
      // 未配置识别能力**不是错误**：如实告诉前端"不可用"，前端静默降级，
      // 而不是弹一个报错吓用户。这和 MOCK_VIDEO 的思路一致。
      return res.json({
        species: null,
        confidence: 0,
        matchedLabel: null,
        provider: speciesAdapter.provider,
        available: false,
      });
    }

    const imageBytes = Buffer.from(imageBase64, 'base64');
    const best = await speciesAdapter.detect({
      imageBytes,
      confidenceMin: SPECIES_CONFIDENCE_MIN,
    });

    res.json({
      species: best ? best.species : null,
      confidence: best ? best.confidence : 0,
      matchedLabel: best ? best.matchedLabel : null,
      provider: speciesAdapter.provider,
      available: true,
    });
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
    videoGenerationEnabled: false,
    resultMode: RESULT_MODE,
    speciesProvider: speciesAdapter.provider,
    speciesReady: speciesAdapter.ready,
  })
);

// ============ 写真提示词优化 ============
const PROMPT_MODEL = process.env.PROMPT_MODEL || 'qwen-plus-2025-07-28';

// 用指定元提示词（prompts.js 的 PROMPT_OPTIMIZER / PROMPT_OPTIMIZER_IMAGE）把
// 用户输入扩写为完整生成提示词。{{用户输入}} 为占位符。
async function optimizeWithMeta(metaPrompt, userPrompt) {
  const key = process.env.DASHSCOPE_API_KEY;
  if (!key) throw new Error('DASHSCOPE_API_KEY 未配置');
  const base = (process.env.MAAS_BASE_URL || 'https://dashscope.aliyuncs.com/api/v1').replace(/\/+$/, '');
  const url = `${base}/services/aigc/text-generation/generation`;
  const system = metaPrompt.replace('{{用户输入}}', userPrompt);
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

// 写真优化（图生图元提示词）。
async function optimizePortraitPrompt(userPrompt) {
  return optimizeWithMeta(PROMPT_OPTIMIZER_IMAGE, userPrompt);
}

// 写真「AI 优化」：{ prompt: 用户描述/待润色提示词 } -> { optimizedPrompt: 宠物写真提示词 }
app.post('/api/beautify/optimize-prompt', async (req, res) => {
  try {
    const userPrompt = String((req.body || {}).prompt || '').trim();
    if (!userPrompt) return res.status(400).json({ error: '缺少 prompt' });
    const optimizedPrompt = await optimizePortraitPrompt(userPrompt);
    console.log(`[beautify][optimize] ${userPrompt.slice(0, 30)} -> ${optimizedPrompt.length} chars | model=${PROMPT_MODEL}`);
    res.json({ optimizedPrompt });
  } catch (e) {
    res.status(500).json({ error: String((e && e.message) || e) });
  }
});

// ============ 通用 COS 上传（作品云存储 + 登记清单） ============
// 前端保存生成结果/拍摄照片时，先把字节传到这里：
//   1) 上传到 COS works/ 目录，拿到公网 URL
//   2) 把 {id, type, url, coverUrl?, label, petId} 追加进 works.json 清单（供刷新后拉取）
// 请求体：{ dataBase64, type, ext?, contentType?, label?, petId?, coverUrl?, coverBase64? }
// 封面（可选，供视频列表预览）：coverUrl 直接复用相册种子图的公网 COS 地址；
// 无公网源图时用 coverBase64 上传一张 jpg 副本。优先 coverUrl，随条目存 item.coverUrl。
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
    const stamp = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

    const key = `works/${stamp}.${ext}`;
    await putObjectP({
      Bucket: COS_BUCKET,
      Region: COS_REGION,
      Key: key,
      Body: buffer,
      ContentType: contentType,
      ACL: 'public-read',
    });

    const url = `https://${COS_BUCKET}.cos.${COS_REGION}.myqcloud.com/${key}`;

    // 可选封面（供「我的创作」列表预览）：
    //   1) 源图已是公网图（相册 COS 种子图）-> 前端传 coverUrl 外链直接复用，不重复上传；
    //   2) 本地/拍摄素材 -> 前端传 coverBase64，这里上传一张 jpg 副本。
    let coverUrl = null;
    if (typeof body.coverUrl === 'string' && body.coverUrl.trim()) {
      coverUrl = body.coverUrl.trim().slice(0, 300);
    } else if (body.coverBase64) {
      const coverBuffer = Buffer.from(String(body.coverBase64), 'base64');
      if (coverBuffer.length) {
        const coverKey = `works/${stamp}-cover.jpg`;
        await putObjectP({
          Bucket: COS_BUCKET,
          Region: COS_REGION,
          Key: coverKey,
          Body: coverBuffer,
          ContentType: 'image/jpeg',
          ACL: 'public-read',
        });
        coverUrl = `https://${COS_BUCKET}.cos.${COS_REGION}.myqcloud.com/${coverKey}`;
      }
    }

    const item = {
      id: `w-${stamp}`,
      type,
      url,
      ...(coverUrl ? { coverUrl } : {}),
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
    `[ai-portrait-proxy] listening on :${PORT} | model=${adapter.model} | format=${adapter.format || 'n/a'} | videoGenerationEnabled=false`
  )
);
