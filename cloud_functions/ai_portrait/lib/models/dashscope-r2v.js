// DashScope（阿里云百炼）万相参考生视频（R2V，wan2.6 系列，旧版协议）适配器。
//
// 与「图生视频-基于首帧」(dashscope-i2v.js) 的本质区别：
//   i2v：input.img_url 就是**视频第一帧**，构图、背景、主体姿态全被这张图锁死。
//   r2v：input.reference_urls 是**角色/主体锚点**，模型只提取里面主体的形象特征，
//        场景、动作、镜头完全由 prompt 决定 —— 即「还是这只猫，但出现在任意场景里」。
//   这正是「毛孩写真视频」想要的形态：用户拍的宠物照只做身份锚点，不占用首帧。
//
// 对齐 API 文档《万相-参考生视频（2.6，旧版协议，仅支持 wan2.6 模型）》：
//   创建任务：POST {API_BASE}/services/aigc/video-generation/video-synthesis
//             （API_BASE 默认 https://dashscope.aliyuncs.com/api/v1，已含 /api/v1；
//               可配 MAAS_BASE_URL / DASHSCOPE_BASE_URL 指向 workspace 专属域名）
//     请求头：X-DashScope-Async: enable（仅异步）
//     body：  { model, input: { prompt, negative_prompt?, reference_urls[] },
//              parameters: { size, duration?, audio?, shot_type?, watermark?, seed? } }
//   查询结果：GET {API_BASE}/tasks/{task_id}  ->  output.{ task_id, task_status, video_url?, message? }
//
// 【与 i2v 的参数差异，改动时别照抄 dashscope-i2v.js】
//   1) 参考图用 input.reference_urls 数组（按数组顺序对应 character1/2/3...），不是 img_url。
//   2) 分辨率是 parameters.size，形如 "1280*720"（星号分隔的具体像素），
//      不是 i2v 的档位字符串 "720P"。写 "720P" 或 "16:9" 会报错。
//   3) size 官方默认值是 1920*1080（1080P），本适配器**强制改为 1280*720** 以控成本
//      （wan2.6-r2v-flash：720P 无声 0.15 元/秒 vs 1080P 无声 0.25 元/秒）。
//   4) audio 开关仅 wan2.6-r2v-flash 支持；且要出无声视频必须**显式**传 audio=false，
//      不传则默认有声（按有声价 0.3 元/秒计费）。本适配器默认显式关掉。
//   5) duration 允许 [2,10] 整数，默认 5（不是 i2v 的 2~15）。
//
// 已知限制（重要）：
//   - 官方文档写明 reference_urls 仅支持「公网 HTTP(S) URL」与「oss:// 临时 URL」，
//     **未声明支持 base64 内联**（i2v 的 img_url 则明确支持 data URL）。
//     本适配器沿用 i2v 的写法把原始 base64 拼成 data URL 提交，实测若报参数错误，
//     需要先落盘到 OSS/公网再传 URL（可用 options.referenceUrls 直接传 URL 绕过）。
//   - 参考素材须「一个主体一张」：图里只有这只宠物，不要混入人或其他动物，否则角色会串。
//   - 图像 0~5 张 + 视频 0~3 个，总数 ≤ 5。本适配器只走图像通道，上限钳到 5。
//   - 计费：输入的**参考视频**按时长计费，参考图片不计；输出按秒计费。
//
// 前端协议（index.js 稳定不变）：POST /api/ai-video -> { taskId }；GET /api/ai-video/status -> { status, videoUrl?, error? }
// 本适配器把 options 透传为 input / parameters：
//   negativePrompt  -> input.negative_prompt
//   referenceUrls   -> input.reference_urls（可选，传了就忽略 imageBase64）
//   duration        -> parameters.duration（钳到 [2,10]）
//   audio           -> parameters.audio（仅 flash 模型；默认 false 出无声视频省费用）
//   shotType        -> parameters.shot_type（single / multi）
//   watermark       -> parameters.watermark
//   seed            -> parameters.seed
//
// 默认模型 wan2.6-r2v-flash（性价比最高档），可用环境变量覆盖：
//   VIDEO_MODEL 或 R2V_MODEL   切换模型（见 lib/videoAdapter.js 注册表）
//   R2V_SIZE                   分辨率，默认 1280*720（见下方 SIZE_ALLOWED 枚举）
//   R2V_AUDIO                  仅 flash：'true' 有声 / 'false' 无声（默认 false）
//   R2V_SHOT_TYPE              single（默认）/ multi 多镜头
//   R2V_AUTO_CHARACTER         'false' 关闭自动补 character1 前缀（默认 true）
//   R2V_SEED                   固定随机种子（可复现，可选）

function createDashScopeR2VAdapter(env) {
  const API_BASE = (env.MAAS_BASE_URL || env.DASHSCOPE_BASE_URL || 'https://dashscope.aliyuncs.com/api/v1').replace(/\/+$/, '');
  const SYNTHESIS_ENDPOINT = `${API_BASE}/services/aigc/video-generation/video-synthesis`;

  // 模型名解析优先级：VIDEO_MODEL > R2V_MODEL > 默认 wan2.6-r2v-flash。
  const MODEL = (env.VIDEO_MODEL || env.R2V_MODEL || 'wan2.6-r2v-flash').trim();

  // size 合法枚举（宽*高）。720P 与 1080P 各 5 档，覆盖 16:9 / 9:16 / 1:1 / 4:3 / 3:4。
  const SIZE_ALLOWED = [
    '1280*720', '720*1280', '960*960', '1088*832', '832*1088',
    '1920*1080', '1080*1920', '1440*1440', '1632*1248', '1248*1632',
  ];

  // 文档内置模型规格表。
  //   supports.audioSwitch：能否用 parameters.audio 控制有声/无声（仅 flash 支持）。
  const MODEL_SPECS = {
    'wan2.6-r2v-flash': {
      durationSpec: { min: 2, max: 10 },
      durationDefault: 5,
      supports: { audioSwitch: true },
    },
    'wan2.6-r2v': {
      durationSpec: { min: 2, max: 10 },
      durationDefault: 5,
      supports: { audioSwitch: false },
    },
  };

  // 未收录模型（未来新模型）给最宽松兜底：按 wan2.6-r2v 规格处理。
  const spec = MODEL_SPECS[MODEL.toLowerCase()] || MODEL_SPECS['wan2.6-r2v'];

  // 分辨率：默认 1280*720。官方默认 1920*1080 太贵，这里显式压到 720P。
  function pickSize() {
    const wanted = (env.R2V_SIZE || '1280*720').trim();
    return SIZE_ALLOWED.includes(wanted) ? wanted : '1280*720';
  }
  const SIZE = pickSize();

  // 时长钳到文档区间 [2,10] 并取整。
  function pickDuration(raw) {
    const d = spec.durationSpec;
    const req = Number.isFinite(Number(raw)) ? Number(raw) : spec.durationDefault;
    return Math.min(d.max, Math.max(d.min, Math.round(req)));
  }

  function boolish(v, fallback) {
    if (v === undefined || v === null) return fallback;
    return ['1', 'true', 'yes'].includes(String(v).trim().toLowerCase());
  }

  // 把单个参考素材规整成 reference_urls 可接受的形态。
  // 已是 http(s):// 或 oss:// 则原样透传；否则按 jpeg base64 拼 data URL。
  function normalizeRef(item) {
    const s = String(item || '').trim();
    if (!s) return null;
    if (s.startsWith('http://') || s.startsWith('https://') || s.startsWith('oss://')) return s;
    return s.startsWith('data:') ? s : `data:image/jpeg;base64,${s}`;
  }

  // r2v 只通过 character1/character2 识别参考主体，prompt 里不出现就不会锚定。
  // 前端若已在 prompt 里写死 character1 则不动；否则自动补前缀。
  // 最佳实践仍是由前端 prompt 模板直接生成「character1 在草地上奔跑」这类写法。
  function withCharacterRef(prompt) {
    const p = String(prompt || '').trim();
    if (!p) return '';
    if (!boolish(env.R2V_AUTO_CHARACTER, true)) return p;
    if (/character\s*1/i.test(p)) return p;
    return `character1 ${p}`;
  }

  // 统一输入 -> DashScope 请求体。
  // options: { negativePrompt, referenceUrls, duration, audio, shotType, watermark, seed }
  function buildPayload(imageBase64, prompt, options = {}) {
    const input = {};

    const finalPrompt = withCharacterRef(prompt);
    if (finalPrompt) input.prompt = finalPrompt;
    if (options.negativePrompt) input.negative_prompt = String(options.negativePrompt);

    // 参考素材：优先用显式传入的 URL 数组，否则退化成单张 imageBase64。
    const raw = Array.isArray(options.referenceUrls) && options.referenceUrls.length
      ? options.referenceUrls
      : [imageBase64];
    const refs = raw.map(normalizeRef).filter(Boolean).slice(0, 5);
    if (!refs.length) throw new Error('r2v 至少需要一个参考素材（imageBase64 或 referenceUrls）');
    input.reference_urls = refs;

    const parameters = { size: SIZE };
    parameters.duration = pickDuration(options.duration);

    // 音频：仅 flash 模型支持开关。默认显式 false —— 无声视频 720P 0.15 元/秒，
    // 比有声 0.3 元/秒便宜一半，且宠物写真场景本就不需要模型配音。
    if (spec.supports.audioSwitch) {
      parameters.audio = boolish(options.audio, boolish(env.R2V_AUDIO, false));
    }

    const shotType = options.shotType || env.R2V_SHOT_TYPE || 'single';
    if (shotType === 'multi' || shotType === 'single') parameters.shot_type = shotType;

    parameters.watermark = boolish(options.watermark, false);

    if (options.seed !== undefined && options.seed !== null && options.seed !== '') {
      const seed = Number(options.seed);
      if (Number.isFinite(seed) && seed >= 0 && seed <= 2147483647) parameters.seed = Math.floor(seed);
    } else if (env.R2V_SEED) {
      const seed = Number(env.R2V_SEED);
      if (Number.isFinite(seed) && seed >= 0 && seed <= 2147483647) parameters.seed = Math.floor(seed);
    }

    return { model: MODEL, input, parameters };
  }

  // 创建异步任务，返回统一 taskId。
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
    const data = await resp.json().catch(() => ({}));
    if (!resp.ok || !data.output || !data.output.task_id) {
      const msg = (data && (data.message || data.code)) || `HTTP ${resp.status}`;
      throw new Error(`创建任务失败：${msg}`);
    }
    return data.output.task_id;
  }

  // 查询任务状态，返回统一 { status, videoUrl?, error? }。
  async function pollStatus(taskId) {
    const key = env.DASHSCOPE_API_KEY;
    if (!key) throw new Error('DASHSCOPE_API_KEY 未配置');
    const resp = await fetch(`${API_BASE}/tasks/${encodeURIComponent(taskId)}`, {
      headers: { Authorization: `Bearer ${key}` },
    });
    const data = await resp.json().catch(() => ({}));
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

  return {
    submit,
    pollStatus,
    model: MODEL,
    resolution: SIZE, // 与 i2v 适配器的 resolution 字段对齐，便于 healthz / 日志统一观测
    format: 'reference_urls', // 与 img_url（i2v）、media（wan2.7）区分
  };
}

module.exports = { createDashScopeR2VAdapter };
