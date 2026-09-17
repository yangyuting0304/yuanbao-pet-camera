/// 宠物拍摄参数引擎（PetCaptureProfile）
///
/// 把「物种 × 毛色 × 场景」映射成一组拍摄参数，分两层：
///
///  1. **硬件参数**（快门/ISO/曝光补偿/白平衡/对焦/闪光策略）
///     —— 只在原生平台（iOS / Android）生效。
///        `camera_web` 官方未实现曝光模式/对焦/白平衡，Web 端只能忽略这一层。
///
///  2. **后处理参数**（色温偏移/高光滚降/微对比/暗角/美颜开关）
///     —— Web 与原生都生效，是"比苹果好"的跨平台兜底方案。
///
/// 设计原则（来自 2026-09-15 调研）：
///  - 宠物美颜 = 质感增强，**禁止磨皮**（毛发是独立线条，磨皮会糊成一团）
///  - 毛色只做亮度/对比，**不做色相偏移**（防止把品种固有色"洗白"）
///  - 宁可高感噪点，不要糊片（糊片不可逆）
///  - 猫 / 兔 / 龙猫 **禁止闪光**（伤眼 + 红眼）
library;

/// 目标物种。
enum PetSpecies {
  cat('猫', '🐱'),
  dog('狗', '🐶'),
  rabbit('兔', '🐰'),
  chinchilla('龙猫', '🐭');

  const PetSpecies(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// 毛色分组——决定曝光补偿的方向（白毛加、黑毛减）。
///
/// 原理：相机测光假设场景是 18% 中性灰。
///  - 白毛 → 相机以为太亮 → 压暗 → 拍成灰毛 → 需要 **加** EV
///  - 黑毛 → 相机以为太暗 → 提亮 → 拍成灰团 → 需要 **减** EV
enum PetCoat {
  white('白/奶油毛', '白猫、萨摩、比熊、白兔、银狐', 0.85),
  black('黑/深色毛', '黑猫、黑拉、黑兔、深棕', -0.50),
  tabby('虎斑/橘/三花', '田园猫、橘猫、三花', 0.0),
  blueGrey('蓝灰/纯色亮毛', '英短蓝猫、俄蓝', -0.15),
  multi('花色/双色', '奶牛猫、边牧', 0.0);

  const PetCoat(this.label, this.examples, this.exposureCompensation);

  final String label;
  final String examples;

  /// 曝光补偿基准值（单位 EV）。
  final double exposureCompensation;
}

/// 拍摄场景——在物种/毛色的基础上做增量调整。
enum PetScene {
  portrait('特写/静卧', '睡觉、发呆、贴脸特写', 320),
  action('动态/奔跑', '跑动、扑食、跳跃、接飞盘', 1000),
  lowLight('弱光/夜间', '室内暗光、夜晚', 320),
  backlight('逆光/窗边', '窗边、下午逆光', 500),
  outdoor('户外/草地', '晴天户外、草坪', 800);

  const PetScene(this.label, this.examples, this.shutterDenominator);

  final String label;
  final String examples;

  /// 该场景建议的快门速度分母（1/分母 秒）。
  final int shutterDenominator;
}

/// 闪光灯策略。
enum FlashPolicy {
  /// 禁用直射闪光（猫、兔、龙猫）。
  forbidden('禁用闪光', '眼睛对光敏感，闪光可能造成伤害并拍出红眼'),

  /// 允许，但建议用柔和/反射光。
  discouraged('不建议', '尽量避免直射，避免惊吓宠物') ;

  const FlashPolicy(this.label, this.reason);
  final String label;
  final String reason;
}

/// 对焦目标。
enum FocusTarget {
  nearestEye('离镜头最近的眼睛', '宠物摄影的第一原则：眼神 > 构图'),
  face('面部', '眼睛不可靠时的回退方案'),
  center('画面中心', '不可靠时的兜底');

  const FocusTarget(this.label, this.reason);
  final String label;
  final String reason;
}

/// 音效引诱 —— 零技术门槛、零 AI 成本，但直接提升出片率。
///
/// [asset] 指向 `assets/sounds/` 下的文件名。当前是脚本合成的占位音
/// （`tools/gen_lure_sounds.py`），拿到实拍录音后**同名覆盖即可**，无需改代码。
enum LureSound {
  catMeow('猫叫', PetSpecies.cat, 'cat_meow.wav'),
  birdChirp('小鸟声', PetSpecies.cat, 'cat_bird.wav'),
  paperBag('纸袋声', PetSpecies.cat, 'cat_paperbag.wav'),
  whistle('哨声', PetSpecies.dog, 'dog_whistle.wav'),
  squeakyToy('玩具声（吱吱球）', PetSpecies.dog, 'dog_squeak.wav'),
  treatBag('零食袋响', PetSpecies.dog, 'dog_treatbag.wav'),
  doorBell('门外脚步声', PetSpecies.dog, 'dog_doorstep.wav'),
  leafRustle('草叶摩擦声', PetSpecies.rabbit, 'rabbit_leaf.wav'),
  plasticBag('翻塑料袋声', PetSpecies.rabbit, 'rabbit_plasticbag.wav'),
  nutBag('坚果袋响', PetSpecies.chinchilla, 'chinchilla_nutbag.wav'),
  lightTap('轻敲声', PetSpecies.chinchilla, 'chinchilla_tap.wav');

  const LureSound(this.label, this.forSpecies, this.asset);

  final String label;
  final PetSpecies forSpecies;

  /// assets/sounds 下的文件名。
  final String asset;

  /// 完整的资源路径，可直接交给播放器。
  String get assetPath => 'assets/sounds/$asset';
}

/// 滤镜模板（风格）。
///
/// 参数取自公开的胶片/氛围调色配方（VSCO、醒图、美图等社区配方），
/// 但做了两处**宠物专用改造**：
///
///  1. **不跟冷调**。公开配方里大量出现「色温 −0.7 ~ −2.6」（偏冷）——
///     那对人像和风景有效，但会让猫狗毛色发灰。这里一律改成暖调。
///  2. **保留甚至加强高光滚降**。胶片配方普遍靠「高光 −20 ~ −30」压高光，
///     而这恰恰是毛发最需要的：保住毛尖层次，不糊成一片死白。
///
/// 各字段都是**在「物种 × 毛色 × 场景」基准之上的增量**，
/// 所以套滤镜不会覆盖毛色保护（白毛本来就有的强高光滚降依然生效）。
enum PetLook {
  natural(
    label: '原色',
    hint: '不加风格，只走物种 / 毛色参数',
  ),

  creamWarm(
    label: '奶油暖光',
    hint: '通用猫狗、室内，暖调加微对比',
    tempShift: 150,
    highlightRolloff: 0.10,
    shadowLift: 0.05,
    saturation: 0.03,
    vibrance: 0.08,
    grain: 0.05,
  ),

  filmBrown(
    label: '棕褐胶片',
    hint: '深毛、复古，胶片颗粒明显',
    tempShift: 200,
    highlightRolloff: 0.05,
    shadowLift: 0.15,
    clarity: -0.05,
    saturation: -0.05,
    vibrance: 0.05,
    grain: 0.12,
  ),

  softWindow(
    label: '窗边柔光',
    hint: '白毛、逆光，强压高光保住毛尖',
    tempShift: 100,
    highlightRolloff: 0.25,
    shadowLift: 0.15,
    clarity: -0.03,
    grain: 0.03,
  ),

  backlitGold(
    label: '逆光金边',
    hint: '户外下午，出毛发光边',
    tempShift: 250,
    highlightRolloff: 0.15,
    shadowLift: 0.20,
    clarity: 0.12,
    vibrance: 0.25,
    grain: 0.06,
  ),

  nightGuard(
    label: '暗光守护',
    hint: '龙猫、夜间；颗粒顺便把高感噪点变成质感',
    tempShift: 150,
    shadowLift: 0.25,
    clarity: 0.05,
    saturation: -0.04,
    grain: 0.10,
    vignette: 0.06,
  ),

  outdoorVivid(
    label: '户外浓郁',
    hint: '狗、草地，提饱和但护住毛色',
    tempShift: 50,
    highlightRolloff: 0.15,
    shadowLift: 0.05,
    clarity: 0.10,
    saturation: 0.06,
    vibrance: 0.10,
    grain: 0.03,
  );

  const PetLook({
    required this.label,
    required this.hint,
    this.tempShift = 0,
    this.highlightRolloff = 0,
    this.shadowLift = 0,
    this.clarity = 0,
    this.saturation = 0,
    this.vibrance = 0,
    this.grain = 0,
    this.vignette = 0,
  });

  final String label;

  /// 给用户看的一句话说明。
  final String hint;

  // 以下均为叠加在基准参数上的**增量**。

  final double tempShift;
  final double highlightRolloff;
  final double shadowLift;
  final double clarity;

  /// 饱和度增量（基准是 1.0 的倍数）。
  final double saturation;

  /// 自然饱和度增量。
  final double vibrance;

  /// 胶片颗粒强度。
  final double grain;

  /// 暗角增量（可为负，用于抵消基础暗角）。
  final double vignette;
}

/// 一个完整的拍摄参数集。
///
/// 由 [PetCaptureProfile.resolve] 生成，描述「当前该怎么拍 + 该怎么处理」。
class PetCaptureProfile {
  const PetCaptureProfile({
    required this.species,
    required this.coat,
    required this.scene,
    required this.look,
    required this.shutterDenominator,
    required this.isoMin,
    required this.isoMax,
    required this.exposureCompensation,
    required this.whiteBalanceK,
    required this.continuousFocus,
    required this.flashPolicy,
    required this.silentShutter,
    required this.focusTarget,
    required this.tempShift,
    required this.highlightRolloff,
    required this.shadowLift,
    required this.clarity,
    required this.noiseReduction,
    required this.vignette,
    required this.saturation,
    required this.vibrance,
    required this.grain,
    required this.eyeEnhance,
    required this.tearStainFix,
    required this.furTextureBoost,
    required this.summary,
  });

  // ───────────────────────── 维度 ─────────────────────────

  final PetSpecies species;
  final PetCoat coat;
  final PetScene scene;

  /// 当前套用的滤镜模板（风格）。
  final PetLook look;

  // ─────────────────── 硬件参数（仅原生） ───────────────────

  /// 快门速度分母，n 表示 1/n 秒。
  final int shutterDenominator;

  /// ISO 建议区间（自动 ISO 上限取 [isoMax]）。
  final int isoMin;
  final int isoMax;

  /// 曝光补偿（EV）。白毛为正、黑毛为负。
  final double exposureCompensation;

  /// 白平衡色温（K）。
  final int whiteBalanceK;

  /// 是否使用连续对焦（动态必开）。
  final bool continuousFocus;

  /// 闪光策略。
  final FlashPolicy flashPolicy;

  /// 是否使用电子静音快门（猫 / 龙猫等易惊物种）。
  final bool silentShutter;

  /// 对焦目标。
  final FocusTarget focusTarget;

  // ────────────────── 后处理参数（跨平台） ──────────────────

  /// 色温偏移（K），正值偏暖。宠物滤镜**只偏暖，不偏冷**。
  final double tempShift;

  /// 高光滚降强度 0..1，保护毛发高光不"死白"。
  final double highlightRolloff;

  /// 暗部提亮强度 0..1。
  ///
  /// 黑/深色毛最需要这一项——不然黑猫会"糊成一团"，
  /// 看不出鼻子和眼睛的边界。
  final double shadowLift;

  /// 微对比 / 清晰度 -1..1。
  ///
  /// **注意**：这是 clarity 而非 sharpness。锐度拉满会让毛发变糙、
  /// 出现伪轮廓、显脏；clarity 才是让"毛发根根分明"的正确工具。
  final double clarity;

  /// 降噪强度 0..1。弱光与深色毛需要更强，但要避免把绒毛抹平。
  final double noiseReduction;

  /// 暗角强度 0..1，把视线收拢到眼睛。
  final double vignette;

  /// 饱和度增益，1.0 为不变。禁止过度饱和（会把毛色"染色"）。
  final double saturation;

  /// 自然饱和度增益。
  ///
  /// 与 [saturation] 的区别：vibrance 只提"还不够鲜艳"的像素，
  /// 已经饱和的毛发几乎不动，所以更安全（社区配方普遍把两者分成两个滑杆）。
  final double vibrance;

  /// 胶片颗粒强度 0..1。
  ///
  /// 除了氛围，它在弱光下还有实用价值：把去不干净的高感噪点
  /// 变成"有意的质感"，比一味降噪抹平更耐看。
  final double grain;

  /// 眼睛增强：提亮瞳色 + 强化眼神光。
  /// **不做放大、不做美瞳、不改变形状**。
  final bool eyeEnhance;

  /// 泪痕 / 眼屎淡化。
  final bool tearStainFix;

  /// 毛发质感增强（微对比 + 选择性去噪）。
  final bool furTextureBoost;

  // ───────────────────────── 展示 ─────────────────────────

  /// 一句话说明当前参数为什么这么设，用于拍摄页给用户看。
  final String summary;

  /// 当前物种推荐的引诱音效。
  List<LureSound> get lureSounds =>
      LureSound.values.where((s) => s.forSpecies == species).toList();

  /// 快门展示文案，如 `1/800s`。
  String get shutterLabel => '1/$shutterDenominator s';

  /// 曝光补偿展示文案，如 `+0.85 EV`。
  String get evLabel {
    if (exposureCompensation == 0) return '0 EV';
    final sign = exposureCompensation > 0 ? '+' : '−';
    return '$sign${exposureCompensation.abs().toStringAsFixed(2)} EV';
  }

  // ─────────────────── 物种基线（内部） ───────────────────

  /// `furTextureBoost` 生效时的 texture 强度（0..1，传入滤镜内核）。
  ///
  /// 取值依据：毛边处中频幅度约 20~40/255，全额门控下单像素增量
  /// ≈ 0.45 × 30 ≈ 13 —— 毛发「根根分明」，但不产生伪轮廓。
  /// 内部还会按固定比例派生一层遮罩锐化（见 pet_filter 的 _sharpRatio）。
  static const double furTextureStrength = 0.45;

  /// `eyeEnhance` 生效时的整体强度系数。
  /// 内部曲线：眼区暗部提亮上限 14/255（(1−l)^1.5，护高光）+ 门控锐化 0.35。
  /// 位置用「画面中上部椭圆」廉价近似，不依赖眼睛检测模型。
  static const double eyeEnhanceStrength = 1.0;

  /// `tearStainFix` 生效时的整体强度系数。
  /// 内部动作：去红 0.40 / 补蓝 0.30 / 暗部提亮 ≤12/255，
  /// 由「偏红 + 偏暗」特征门控逐像素决定作用量。
  static const double tearStainStrength = 0.8;


  /// 每个物种的基线参数。毛色与场景在此之上做增量。
  static const Map<PetSpecies, _SpeciesBase> _speciesBase = {
    PetSpecies.cat: _SpeciesBase(
      isoMin: 400,
      isoMax: 1600,
      whiteBalanceK: 5000,
      silentShutter: true,
      flashPolicy: FlashPolicy.forbidden,
      focusTarget: FocusTarget.nearestEye,
      tempShift: 300,
      highlightRolloff: 0.55,
      clarity: 0.15,
      noiseReduction: 0.20,
      vignette: 0.2,
      tearStainFix: true,
      furTextureBoost: true,
      why: '猫易惊、瞳孔对光敏感，用静音快门 + 禁闪光；短毛易反光，用微对比提质感而非锐化',
    ),
    PetSpecies.dog: _SpeciesBase(
      isoMin: 100,
      isoMax: 800,
      whiteBalanceK: 5200,
      silentShutter: false,
      flashPolicy: FlashPolicy.discouraged,
      focusTarget: FocusTarget.nearestEye,
      tempShift: 250,
      highlightRolloff: 0.5,
      clarity: 0.18,
      noiseReduction: 0.18,
      vignette: 0.15,
      tearStainFix: true,
      furTextureBoost: true,
      why: '狗动作幅度大、户外多，快门要拉满；毛色跨度最大，曝光补偿最依赖毛色判断',
    ),
    PetSpecies.rabbit: _SpeciesBase(
      isoMin: 400,
      isoMax: 1600,
      whiteBalanceK: 5000,
      silentShutter: true,
      flashPolicy: FlashPolicy.forbidden,
      focusTarget: FocusTarget.face,
      tempShift: 250,
      highlightRolloff: 0.6,
      clarity: 0.12,
      noiseReduction: 0.22,
      vignette: 0.18,
      tearStainFix: false,
      furTextureBoost: true,
      why: '白化种有红眼，必须禁闪光；整体安静但鼻须高频动，快门不能低于 1/500s',
    ),
    PetSpecies.chinchilla: _SpeciesBase(
      isoMin: 1600,
      isoMax: 6400,
      whiteBalanceK: 4500,
      silentShutter: true,
      flashPolicy: FlashPolicy.forbidden,
      focusTarget: FocusTarget.nearestEye,
      tempShift: 350,
      highlightRolloff: 0.45,
      clarity: 0.28,
      noiseReduction: 0.30,
      vignette: 0.22,
      tearStainFix: false,
      furTextureBoost: true,
      why: '夜行性、极怕光怕惊 → 弱光优先 + 禁闪光 + 静音快门；丝状绒毛几千根挤一起极易糊成一团，需要更强的微对比',
    ),
  };

  /// 根据三个维度解析出一组完整参数。
  static PetCaptureProfile resolve({
    required PetSpecies species,
    required PetCoat coat,
    PetScene scene = PetScene.portrait,
    PetLook look = PetLook.natural,
  }) {
    final base = _speciesBase[species]!;

    // 快门：取「场景要求」与「物种下限」中更快的那个。
    // 猫爆冲需要 1/1000s，但静卧时没必要，所以以场景为主、物种给下限。
    final shutter = _maxInt(scene.shutterDenominator, _speciesShutterFloor(species));

    // ISO：弱光场景整体上浮一档。上限锁 6400——再高画质崩得比拍不清更难看。
    final isoScale = scene == PetScene.lowLight ? 2.0 : 1.0;
    final isoMin = (base.isoMin * isoScale).round().clamp(50, 3200);
    final isoMax = (base.isoMax * isoScale).round().clamp(100, 6400);

    // 曝光补偿 = 毛色基准 + 场景修正（逆光要加）。
    var ev = coat.exposureCompensation;
    if (scene == PetScene.backlight) ev += 0.8;
    if (scene == PetScene.outdoor) ev -= 0.15;
    // 弱光下不要把 EV 推太高，否则噪点爆炸。
    if (scene == PetScene.lowLight) ev = (ev * 0.6);
    ev = ev.clamp(-1.5, 1.5);

    // 后处理：以物种基线为底，按场景与毛色做增量。
    var tempShift = base.tempShift;
    var clarity = base.clarity;
    var saturation = 1.0;
    var highlightRolloff = base.highlightRolloff;
    var shadowLift = 0.10;
    var noiseReduction = base.noiseReduction;

    if (scene == PetScene.backlight) {
      highlightRolloff += 0.20;
      clarity += 0.05;
      shadowLift += 0.15;
    }
    if (scene == PetScene.outdoor) {
      saturation = 1.06;
      clarity += 0.04;
    }
    if (scene == PetScene.lowLight) {
      saturation = 0.98; // 弱光略降饱和，避免噪点显色
      noiseReduction += 0.35;
      shadowLift += 0.15;
    }
    if (scene == PetScene.action) {
      clarity += 0.03; // 动态画面本身偏软，补一点质感
    }

    // 毛色决定高光/暗部的处理侧重。
    switch (coat) {
      case PetCoat.white:
        // 白毛最怕死白丢质感 → 强压高光
        highlightRolloff += 0.15;
        shadowLift += 0.05;
      case PetCoat.black:
        // 黑毛最怕糊成一团 → 强提暗部，但降 clarity 以免放大暗部噪点
        shadowLift += 0.30;
        noiseReduction += 0.20;
        clarity -= 0.03;
      case PetCoat.blueGrey:
        // 蓝灰毛最容易"发灰显脏" → 抬高一点对比与饱和
        clarity += 0.02;
        saturation = saturation == 1.0 ? 1.02 : saturation;
      case PetCoat.tabby:
      case PetCoat.multi:
        break; // 基准值即可
    }

    // 滤镜模板：在基准之上再叠一层风格增量。
    //
    // 刻意放在**最后**：先算完「物种 × 毛色 × 场景」这些硬约束，
    // 再叠风格。反过来的话，一个"暖调胶片"滤镜就可能把白毛的强高光滚降
    // 覆盖掉，毛色保护就白做了。
    tempShift += look.tempShift;
    highlightRolloff += look.highlightRolloff;
    shadowLift += look.shadowLift;
    clarity += look.clarity;
    saturation += look.saturation;

    return PetCaptureProfile(
      species: species,
      coat: coat,
      scene: scene,
      look: look,
      shutterDenominator: shutter,
      isoMin: isoMin,
      isoMax: isoMax,
      exposureCompensation: double.parse(ev.toStringAsFixed(2)),
      whiteBalanceK: base.whiteBalanceK,
      continuousFocus: scene == PetScene.action,
      flashPolicy: base.flashPolicy,
      silentShutter: base.silentShutter,
      focusTarget: base.focusTarget,
      tempShift: tempShift,
      highlightRolloff: highlightRolloff.clamp(0.0, 1.0),
      shadowLift: shadowLift.clamp(0.0, 1.0),
      clarity: clarity.clamp(-1.0, 1.0),
      noiseReduction: noiseReduction.clamp(0.0, 1.0),
      saturation: saturation.clamp(0.85, 1.15),
      vibrance: look.vibrance.clamp(-1.0, 1.0),
      grain: look.grain.clamp(0.0, 1.0),
      vignette: (base.vignette + look.vignette).clamp(0.0, 1.0),
      eyeEnhance: true,
      tearStainFix: base.tearStainFix,
      furTextureBoost: base.furTextureBoost,
      summary: '${species.label} · ${coat.label} · ${scene.label} — ${_reason(
        species: species,
        coat: coat,
        scene: scene,
        base: base,
        shutter: shutter,
        isoMax: isoMax,
        ev: ev,
      )}',
    );
  }

  static int _maxInt(int a, int b) => a > b ? a : b;

  /// 各物种的快门下限：再慢就必糊。
  static int _speciesShutterFloor(PetSpecies species) {
    switch (species) {
      case PetSpecies.cat:
        return 500; // 猫爆冲极快，静卧也别低于 1/500
      case PetSpecies.dog:
        return 500;
      case PetSpecies.rabbit:
        return 500; // 鼻须高频动
      case PetSpecies.chinchilla:
        return 500;
    }
  }

  static String _reason({
    required PetSpecies species,
    required PetCoat coat,
    required PetScene scene,
    required _SpeciesBase base,
    required int shutter,
    required int isoMax,
    required double ev,
  }) {
    final buf = StringBuffer();
    buf.write('1/$shutter s · ISO ≤$isoMax · ');
    if (ev > 0.05) {
      buf.write('曝光 +${ev.toStringAsFixed(2)}EV（${coat.label}容易被相机拍暗）');
    } else if (ev < -0.05) {
      buf.write('曝光 ${ev.toStringAsFixed(2)}EV（${coat.label}容易被相机拍亮）');
    } else {
      buf.write('曝光 0EV');
    }
    buf.write('。${base.why}');
    return buf.toString();
  }
}

/// 物种基线参数（内部使用）。
class _SpeciesBase {
  const _SpeciesBase({
    required this.isoMin,
    required this.isoMax,
    required this.whiteBalanceK,
    required this.silentShutter,
    required this.flashPolicy,
    required this.focusTarget,
    required this.tempShift,
    required this.highlightRolloff,
    required this.clarity,
    required this.noiseReduction,
    required this.vignette,
    required this.tearStainFix,
    required this.furTextureBoost,
    required this.why,
  });

  final int isoMin;
  final int isoMax;
  final int whiteBalanceK;
  final bool silentShutter;
  final FlashPolicy flashPolicy;
  final FocusTarget focusTarget;
  final double tempShift;
  final double highlightRolloff;
  final double clarity;

  /// 降噪基线。与物种的实际 ISO 档位挂钩——龙猫弱光要跑到 ISO 6400，
  /// 噪点远多于猫，所以基线更高（这一条是被单元测试逼出来的修正）。
  final double noiseReduction;

  final double vignette;
  final bool tearStainFix;
  final bool furTextureBoost;
  final String why;
}
