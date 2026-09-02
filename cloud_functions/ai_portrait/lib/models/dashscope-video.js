// DashScope（阿里云百炼 / 千问）图生视频（wan2.7-i2v）适配器。
//
// 该适配器把「统一输入」转换为 DashScope 特有的请求格式，再把 DashScope 的
// 各种返回结构统一为「统一输出」，供 index.js 的前端协议使用。
//
// 前端协议（稳定不变）：
//   1. POST /api/ai-video { imageBase64, prompt, negativePrompt, duration, watermark }
//      -> submit() 创建任务，返回统一 taskId
//   2. GET  /api/ai-video/status?taskId=xxx
//      -> pollStatus() 查询，返回统一 { status, videoUrl?, error? }
//
// 注意：wan2.7-i2v 的 HTTP 接口**仅支持异步**（必须带 X-DashScope-Async: enable）。
// 因此这里实现的是「提交任务 -> 轮询」的异步模型适配器。
//
// 换模型时只需新增一个适配器文件（实现 submit() + pollStatus()），
// 并在 videoAdapter.js 中注册。

function createDashScopeVideoAdapter(env) {
  const MODEL = env.I2V_MODEL || 'wan2.7-i2v-2026-04-25';
  const MAAS_BASE_URL = (env.MAAS_BASE_URL || '').replace(/\/+$/, '');
  const API_BASE = MAAS_BASE_URL || 'https://dashscope.aliyuncs.com/api/v1';
  const RESOLUTION = env.I2V_RESOLUTION || '720P';

  const SYNTHESIS_ENDPOINT =
    `${API_BASE}/services/aigc/video-generation/video-synthesis`;

  // 统一输入 -> DashScope 请求体。
  // options: { negativePrompt, duration, watermark }
  function buildPayload(imageBase64, prompt, options = {}) {
    const dataUrl = `data:image/jpeg;base64,${imageBase64}`;
    const duration = Math.max(2, Math.min(15, Number(options.duration) || 5));
    const watermark = options.watermark !== false;
    return {
      model: MODEL,
      input: {
        prompt: prompt || '',
        negative_prompt: options.negativePrompt || '',
        media: [{ type: 'first_frame', url: dataUrl }],
      },
      parameters: { resolution: RESOLUTION, duration, watermark },
    };
  }

  // 创建异步任务，返回统一 taskId（前端协议只认 taskId）。
  async function submit({ imageBase64, prompt, options = {} }) {
    const key = env.DASHSCOPE_API_KEY;
    if (!key) throw new Error('DASHSCOPE_API_KEY 未配置');

    const payload = buildPayload(imageBase64, prompt, options);
    const resp = await fetch(SYNTHESIS_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${key}`,
        'X-DashScope-Async': 'enable',
      },
      body: JSON.stringify(payload),
    });
    const data = await resp.json();
    if (!resp.ok || !data.output || !data.output.task_id) {
      const msg = (data && (data.message || data.code)) || `HTTP ${resp.status}`;
      throw new Error(`创建任务失败：${msg}`);
    }
    return data.output.task_id;
  }

  // 查询任务状态，返回统一 { status, videoUrl?, error? }。
  // status 枚举：PENDING / RUNNING / SUCCEEDED / FAILED / CANCELED / UNKNOWN。
  async function pollStatus(taskId) {
    const key = env.DASHSCOPE_API_KEY;
    if (!key) throw new Error('DASHSCOPE_API_KEY 未配置');

    const resp = await fetch(`${API_BASE}/tasks/${taskId}`, {
      headers: { Authorization: `Bearer ${key}` },
    });
    const data = await resp.json();
    if (!resp.ok) {
      throw new Error(`查询任务失败：${(data && data.message) || resp.status}`);
    }
    const out = data.output || {};
    const status = out.task_status || 'UNKNOWN';
    if (status === 'SUCCEEDED') {
      return { status, videoUrl: out.video_url || null };
    }
    if (status === 'FAILED' || status === 'CANCELED') {
      return { status, error: out.message || out.code || '任务失败' };
    }
    return { status };
  }

  return { submit, pollStatus, model: MODEL, resolution: RESOLUTION };
}

module.exports = { createDashScopeVideoAdapter };
