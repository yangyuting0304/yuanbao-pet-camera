// 元宝拍拍 - AI 写真代理（部署于阿里云 ECS / 函数计算）
// 作用：
//   1) 服务端持有 DASHSCOPE_API_KEY，浏览器只调本服务，避免 key 泄露 + 绕过 CORS。
//   2) 写真 = 图生图：默认走百炼 wan2.7-image-pro（multimodal-generation 端点），
//      支持 base64 图片内联输入，无需再依赖 COS 图床；
//      若未配置 MAAS_BASE_URL，则兼容旧版 wanx2.1-imageedit（需先传 COS 拿公网 URL）。
//   3) 腾讯云 COS 仅旧版路径用作「临时公网图床」。
//
// 环境变量（务必在 ECS/FC 环境变量中配置，勿写进代码）：
//   DASHSCOPE_API_KEY        必填  百炼/千问 API Key（写真模型）
//   MODEL                    可选  默认 wan2.7-image-pro
//   MAAS_BASE_URL            可选  百炼 workspace 专属 base，如
//                                 https://ws-xxxx.cn-beijing.maas.aliyuncs.com/api/v1
//                                 （配置后走 multimodal-generation + base64 内联图）
//   DASHSCOPE_BASE_URL       可选  兼容旧版：wanx2.1-imageedit 图生图端点
//   OUTPUT_SIZE              可选  输出尺寸，默认 1K（1024*1024，响应更快）
//   TENCENT_COS_SECRET_ID/KEY/BUCKET/REGION  可选  仅旧版路径需要
//   PORT                     可选  监听端口，默认 3000
//   ALLOW_ORIGIN             可选  CORS 来源，默认 *（建议设为你的站点域名）

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const COS = require('cos-nodejs-sdk-v5');
const crypto = require('crypto');

const app = express();
app.use(cors({ origin: process.env.ALLOW_ORIGIN || '*' }));
app.use(express.json({ limit: '15mb' }));

const MODEL = process.env.MODEL || 'wan2.7-image-pro';
const MAAS_BASE_URL = (process.env.MAAS_BASE_URL || '').replace(/\/+$/, '');
const DASHSCOPE_BASE_URL = (process.env.DASHSCOPE_BASE_URL || '').replace(/\/+$/, '');
const OUTPUT_SIZE = process.env.OUTPUT_SIZE || '1K';

// 新模型（wan2.7-image-pro）走 workspace multimodal-generation 端点，支持 base64 内联图
const USE_NEW_FORMAT = Boolean(MAAS_BASE_URL) || /wan2\.7/.test(MODEL);
const API_BASE = MAAS_BASE_URL || DASHSCOPE_BASE_URL || 'https://dashscope.aliyuncs.com/api/v1';
const GENERATION_ENDPOINT = USE_NEW_FORMAT
  ? `${API_BASE}/services/aigc/multimodal-generation/generation`
  : `${API_BASE}/services/aigc/image2image/image-synthesis`;

const cos = new COS({
  SecretId: process.env.TENCENT_COS_SECRET_ID || '',
  SecretKey: process.env.TENCENT_COS_SECRET_KEY || '',
});

// 与 lib/data/ai_portrait_service.dart 的 kPortraitStyles 保持一致
const STYLE_PROMPTS = {
  oil: '一幅油画风格的宠物猫肖像，细腻笔触，暖色调，古典光影，背景虚化',
  watercolor: '水彩画风格的宠物猫，清新通透，留白意境，淡彩晕染',
  anime: '动漫二次元风格的宠物猫，大眼睛，可爱，赛璐璐上色',
  vintage: '复古胶片风格的宠物猫照片，颗粒感，暖黄褪色，柯达色调',
  royal: '国风工笔画风格的宠物猫，典雅，牡丹与祥云背景，绢本设色',
  festive: '节日主题的宠物猫，圣诞暖灯与礼物装饰，温馨欢乐氛围',
};

function putObjectP(params) {
  return new Promise((resolve, reject) => {
    cos.putObject(params, (err, data) => (err ? reject(err) : resolve(data)));
  });
}
function deleteObjectP(params) {
  return new Promise((resolve, reject) => {
    cos.deleteObject(params, (err, data) => (err ? reject(err) : resolve(data)));
  });
}

// 旧版路径：上传源图到 COS 临时目录，返回公网可访问 URL（wanx2.1-imageedit 要求）
async function uploadToCos(buffer) {
  const key = `temp/${crypto.randomUUID()}.jpg`;
  await putObjectP({
    Bucket: process.env.TENCENT_COS_BUCKET,
    Region: process.env.TENCENT_COS_REGION,
    Key: key,
    Body: buffer,
    ContentType: 'image/jpeg',
    ACL: 'public-read',
  });
  return `https://${process.env.TENCENT_COS_BUCKET}.cos.${process.env.TENCENT_COS_REGION}.myqcloud.com/${key}`;
}

// 调百炼 wan2.7-image-pro（图生图，异步：提交任务 -> 轮询），返回结果图 URL 与旧版临时 key
async function generateEdit(imageBuffer, prompt) {
  const key = process.env.DASHSCOPE_API_KEY;
  if (!key) throw new Error('DASHSCOPE_API_KEY 未配置');

  // 新格式：base64 图片内联（data URL），无需 COS
  const dataUrl = `data:image/jpeg;base64,${imageBuffer.toString('base64')}`;
  let tempCosKey = null;
  const body = USE_NEW_FORMAT
    ? {
        model: MODEL,
        input: {
          messages: [
            {
              role: 'user',
              content: [{ text: prompt }, { image: dataUrl }],
            },
          ],
        },
        parameters: { size: OUTPUT_SIZE, n: 1, watermark: false },
      }
    : {
        model: 'wanx2.1-imageedit',
        input: {
          function: 'stylization_all',
          prompt,
          base_image_url: await uploadToCos(imageBuffer),
        },
        parameters: { n: 1 },
      };
  // 旧版路径记录临时 key，供成功后清理
  if (!USE_NEW_FORMAT) {
    tempCosKey = body.input.base_image_url.split('.myqcloud.com/')[1];
  }

  const subRes = await fetch(GENERATION_ENDPOINT, {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + key,
      'Content-Type': 'application/json',
      'X-DashScope-Async': 'enable',
    },
    body: JSON.stringify(body),
  });
  if (!subRes.ok) {
    const t = await subRes.text();
    throw new Error(`提交任务失败 ${subRes.status} ${t}`);
  }
  const sub = await subRes.json();
  const taskId = sub.output && sub.output.task_id;
  if (!taskId) throw new Error('未返回 task_id：' + JSON.stringify(sub));

  const taskUrl = `${API_BASE}/tasks/${taskId}`;
  for (let i = 0; i < 40; i++) {
    await new Promise((r) => setTimeout(r, 2000));
    const st = await fetch(taskUrl, { headers: { Authorization: 'Bearer ' + key } });
    if (!st.ok) continue;
    const d = await st.json();
    const s = d.output && d.output.task_status;
    if (s === 'SUCCEEDED') {
      if (USE_NEW_FORMAT) {
        // 新格式：output.choices[0].message.content[] 里的 image 字段
        const choice = d.output.choices && d.output.choices[0];
        const items = choice && choice.message && choice.message.content;
        const img = Array.isArray(items)
          ? items.find((it) => it && it.type === 'image' && it.image)
          : null;
        if (img && img.image) return { url: img.image, tempCosKey };
        throw new Error('生成成功但缺少结果图：' + JSON.stringify(d.output).slice(0, 300));
      }
      // 旧格式：output.results[0].url
      const results = d.output.results;
      const url =
        (results && results[0] && (results[0].url || results[0].result_url)) ||
        d.output.result_url;
      if (!url) throw new Error('生成成功但缺少结果 URL');
      return { url, tempCosKey };
    }
    if (s === 'FAILED') throw new Error('生成失败：' + JSON.stringify(d.output));
  }
  throw new Error('生成超时，请稍后重试');
}

app.post('/api/beautify', async (req, res) => {
  try {
    const body = req.body || {};
    const imageBase64 = body.imageBase64;
    const styleId = body.styleId || 'oil';
    if (!imageBase64) return res.status(400).json({ error: '缺少 imageBase64' });

    const prompt = STYLE_PROMPTS[styleId] || STYLE_PROMPTS.oil;
    const buf = Buffer.from(imageBase64, 'base64');

    // 1) 调图生图（新模型 base64 内联；旧模型内部自行上传 COS）
    const { url: resultUrl, tempCosKey } = await generateEdit(buf, prompt);

    // 2) 下载结果图，转 base64 回前端（避免前端再跨域拉取）
    const imgRes = await fetch(resultUrl);
    if (!imgRes.ok) throw new Error('下载生成结果失败 ' + imgRes.status);
    const ab = await imgRes.arrayBuffer();
    const b64 = Buffer.from(ab).toString('base64');

    // 3) 旧版路径清理 COS 临时原图（新路径无 COS 依赖）
    if (tempCosKey) {
      try {
        await deleteObjectP({
          Bucket: process.env.TENCENT_COS_BUCKET,
          Region: process.env.TENCENT_COS_REGION,
          Key: tempCosKey,
        });
      } catch (_) {
        /* 清理失败不影响返回 */
      }
    }

    res.json({ imageBase64: b64, styleId });
  } catch (e) {
    res.status(500).json({ error: String((e && e.message) || e) });
  }
});

app.get('/healthz', (req, res) => res.json({ ok: true, model: MODEL, format: USE_NEW_FORMAT ? 'multimodal' : 'imageedit' }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () =>
  console.log(`[ai-portrait-proxy] listening on :${PORT} | model=${MODEL} | format=${USE_NEW_FORMAT ? 'multimodal(base64)' : 'imageedit(cos)'}`),
);
