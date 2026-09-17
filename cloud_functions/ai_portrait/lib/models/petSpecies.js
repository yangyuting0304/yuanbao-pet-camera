// 宠物物种识别适配器。
//
// ## 为什么必须放在服务端
//
// 识别用的 API Key **绝不能进客户端**：Flutter 包（尤其 Web 产物）里的字符串
// 可以被直接解出来，Key 一泄露别人就能刷爆你的额度。
// 项目里 AI 写真 / 一键成片早就是「Key 在服务端、客户端只调自家代理」的模式，
// 这里沿用同一套，不引入例外。
//
// ## 前端协议（固定，换供应商不改前端）
//
//   POST /api/pet-species  { imageBase64 }
//     -> { species, confidence, matchedLabel, provider }
//
//   species: 'cat' | 'dog' | 'rabbit' | 'chinchilla' | null
//   null 表示没识别出来 —— 前端据此退化为"沿用当前物种并提示用户确认"，
//   而不是硬套一个可能错的参数。
//
// 供应商差异全部收敛在本文件的适配器里。
//
// ## 环境变量
//
//   SPECIES_PROVIDER           baidu | mock | off（默认 off）
//   BAIDU_AI_API_KEY           百度 AI 开放平台 API Key
//   BAIDU_AI_SECRET_KEY        百度 AI 开放平台 Secret Key
//   SPECIES_CONFIDENCE_MIN     置信度下限，默认 0.5
//   SPECIES_MOCK_RESULT        mock 模式下固定返回的物种，默认 cat

const BAIDU_OAUTH = 'https://aip.baidubce.com/oauth/2.0/token';
const BAIDU_ANIMAL = 'https://aip.baidubce.com/rest/2.0/image-classify/v1/animal';

/** 合法的物种编码（前端只认这几个）。 */
const SPECIES_CODES = ['cat', 'dog', 'rabbit', 'chinchilla'];

/**
 * 标签关键词 → 物种编码。
 *
 * 中英文都要覆盖：百度动物识别返回**中文**名（如「猫」），
 * 多数海外模型返回英文标签。
 *
 * 顺序即优先级，「小众的排前面」很关键 ——
 * 「龙猫」里含「猫」、「豚鼠」里含「鼠」，如果不先判就会串到错的物种上。
 */
const SPECIES_KEYWORDS = {
  chinchilla: [
    'chinchilla', '龙猫', '毛丝鼠',
    'guinea pig', '豚鼠', '荷兰猪',
    'hamster', '仓鼠', 'gerbil', 'rodent', '啮齿',
  ],
  rabbit: ['rabbit', 'bunny', 'hare', 'lop', '兔', '穴兔', '垂耳兔'],
  cat: [
    'cat', 'kitten', 'kitty', 'tabby', 'siamese', 'persian', 'ragdoll',
    'bengal', 'shorthair', 'sphynx', 'maine coon',
    '猫', '英短', '美短', '布偶', '狸花', '橘猫', '缅因', '暹罗', '蓝猫', '奶牛猫',
  ],
  dog: [
    'dog', 'puppy', 'pup', 'retriever', 'labrador', 'poodle', 'corgi',
    'husky', 'beagle', 'bulldog', 'shepherd', 'terrier', 'chihuahua',
    'dachshund', 'pug', 'shiba', 'akita', 'collie', 'spaniel', 'schnauzer',
    '犬', '狗', '柯基', '柴犬', '金毛', '拉布拉多', '萨摩耶', '泰迪', '贵宾',
    '边牧', '哈士奇', '比熊', '博美', '雪纳瑞',
  ],
};

/**
 * 把一条标签映射成物种编码；识别不出返回 null。
 * 导出是为了能在不连外网的情况下单测。
 */
function speciesOfLabel(label) {
  const s = String(label == null ? '' : label).toLowerCase().trim();
  if (!s) return null;
  for (const code of Object.keys(SPECIES_KEYWORDS)) {
    if (SPECIES_KEYWORDS[code].some((w) => s.includes(w))) return code;
  }
  return null;
}

/** 从一组候选标签里挑置信度最高的、能映射到物种的那一条。 */
function pickBestSpecies(candidates, confidenceMin) {
  let best = null;
  for (const item of candidates) {
    const score = Number(item.score);
    if (!Number.isFinite(score) || score < confidenceMin) continue;
    const code = speciesOfLabel(item.name);
    if (!code) continue;
    if (!best || score > best.confidence) {
      best = { species: code, confidence: score, matchedLabel: String(item.name) };
    }
  }
  return best;
}

/** 百度 AI 开放平台 —— 动物识别。 */
function createBaiduSpeciesAdapter(env) {
  const apiKey = env.BAIDU_AI_API_KEY || '';
  const secretKey = env.BAIDU_AI_SECRET_KEY || '';
  // access_token 有效期 30 天，进程内缓存即可，避免每次都换一次 token。
  let token = '';
  let tokenExpireAt = 0;

  async function getToken() {
    if (token && Date.now() < tokenExpireAt) return token;
    const url = `${BAIDU_OAUTH}?grant_type=client_credentials`
      + `&client_id=${encodeURIComponent(apiKey)}`
      + `&client_secret=${encodeURIComponent(secretKey)}`;
    const resp = await fetch(url, { method: 'POST' });
    if (!resp.ok) throw new Error(`百度 token 获取失败 ${resp.status}`);
    const data = await resp.json();
    if (!data.access_token) {
      throw new Error(`百度 token 异常：${data.error || ''} ${data.error_description || ''}`);
    }
    token = data.access_token;
    // 提前 5 分钟过期，避免边界上踩到失效。
    tokenExpireAt = Date.now() + Math.max(0, (Number(data.expires_in) || 2592000) - 300) * 1000;
    return token;
  }

  async function detect({ imageBytes, confidenceMin }) {
    const accessToken = await getToken();
    // 百度要求 x-www-form-urlencoded，且 image 是去掉编码头的纯 base64。
    const form = new URLSearchParams();
    form.append('image', imageBytes.toString('base64'));
    form.append('top_num', '6');
    const resp = await fetch(`${BAIDU_ANIMAL}?access_token=${encodeURIComponent(accessToken)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form,
    });
    if (!resp.ok) throw new Error(`百度动物识别失败 ${resp.status}`);
    const data = await resp.json();
    if (data.error_code) {
      throw new Error(`百度动物识别业务错误 ${data.error_code} ${data.error_msg || ''}`);
    }
    const result = Array.isArray(data.result) ? data.result : [];
    return pickBestSpecies(result, confidenceMin);
  }

  return {
    provider: 'baidu',
    ready: Boolean(apiKey && secretKey),
    detect,
  };
}

/** 演示用：不连外网，固定返回配置的物种。 */
function createMockSpeciesAdapter(env) {
  const fixed = String(env.SPECIES_MOCK_RESULT || 'cat').trim().toLowerCase();
  const species = SPECIES_CODES.includes(fixed) ? fixed : 'cat';
  return {
    provider: 'mock',
    ready: true,
    async detect() {
      return { species, confidence: 0.99, matchedLabel: `mock:${species}` };
    },
  };
}

/** 未启用：让接口明确返回"不可用"，前端据此静默降级为用户手选。 */
function createOffSpeciesAdapter() {
  return {
    provider: 'off',
    ready: false,
    async detect() {
      return null;
    },
  };
}

/** 按环境变量解析出物种识别适配器。 */
function resolveSpeciesAdapter(env) {
  const provider = String(env.SPECIES_PROVIDER || 'off').trim().toLowerCase();
  if (provider === 'baidu') {
    const adapter = createBaiduSpeciesAdapter(env);
    // Key 没配齐时不要"看起来能用却一直报错"，直接退回 off。
    return adapter.ready ? adapter : createOffSpeciesAdapter();
  }
  if (provider === 'mock') return createMockSpeciesAdapter(env);
  return createOffSpeciesAdapter();
}

module.exports = {
  resolveSpeciesAdapter,
  speciesOfLabel,
  pickBestSpecies,
  SPECIES_CODES,
  SPECIES_KEYWORDS,
};
