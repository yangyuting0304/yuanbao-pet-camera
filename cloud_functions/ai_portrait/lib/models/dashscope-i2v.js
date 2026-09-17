// DashScope（阿里云百炼）万相图生视频（基于首帧）适配器。
//
// 对齐 API 文档《万相-图生视频（基于首帧，wan2.6 及早期模型）》：
//   创建任务：POST {API_BASE}/services/aigc/video-generation/video-synthesis
//             （API_BASE 默认 https://dashscope.aliyuncs.com/api/v1，已含 /api/v1；
//               可配 MAAS_BASE_URL / DASHSCOPE_BASE_URL 指向 workspace 专属域名）
//     请求头：X-DashScope-Async: enable（仅异步）
//     body：  { model, input: { prompt?, negative_prompt?, img_url, audio_url?, template? },
//              parameters: { resolution, duration?, prompt_extend?, shot_type?, audio?, watermark?, seed? } }
//   查询结果：GET {API_BASE}/tasks/{task_id}  ->  output.{ task_id, task_status, video_url?, message? }
//
// 与 wan2.7（lib/models/dashscope-video.js，input.media 数组格式）的主要区别：
//   1) 首帧图用 input.img_url（data URL 内联 / 公网 URL / oss://），而非 input.media。
//   2) 图片格式仅 JPEG/JPG/PNG(不含透明)/BMP/WEBP，上限 20MB（wan2.6/2.5 系）。
//   3) resolution / duration 的允许值随模型不同，此处内置文档规格表做合法钳制，
//      避免服务端写死 720P 撞上不支持该档位的模型（如 wan2.2-i2v-plus 无 720P）。
//
// 前端协议（index.js 稳定不变）：POST /api/ai-video -> { taskId }；GET /api/ai-video/status -> { status, videoUrl?, error? }
// 本适配器把 options 透传为 input / parameters：
//   negativePrompt -> input.negative_prompt
//   audioUrl       -> input.audio_url
//   template       -> input.template（视频特效，使用后 prompt 会被忽略）
//   duration       -> parameters.duration（按模型规格钳制）
//   promptExtend   -> parameters.prompt_extend
//   shotType       -> parameters.shot_type（multi：多镜头叙事，需 prompt_extend=true 且模型支持）
//   audio          -> parameters.audio（仅 wan2.6-i2v-flash 支持显式开/关有声）
//   watermark      -> parameters.watermark
//   seed           -> parameters.seed
//
// 默认模型 wanx2.1-i2v-plus（当前百炼可用额度下选定的生产模型；仅 720P / 固定 5s），
// 可用环境变量覆盖：
//   VIDEO_MODEL 或 I2V_MODEL 切换模型（见 lib/videoAdapter.js 注册表）
//   I2V_RESOLUTION     固定分辨率档位（默认 720P；模型不支持 720P 时回退该模型最低档）
//   I2V_AUDIO          仅 wan2.6-i2v-flash：'true' 有声 / 'false' 无声（不设走模型默认）
//   I2V_PROMPT_EXTEND  'true' 开启 prompt 智能改写（默认 false：前端已走 LLM 扩写）
//   I2V_SEED           固定随机种子（可复现，可选）

function createDashScopeI2VAdapter(env) {
  const API_BASE = (env.MAAS_BASE_URL || env.DASHSCOPE_BASE_URL || 'https://dashscope.aliyuncs.com/api/v1').replace(/\/+$/, '');
  const SYNTHESIS_ENDPOINT = `${API_BASE}/services/aigc/video-generation/video-synthesis`;

  // 模型名解析优先级：VIDEO_MODEL > I2V_MODEL > 默认 wanx2.1-i2v-plus。
  const MODEL = (env.VIDEO_MODEL || env.I2V_MODEL || 'wanx2.1-i2v-plus').trim();

  // ---- 文档内置模型规格表 ----
  // durationSpec: { min, max } 区间取整 | { fixed } 固定 | { allowed: [] } 枚举就近取值。
  // resolutionAllowed: 文档允许档位（升序）；默认取 env.I2V_RESOLUTION 若允许，
  //                    否则回退最低档（延续服务端「固定 720P 省费用」的默认意图）。
  const MODEL_SPECS = {
    'wan2.6-i2v-flash': {
      resolutionAllowed: ['720P', '1080P'],
      durationSpec: { min: 2, max: 15 },
      durationDefault: 5,
      supports: { shotType: true, audioSwitch: true, audioUrl: true },
    },
    'wan2.6-i2v': {
      resolutionAllowed: ['720P', '1080P'],
      durationSpec: { min: 2, max: 15 },
      durationDefault: 5,
      supports: { shotType: true, audioSwitch: false, audioUrl: true },
    },
    'wan2.6-i2v-us': {
      resolutionAllowed: ['720P', '1080P'],
      durationSpec: { allowed: [5, 10, 15] },
      durationDefault: 5,
      supports: { shotType: true, audioSwitch: false, audioUrl: true },
    },
    'wan2.5-i2v-preview': {
      resolutionAllowed: ['480P', '720P', '1080P'],
      durationSpec: { allowed: [5, 10] },
      durationDefault: 5,
      supports: { shotType: false, audioSwitch: false, audioUrl: true },
    },
    'wan2.2-i2v-flash': {
      resolutionAllowed: ['480P', '720P'],
      durationSpec: { fixed: 5 },
      durationDefault: 5,
      supports: { shotType: false, audioSwitch: false, audioUrl: false },
    },
    'wan2.2-i2v-plus': {
      resolutionAllowed: ['480P', '1080P'],
      durationSpec: { fixed: 5 },
      durationDefault: 5,
      supports: { shotType: false, audioSwitch: false, audioUrl: false },
    },
    'wanx2.1-i2v-turbo': {
      resolutionAllowed: ['480P', '720P'],
      durationSpec: { allowed: [3, 4, 5] },
      durationDefault: 5,
      supports: { shotType: false, audioSwitch: false, audioUrl: false },
    },
    'wanx2.1-i2v-plus': {
      resolutionAllowed: ['720P'],
      durationSpec: { fixed: 5 },
      durationDefault: 5,
      supports: { shotType: false, audioSwitch: false, audioUrl: false },
    },
  };

  // 未收录模型（未来新模型）给出最宽松的兜底：取区间跨度最大的 wan2.6-i2v 规格处理。
  const spec = MODEL_SPECS[MODEL.toLowerCase()] || MODEL_SPECS['wan2.6-i2v'];

  // 分辨率：env.I2V_RESOLUTION 若在模型允许档位内则用之，否则回退模型最低档
  // （延续原实现「服务端写死 720P 省费用」的意图；720P 不被该模型支持时才退档）。
  function pickResolution() {
    const wanted = (env.I2V_RESOLUTION || '720P').trim();
    if (spec.resolutionAllowed.includes(wanted)) return wanted;
    return spec.resolutionAllowed[0];
  }
  const RESOLUTION = pickResolution();

  // 时长按文档规格钳制：区间取整 / 固定 / 枚举就近。
  function pickDuration(raw) {
    const d = spec.durationSpec;
    const req = Number.isFinite(Number(raw)) ? Number(raw) : spec.durationDefault;
    if (d.fixed) return d.fixed;
    if (d.allowed) {
      let best = d.allowed[0];
      for (const v of d.allowed) {
        if (Math.abs(v - req) < Math.abs(best - req)) best = v;
      }
      return best;
    }
    return Math.min(d.max, Math.max(d.min, Math.round(req)));
  }

  function boolish(v, fallback) {
    if (v === undefined || v === null) return fallback;
    return ['1', 'true', 'yes'].includes(String(v).trim().toLowerCase());
  }

  // 统一输入 -> DashScope 请求体。
  // options: { negativePrompt, duration, promptExtend, shotType, audio, audioUrl, watermark, template, seed }
  function buildPayload(imageBase64, prompt, options = {}) {
    const input = {};
    // prompt 仅在非特效模式下有意义；template 非空时 prompt 应留空/不传（文档要求）。
    if (options.template) {
      input.template = String(options.template).trim();
    } else if (prompt) {
      input.prompt = String(prompt);
    }
    if (options.negativePrompt) input.negative_prompt = String(options.negativePrompt);
    if (options.audioUrl && spec.supports.audioUrl) input.audio_url = String(options.audioUrl);

    // img_url：支持 data URL（前端协议 imageBase64 传原始 base64）或公网 URL。
    const image = String(imageBase64 || '');
    input.img_url = image.startsWith('data:') || image.startsWith('http') || image.startsWith('oss://')
      ? image
      : `data:image/jpeg;base64,${image}`;

    const parameters = { resolution: RESOLUTION };
    const duration = pickDuration(options.duration);
    if (duration !== undefined) parameters.duration = duration;

    // prompt 智能改写：默认 false（前端已用 LLM 扩写 prompt，避免二次改写漂移/增加耗时）。
    // shot_type=multi 需 prompt_extend=true 才生效，此时自动打开。
    const shotType = options.shotType || '';
    const wantExtend = boolish(options.promptExtend, false) || shotType === 'multi';
    if (wantExtend) parameters.prompt_extend = true;
    if (shotType && spec.supports.shotType) parameters.shot_type = shotType;

    if (options.audio !== undefined && spec.supports.audioSwitch) {
      parameters.audio = boolish(options.audio, true);
    }
    if (options.watermark !== undefined) {
      parameters.watermark = boolish(options.watermark, false);
    }
    if (options.seed !== undefined && options.seed !== null && options.seed !== '') {
      parameters.seed = Number(options.seed);
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
    resolution: RESOLUTION,
    format: 'img_url', // 与 wan2.7 的 media 数组格式区分，便于 healthz 观测
  };
}

module.exports = { createDashScopeI2VAdapter };
