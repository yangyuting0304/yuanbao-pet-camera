// 毛孩美颜 - FireRed Image Edit 代理（ModelScope）
// 职责：持有 ModelScope API Key（不进前端），把源图 base64 上传到腾讯云 COS 拿公网 URL，
//       调 FireRed 异步图像编辑任务，轮询结果，下载结果图转 base64 返回前端。
//
// 注意：FireRed-Image-Edit 模型只接受 image_url（公网 URL），不接受 base64，因此必须先传 COS。

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const COS = require('cos-nodejs-sdk-v5');

const app = express();
app.use(cors());
app.use(express.json({ limit: '25mb' }));

const MODELSCOPE_API_KEY = process.env.MODELSCOPE_API_KEY;
const MODEL = process.env.FIRERED_MODEL || 'FireRedTeam/FireRed-Image-Edit-1.1';
const PORT = process.env.PORT || 3000;
const API_BASE = 'https://api-inference.modelscope.cn';

const cos = new COS({
  SecretId: process.env.COS_SECRET_ID,
  SecretKey: process.env.COS_SECRET_KEY,
});

// 1) 把源图 buffer 上传到 COS（对象级公开读），返回公网 URL
function uploadToCos(buffer, ext = 'jpg') {
  const key = `firered/tmp/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
  return new Promise((resolve, reject) => {
    cos.putObject(
      {
        Bucket: process.env.COS_BUCKET,
        Region: process.env.COS_REGION,
        Key: key,
        Body: buffer,
        ACL: 'public-read',
      },
      (err) => {
        if (err) return reject(err);
        const url = `https://${process.env.COS_BUCKET}.cos.${process.env.COS_REGION}.myqcloud.com/${key}`;
        resolve(url);
      },
    );
  });
}

// 2) 提交 FireRed 异步任务，返回 task_id
async function submitFireRed(imageUrl, prompt) {
  const resp = await fetch(`${API_BASE}/v1/images/generations`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${MODELSCOPE_API_KEY}`,
      'Content-Type': 'application/json',
      'X-ModelScope-Async-Mode': 'true',
    },
    body: JSON.stringify({ model: MODEL, prompt, image_url: imageUrl }),
  });
  if (!resp.ok) {
    const txt = await resp.text();
    throw new Error(`ModelScope submit failed: ${resp.status} ${txt}`);
  }
  const data = await resp.json();
  if (!data.task_id) throw new Error(`No task_id: ${JSON.stringify(data)}`);
  return data.task_id;
}

// 3) 轮询任务状态，成功后返回结果图 URL
async function pollTask(taskId, maxAttempts = 36, interval = 5000) {
  for (let i = 0; i < maxAttempts; i++) {
    await new Promise((r) => setTimeout(r, interval));
    const resp = await fetch(`${API_BASE}/v1/tasks/${taskId}`, {
      headers: {
        Authorization: `Bearer ${MODELSCOPE_API_KEY}`,
        'X-ModelScope-Task-Type': 'image_generation',
      },
    });
    if (!resp.ok) continue;
    const data = await resp.json();
    const status = data.task_status;
    if (status === 'SUCCEED') {
      const out =
        data.output_images ||
        (data.output && data.output.output_images) ||
        [];
      if (!out.length) throw new Error('SUCCEED but no output_images');
      return out[0];
    } else if (status === 'FAILED') {
      throw new Error(`FireRed generation FAILED: ${JSON.stringify(data).slice(0, 300)}`);
    }
  }
  throw new Error('FireRed generation timeout');
}

// 4) 主接口：{ imageBase64, prompt } -> { imageBase64 }
app.post('/api/v1/firered-edit', async (req, res) => {
  try {
    const { imageBase64, prompt } = req.body || {};
    if (!imageBase64 || !prompt) {
      return res.status(400).json({ error: 'imageBase64 and prompt are required' });
    }
    // 兼容带 data URI 前缀的 base64
    const base64Data = imageBase64.includes('base64,')
      ? imageBase64.split('base64,')[1]
      : imageBase64;
    const buffer = Buffer.from(base64Data, 'base64');

    // 1) 传 COS 拿公网 URL
    const imageUrl = await uploadToCos(buffer);
    // 2) 提交任务
    const taskId = await submitFireRed(imageUrl, prompt);
    // 3) 轮询
    const resultUrl = await pollTask(taskId);
    // 4) 下载结果图转 base64
    const imgResp = await fetch(resultUrl);
    if (!imgResp.ok) throw new Error(`Download result failed: ${imgResp.status}`);
    const arrayBuf = await imgResp.arrayBuffer();
    const resultBase64 = Buffer.from(arrayBuf).toString('base64');
    res.json({ imageBase64: resultBase64 });
  } catch (e) {
    console.error('[firered-edit] error:', e);
    res.status(500).json({ error: e.message || String(e) });
  }
});

app.get('/health', (_, res) => res.json({ ok: true }));

app.listen(PORT, () => {
  console.log(`FireRed proxy listening on :${PORT}`);
});
