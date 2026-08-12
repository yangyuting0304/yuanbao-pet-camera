// 元宝拍拍 - AI 美颜代理（部署于阿里云 ECS / 函数计算）
// 作用：
//   1) 服务端持有 DASHSCOPE_API_KEY，浏览器只调本服务，避免 key 泄露 + 绕过 CORS。
//   2) 千问 wanx2.1-imageedit 要求输入图是「公网可访问 URL」（不接受 base64），
//      所以源图先传腾讯云 COS 拿临时公网 URL，再调图生图，结果转 base64 回前端。
//   3) 腾讯云 COS 在这里被复用为「临时公网图床」，正好是你已有的云存储。
//
// 环境变量（务必在 ECS/FC 环境变量中配置，勿写进代码）：
//   DASHSCOPE_API_KEY        必填  千问/百炼 API Key（免费额度 500 张 / 激活后 180 天）
//   DASHSCOPE_BASE_URL       可选  默认 https://dashscope.aliyuncs.com/api/v1/services/aigc/image2image/image-synthesis
//   TENCENT_COS_SECRET_ID    必填  腾讯云 COS SecretId
//   TENCENT_COS_SECRET_KEY   必填  腾讯云 COS SecretKey
//   TENCENT_COS_BUCKET       必填  COS 桶名
//   TENCENT_COS_REGION       必填  COS 地域，如 ap-guangzhou
//   PORT                     可选  监听端口，默认 3000
//   ALLOW_ORIGIN            可选  CORS 来源，默认 *（建议设为你的 COS 站点域名）

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const COS = require('cos-nodejs-sdk-v5');
const crypto = require('crypto');

const app = express();
app.use(cors({ origin: process.env.ALLOW_ORIGIN || '*' }));
app.use(express.json({ limit: '15mb' }));

const cos = new COS({
  SecretId: process.env.TENCENT_COS_SECRET_ID,
  SecretKey: process.env.TENCENT_COS_SECRET_KEY,
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

// 上传源图到 COS 临时目录，返回公网可访问 URL（千问要求）
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

// 调千问 wanx2.1-imageedit（图生图，异步：提交任务 -> 轮询）
async function callImageEdit(baseImageUrl, prompt) {
  const base =
    process.env.DASHSCOPE_BASE_URL ||
    'https://dashscope.aliyuncs.com/api/v1/services/aigc/image2image/image-synthesis';
  const key = process.env.DASHSCOPE_API_KEY;
  if (!key) throw new Error('DASHSCOPE_API_KEY 未配置');

  const subRes = await fetch(base, {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + key,
      'Content-Type': 'application/json',
      'X-DashScope-Async': 'enable',
    },
    body: JSON.stringify({
      model: 'wanx2.1-imageedit',
      input: {
        function: 'stylization_all',
        prompt: prompt,
        base_image_url: baseImageUrl,
      },
      parameters: { n: 1 },
    }),
  });
  if (!subRes.ok) {
    const t = await subRes.text();
    throw new Error(`提交任务失败 ${subRes.status} ${t}`);
  }
  const sub = await subRes.json();
  const taskId = sub.output && sub.output.task_id;
  if (!taskId) throw new Error('未返回 task_id：' + JSON.stringify(sub));

  const taskUrl = `https://dashscope.aliyuncs.com/api/v1/tasks/${taskId}`;
  for (let i = 0; i < 40; i++) {
    await new Promise((r) => setTimeout(r, 2000));
    const st = await fetch(taskUrl, { headers: { Authorization: 'Bearer ' + key } });
    if (!st.ok) continue;
    const d = await st.json();
    const s = d.output && d.output.task_status;
    if (s === 'SUCCEEDED') {
      const results = d.output.results;
      const url =
        (results && results[0] && (results[0].url || results[0].result_url)) ||
        d.output.result_url;
      if (!url) throw new Error('生成成功但缺少结果 URL');
      return url;
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

    // 1) 源图传 COS 拿公网 URL
    const publicUrl = await uploadToCos(buf);

    // 2) 调千问图生图
    const resultUrl = await callImageEdit(publicUrl, prompt);

    // 3) 下载结果图，转 base64 回前端（避免前端再跨域拉取）
    const imgRes = await fetch(resultUrl);
    if (!imgRes.ok) throw new Error('下载生成结果失败 ' + imgRes.status);
    const ab = await imgRes.arrayBuffer();
    const b64 = Buffer.from(ab).toString('base64');

    // 4) 清理临时原图
    try {
      const key = publicUrl.split('.myqcloud.com/')[1];
      await deleteObjectP({
        Bucket: process.env.TENCENT_COS_BUCKET,
        Region: process.env.TENCENT_COS_REGION,
        Key: key,
      });
    } catch (_) {
      /* 清理失败不影响返回 */
    }

    res.json({ imageBase64: b64, styleId });
  } catch (e) {
    res.status(500).json({ error: String((e && e.message) || e) });
  }
});

app.get('/healthz', (req, res) => res.json({ ok: true }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`[ai-portrait-proxy] listening on :${PORT}`));
