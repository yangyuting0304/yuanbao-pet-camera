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
const { createDashScopeI2VAdapter } = require('./models/dashscope-i2v');
const { createDashScopeR2VAdapter } = require('./models/dashscope-r2v');

// 万相-图生视频（基于首帧）系列：wan2.6 / wan2.5 / wan2.2 / wanx2.1
// 全部共用同一适配器（input.img_url + parameters.*），差异只在模型名与参数允许值
// （已内置规格表按模型钳制 resolution/duration）。VIDEO_MODEL 填哪个模型名即用哪个。
const I2V_FIRST_FRAME_MODELS = [
  'wan2.6-i2v-flash',
  'wan2.6-i2v',
  'wan2.6-i2v-us',
  'wan2.5-i2v-preview',
  'wan2.2-i2v-flash',
  'wan2.2-i2v-plus',
  'wanx2.1-i2v-turbo',
  'wanx2.1-i2v-plus',
];

// key 与 VIDEO_MODEL 环境变量对应（大小写不敏感匹配）。
// 新增模型：import 对应工厂函数并在此注册即可。
const VIDEO_ADAPTERS = {
  // 万相2.7（input.media 数组格式，非首帧 img_url），按需显式切换。
  'wan2.7-i2v': createDashScopeVideoAdapter,
  // 兼容别名：VIDEO_MODEL=dashscope 时同样走 wan2.7 适配器。
  dashscope: createDashScopeVideoAdapter,
  // 示例：将来接入其他图生视频模型
  // 'minimax-video': createMiniMaxVideoAdapter,
  // 'replicate-video': createReplicateVideoAdapter,
};

// 万相2.6 参考生视频（R2V，旧版协议）：照片只作角色锚点，不占首帧。
// 与首帧系列共用 video-synthesis 端点，但入参是 input.reference_urls + parameters.size，
// 参数语义差异较大，故独立适配器，详见 lib/models/dashscope-r2v.js 头部注释。
const R2V_REFERENCE_MODELS = [
  'wan2.6-r2v-flash',
  'wan2.6-r2v',
];

// 首帧系列模型全部映射到同一个通用适配器。
for (const name of I2V_FIRST_FRAME_MODELS) {
  VIDEO_ADAPTERS[name] = createDashScopeI2VAdapter;
}

// 参考生视频系列映射到 r2v 适配器。
for (const name of R2V_REFERENCE_MODELS) {
  VIDEO_ADAPTERS[name] = createDashScopeR2VAdapter;
}

// 根据 VIDEO_MODEL 环境变量解析出视频适配器实例。
// 规则：
//   - 显式指定 VIDEO_MODEL 且能在 VIDEO_ADAPTERS 中找到 -> 用对应适配器。
//   - 未指定 / 未知模型名 -> 回退默认首帧适配器（wanx2.1-i2v-plus，见 dashscope-i2v.js）：
//     为避免把拼错的 VIDEO_MODEL 当作真实模型名提交，回退时剥离该变量，
//     仅保留 I2V_MODEL（可显式覆盖默认模型）。
function resolveVideoAdapter(env) {
  // R2V_MODEL 亦可触发选型（dashscope-r2v.js 也认这两个变量），
  // 便于只配 R2V_MODEL 而不动 VIDEO_MODEL 的场景。
  const model = (env.VIDEO_MODEL || env.R2V_MODEL || '').trim().toLowerCase();
  if (model && VIDEO_ADAPTERS[model]) {
    return VIDEO_ADAPTERS[model](env);
  }
  const cleanEnv = { ...env };
  delete cleanEnv.VIDEO_MODEL;
  return createDashScopeI2VAdapter(cleanEnv);
}

module.exports = {
  resolveVideoAdapter,
  VIDEO_ADAPTERS,
  I2V_FIRST_FRAME_MODELS,
  R2V_REFERENCE_MODELS,
};
