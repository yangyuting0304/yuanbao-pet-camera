// 模型适配器注册中心。
//
// 前端协议是固定的：POST /api/beautify 发送 { styleId, imageBase64 }，
// 后端返回 { imageBase64 }。所有模型差异都在适配器内部消化。
//
// 换模型步骤：
//   1. 新建一个适配器文件（实现 generate({ sourceBytes, prompt, options })，
//      返回 { imageBytes, imageUrl?, cleanup? }）。
//   2. 在下方 ADAPTERS 注册：key = 模型名（或任意标识），value = 工厂函数。
//   3. 通过环境变量 MODEL 切换：MODEL=xxx 即走对应适配器。
//
// 适配器签名：
//   createAdapter(env, cosConfig) -> { generate({sourceBytes, prompt, options}),
//                                      model: string, format?: string }
//   generate 返回 { imageBytes: Buffer, imageUrl?: string,
//                   cleanup?: () => Promise<void> }
//   - imageBytes: 最终结果图（必填），由 index.js 统一 base64 返回给前端。
//   - cleanup:    可选，生成成功后的清理回调（如删 COS 临时图）。

const { createDashScopeAdapter } = require('./models/dashscope');

// key 与 MODEL 环境变量对应（大小写不敏感匹配）。
// 新增模型：import 对应工厂函数并在此注册即可。
const ADAPTERS = {
  dashscope: createDashScopeAdapter,
  // 示例：将来接入其他模型
  // 'openai-gpt-image': createOpenAiAdapter,
  // 'replicate': createReplicateAdapter,
};

// 根据 MODEL 环境变量解析出适配器实例。
// 规则：
//   - 显式指定 MODEL 且能在 ADAPTERS 中找到 -> 用该适配器（格式由适配器内部决定）。
//   - 以 wan2.7 开头 -> DashScope 新格式（默认）。
//   - 其他/未指定 -> 回退 DashScope 适配器。
function resolveAdapter(env) {
  const model = (env.MODEL || '').trim().toLowerCase();
  if (model && ADAPTERS[model]) {
    return ADAPTERS[model](env, env);
  }
  // 默认全部收敛到 DashScope 适配器；具体格式（multimodal / imageedit）
  // 由适配器根据 MODEL / MAAS_BASE_URL 自行决定。
  return createDashScopeAdapter(env, env);
}

module.exports = { resolveAdapter, ADAPTERS };
