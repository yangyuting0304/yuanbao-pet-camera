// DashScope（阿里云百炼 / 千问）图生图适配器。
//
// 该适配器把「统一输入」转换为 DashScope 特有的请求格式，再把 DashScope 的
// 各种返回结构统一为「统一输出」。
//
// 统一输入：  { sourceBytes: Buffer, prompt: string, options?: object }
// 统一输出：  { imageBytes: Buffer, imageUrl?: string, cleanup?: () => Promise<void> }
//
// 支持两种模型格式（由 MODEL 环境变量 / 配置自动选择）：
//   - multimodal-generation（wan2.7-image-pro 等）：base64 图片内联，无需 COS 图床。
//     既支持同步调用（一次请求返回结果），也支持异步任务（X-DashScope-Async: enable）。
//   - image2image-image-synthesis（wanx2.1-imageedit 等）：异步任务，需先把源图传到 COS 拿公网 URL。
//
// 调用模式（环境变量）：
//   DASHSCOPE_SYNC_MODE   可选  "auto"（默认）|"sync"|"async"
//                         auto: 新格式默认同步，旧格式（wanx2.1）走异步
//                         sync: 强制同步（新格式有效）
//                         async: 强制异步
//
// 换模型时只需新增一个适配器文件（实现 generate()），并在 adapter.js 中注册。

const COS = require('cos-nodejs-sdk-v5');
const crypto = require('crypto');

const DEFAULT_MODEL = 'wan2.7-image-pro';

function createDashScopeAdapter(env, cosConfig) {
  const MODEL = env.MODEL || DEFAULT_MODEL;
  const MAAS_BASE_URL = (env.MAAS_BASE_URL || '').replace(/\/+$/, '');
  const DASHSCOPE_BASE_URL = (env.DASHSCOPE_BASE_URL || '').replace(/\/+$/, '');
  const OUTPUT_SIZE = env.OUTPUT_SIZE || '1K';
  const SYNC_MODE = (env.DASHSCOPE_SYNC_MODE || 'auto').toLowerCase();

  // 新模型（wan2.7 等）走 workspace multimodal-generation 端点，支持 base64 内联图。
  const USE_NEW_FORMAT = Boolean(MAAS_BASE_URL) || /wan2\.7/.test(MODEL);
  const API_BASE = MAAS_BASE_URL || DASHSCOPE_BASE_URL || 'https://dashscope.aliyuncs.com/api/v1';
  const GENERATION_ENDPOINT = USE_NEW_FORMAT
    ? `${API_BASE}/services/aigc/multimodal-generation/generation`
    : `${API_BASE}/services/aigc/image2image/image-synthesis`;

  // 是否走同步模式：
  //   - 同步模式：新格式有效（wan2.7），一次请求拿结果。
  //   - 异步模式：新旧格式都有效（旧格式只能异步）。
  const USE_SYNC = SYNC_MODE === 'sync' || (SYNC_MODE === 'auto' && USE_NEW_FORMAT);

  const cos = new COS({
    SecretId: env.TENCENT_COS_SECRET_ID || '',
    SecretKey: env.TENCENT_COS_SECRET_KEY || '',
  });
  const putObjectP = (params) =>
    new Promise((resolve, reject) =>
      cos.putObject(params, (err, data) => (err ? reject(err) : resolve(data)))
    );
  const deleteObjectP = (params) =>
    new Promise((resolve, reject) =>
      cos.deleteObject(params, (err, data) => (err ? reject(err) : resolve(data)))
    );

  // 旧版格式需要把源图传到 COS 拿公网 URL，返回 key 供生成成功后清理。
  async function uploadToCos(buffer) {
    const key = `temp/${crypto.randomUUID()}.jpg`;
    await putObjectP({
      Bucket: env.TENCENT_COS_BUCKET,
      Region: env.TENCENT_COS_REGION,
      Key: key,
      Body: buffer,
      ContentType: 'image/jpeg',
      ACL: 'public-read',
    });
    return `https://${env.TENCENT_COS_BUCKET}.cos.${env.TENCENT_COS_REGION}.myqcloud.com/${key}`;
  }

  function buildRequestBody(imageBuffer, prompt) {
    if (USE_NEW_FORMAT) {
      const dataUrl = `data:image/jpeg;base64,${imageBuffer.toString('base64')}`;
      return {
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
      };
    }
    return {
      model: 'wanx2.1-imageedit',
      input: {
        function: 'stylization_all',
        prompt,
        base_image_url: null, // 由调用方填 COS URL
      },
      parameters: { n: 1 },
    };
  }

  // 从同步响应中提取结果图 URL（新格式：output.choices[0].message.content[].image）。
  function extractSyncImageUrl(output) {
    const choice = output && output.choices && output.choices[0];
    const items = choice && choice.message && choice.message.content;
    const img = Array.isArray(items)
      ? items.find((it) => it && (it.type === 'image' || it.image) && it.image)
      : null;
    if (img && img.image) return img.image;
    throw new Error('同步响应缺少结果图：' + JSON.stringify(output).slice(0, 300));
  }

  // 同步调用：一次请求返回结果（适用于 wan2.7-image-pro，且 API Key 支持同步）。
  async function runSync(imageBuffer, prompt) {
    const key = env.DASHSCOPE_API_KEY;
    if (!key) throw new Error('DASHSCOPE_API_KEY 未配置');

    const body = buildRequestBody(imageBuffer, prompt);
    const res = await fetch(GENERATION_ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + key,
        'Content-Type': 'application/json',
        // 注意：同步调用绝对不能传 X-DashScope-Async header，否则会
        // 报 "current user api does not support asynchronous calls"。
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const t = await res.text();
      throw new Error(`同步调用失败 ${res.status} ${t}`);
    }
    const data = await res.json();
    if (data.code) {
      throw new Error(`同步调用业务错误：${data.code} ${data.message || ''}`);
    }
    const url = extractSyncImageUrl(data.output);
    return { url, tempCosKey: null };
  }

  // 异步调用：提交任务并轮询。返回「结果图 URL + 待清理的 COS key」。
  async function runAsync(imageBuffer, prompt) {
    const key = env.DASHSCOPE_API_KEY;
    if (!key) throw new Error('DASHSCOPE_API_KEY 未配置');

    const body = buildRequestBody(imageBuffer, prompt);
    let tempCosKey = null;
    if (!USE_NEW_FORMAT) {
      // 旧版：先传 COS 拿公网 URL
      body.input.base_image_url = await uploadToCos(imageBuffer);
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
          // 新格式异步响应：output.choices[0].message.content[] 里的 image 字段
          const url = extractSyncImageUrl(d.output);
          return { url, tempCosKey };
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

  // 统一的生成入口：任何 DashScope 图生图模型都收敛到这里。
  async function generate({ sourceBytes, prompt, options = {} }) {
    // 根据配置选同步/异步路径。同步仅新格式支持，旧格式强制异步。
    const { url, tempCosKey } = USE_SYNC
      ? await runSync(sourceBytes, prompt)
      : await runAsync(sourceBytes, prompt);

    // 下载结果图，统一转成字节返回（前端协议不需要拿到 URL，减少跨域问题）。
    const imgRes = await fetch(url);
    if (!imgRes.ok) throw new Error('下载生成结果失败 ' + imgRes.status);
    const ab = await imgRes.arrayBuffer();

    // cleanup 用于生成成功后清理 COS 临时原图（旧版路径）。
    const cleanup = async () => {
      if (!tempCosKey) return;
      try {
        await deleteObjectP({
          Bucket: env.TENCENT_COS_BUCKET,
          Region: env.TENCENT_COS_REGION,
          Key: tempCosKey,
        });
      } catch (_) {
        /* 清理失败不影响返回 */
      }
    };

    return { imageBytes: Buffer.from(ab), imageUrl: url, cleanup };
  }

  return {
    generate,
    model: MODEL,
    format: USE_NEW_FORMAT ? 'multimodal' : 'imageedit',
    syncMode: USE_SYNC ? 'sync' : 'async',
  };
}

module.exports = { createDashScopeAdapter };