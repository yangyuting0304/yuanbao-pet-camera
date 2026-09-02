// 视频模型适配器注册中心。
//
// 前端协议固定不变（AI 一键成片）：
//   POST /api/ai-video { imageBase64, prompt, negativePrompt, duration, watermark } -> { taskId }
//   GET  /api/ai-video/status?taskId=xxx -> { status, videoUrl?, error? }
//
// 所有模型差异（任务 ID 字段、状态枚举、结果 URL 字段等）都在适配器内部消化。
//
// 换模型步骤：
//   1. 新建适配器文件（实现 submit() + pollStatus()）。
//   2. 在下方 VIDEO_ADAPTERS 注册。
//   3. 通过环境变量 VIDEO_MODEL 切换：VIDEO_MODEL=xxx 即走对应适配器。
//
// 适配器签名：
//   createVideoAdapter(env) -> {
//     submit({ imageBase64, prompt, options }) : Promise<taskId>,
//     pollStatus(taskId) : Promise<{ status, videoUrl?, error? }>,
//     model, resolution?
//   }
//   - status 统一枚举：PENDING / RUNNING / SUCCEEDED / FAILED / CANCELED / UNKNOWN

const { createDashScopeVideoAdapter } = require('./models/dashscope-video');

// key 与 VIDEO_MODEL 环境变量对应（大小写不敏感匹配）。
// 新增模型：import 对应工厂函数并在此注册即可。
const VIDEO_ADAPTERS = {
  dashscope: createDashScopeVideoAdapter,
  'wan2.7-i2v': createDashScopeVideoAdapter,
  // 示例：将来接入其他图生视频模型
  // 'minimax-video': createMiniMaxVideoAdapter,
  // 'replicate-video': createReplicateVideoAdapter,
};

// 根据 VIDEO_MODEL 环境变量解析出视频适配器实例。
// 未指定时默认 DashScope 图生视频适配器。
function resolveVideoAdapter(env) {
  const model = (env.VIDEO_MODEL || '').trim().toLowerCase();
  if (model && VIDEO_ADAPTERS[model]) {
    return VIDEO_ADAPTERS[model](env);
  }
  return createDashScopeVideoAdapter(env);
}

module.exports = { resolveVideoAdapter, VIDEO_ADAPTERS };
