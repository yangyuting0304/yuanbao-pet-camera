// 宠物相机页：全屏沉浸式取景框 + 快门 + 闪光灯 + 模式切换。
//
// 拆分自原 pages.dart（8631 行）里的相机块。用 part 而不是独立 library：
// 相机页的私有组件（_CameraXxx / _ExposureSlider …）在本 library 之外本就
// 不可见，而宿主共享的 import 集合与私有符号（_DragScrollBehavior 等）
// 又必须延续，part 是唯一零改动的切法。

part of 'pages.dart';

/// 宠物相机页——全屏沉浸式取景框 + 快门 + 闪光灯 + 模式切换。
/// Web 端用模拟预览（真实相机在 Android 端接入 camera 插件）。
class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key});
  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

/// 切片2：真实相机取景框 + 快门拍照 + 存入应用内相册。
/// Web 端使用 camera_web（getUserMedia，需 localhost/https 授权）；Android 端原生相机。
class _CameraPageState extends ConsumerState<CameraPage> {
  static const Duration _cameraInitTimeout = Duration(seconds: 10);

  /// 释放旧控制器后的等待时间。Camerax 释放底层相机会话是异步的，
  /// 不等这一下，紧接着的初始化会抢不到相机（切模式黑屏的成因之一）。
  static const Duration _cameraReleaseDelay = Duration(milliseconds: 250);

  /// 自动识别的抓帧超时。takePicture 在个别机型上会长时间不返回，
  /// 没有超时会让「识别中」永久卡住，用户连手动重试都点不动。
  static const Duration _autoDetectTimeout = Duration(seconds: 10);

  /// 切到宠物模式后延迟多久再抓帧：等新控制器的预览首帧稳定。
  /// 刚重建完就 takePicture 会和相机会话抢资源，在 Android 上可能把预览卡死。
  static const Duration _autoDetectDelay = Duration(milliseconds: 800);

  /// 多帧融合的输出长边上限。
  /// 与滤镜同一档（都要在 isolate 里逐像素跑），3000 是画质与内存的折中。
  static const int _fusionMaxSide = 3000;
  // UI 按常见相机文案展示 4:3 / 16:9，内部仍按竖屏预览比例计算。
  static const List<String> _photoRatioLabels = ['原图', '1:1', '4:3', '16:9'];
  static const List<double?> _photoRatioValues = [null, 1.0, 3 / 4, 9 / 16];
  List<CameraDescription> _cameras = <CameraDescription>[];
  CameraController? _controller;
  bool _isInitialized = false;
  String? _error;
  bool _flashOn = false;
  int _cameraIndex = 0;
  int _modeIndex = 0; // 0=拍照 1=视频 2=宠物
  bool _showPetGuide = true; // 宠物模式下默认显示取景辅助框
  int _photoRatioIndex = 0; // 0=原图 1=1:1 2=3:4 3=9:16
  bool _showGridGuide = false; // 参考线使用经典 3x3 构图线
  static const _modes = ['拍照', '视频', '宠物'];
  bool _captured = false;
  Uint8List? _lastBytes;
  bool _recording = false; // 视频录制进行中
  bool _audioUnsupported = false; // 本设备/浏览器不支持录制音频，已降级无声

  /// 动态照片（Live Photo）短片录制中。同一时刻只允许一路录制。
  bool _liveRecording = false;
  /// 已请求提前收尾：用户按下快门要抢相机，录制循环见到此标志立刻结束。
  bool _liveAbort = false;
  /// 快门去重标志：连点快门时只放行一次拍照（见 [_capture]）。
  bool _capturing = false;
  /// 本次拍照的开始时刻，供 [_capture] 的看门狗判断是否已卡死。
  DateTime? _capturingSince;
  /// 相机控制器重建中。防止连点切模式/镜头/画质触发并发重建
  /// （见 [_setupController]）。
  bool _switching = false;

  // ───────────── 切片A：画质地基 ─────────────
  /// 拍摄画质档位（原生走 max，网页自动降一档）。
  CaptureQuality _quality = CaptureQuality.ultra;
  /// 平台能力探测 + 安全应用（网页端曝光/对焦不可用，自动降级）。
  final CameraCapability _capability = CameraCapability();
  /// 降级链里实际生效的分辨率预设，用于设置面板展示。
  ResolutionPreset? _activePreset;

  // ───────────── 切片B：宠物拍摄参数 ─────────────
  PetSpecies _species = PetSpecies.cat;
  /// 默认蓝灰（金元宝是英短），这一档最能体现"毛色保护"的差异。
  PetCoat _coat = PetCoat.blueGrey;
  PetScene _scene = PetScene.portrait;
  /// 滤镜模板（风格）。默认"原色"，即只走物种/毛色算出的参数。
  PetLook _look = PetLook.natural;

  // ───────────── 自动识别（减少用户选择） ─────────────
  /// 自动识别进行中（抓帧 + 分析需要时间，给用户反馈）。
  bool _autoDetecting = false;
  /// 最近一次自动识别的结果，用于把"为什么这么判"讲给用户听。
  PetAutoSetup? _lastAutoSetup;
  /// 物种识别器。
  ///
  /// 原生端：端侧 TFLite（MobileNetV2 量化）优先——离线、即时、零流量；
  /// 识别不出或异常时自动退自建代理（Key 在服务端）。Web 端直接云端。
  /// 平台分流见 `default_species_detector.dart`。
  ///
  /// 任何失败都静默降级为"没识别出来"，由用户手选——不会报错、
  /// 不影响拍照。
  final PetSpeciesDetector _speciesDetector = createDefaultSpeciesDetector();
  /// 宠物模式下是否已经自动识别过一次（避免每次切模式都抓帧）。
  bool _autoDetectedThisSession = false;

  /// 当前宠物参数集——物种 × 毛色 × 场景 × 滤镜模板。
  PetCaptureProfile get _profile => PetCaptureProfile.resolve(
    species: _species,
    coat: _coat,
    scene: _scene,
    look: _look,
  );

  // ───────────── 切片E：音效引诱 ─────────────
  final LureSoundPlayer _lurePlayer = LureSoundPlayer();

  // ───────────── 切片D：宠物滤镜 ─────────────
  /// 是否在出片时套用宠物滤镜（调色 + 美颜）。默认开启。
  bool _filterEnabled = true;
  /// 正在处理滤镜（大图纯 Dart 处理需要时间，给用户一个反馈）。
  bool _filtering = false;
  /// 快门已按下，值为当前阶段提示文案（null = 空闲）。
  ///
  /// 为什么要按阶段细分：整条链路（连拍 → 融合 → 滤镜 → 比例合成）里，
  /// 只有滤镜阶段有自己的 [_filtering] 提示，**前半段的连拍与多帧融合
  /// 可能耗时几十秒却一个字都不显示**。用户按下快门后看不到任何变化，
  /// 会以为"点了没反应"并反复点，而后几次又会被 [_capture] 的 `_capturing`
  /// 去重**静默吞掉**，表象就是「快门坏了」。
  /// 细分之后，卡在哪一步从提示文案就能直接读出来。
  String? _shootingHint;

  // ───────────── 切片C：曝光 / 对焦 / 缩放 ─────────────
  /// 用户点按的位置（视口局部坐标），用于画对焦框。
  Offset? _focusTapLocal;
  /// 送给相机的归一化对焦点（0..1）。null 表示回到自动（画面中心）。
  Offset? _focusNormalized;
  /// 用户手动微调的曝光补偿，叠加在物种/毛色算出的基准值之上。
  double _userEvOffset = 0;
  /// 当前缩放倍数。
  double _zoom = 1.0;
  /// 双指缩放开始时的倍数，用于计算增量。
  double _zoomAtGestureStart = 1.0;

  // ───────────── 切片G：连拍 ─────────────
  /// 每次拍照的张数档位。
  ///
  /// **默认单张**（原为 5 连拍）。多帧融合确实是"画质超越原生相机"的核心
  /// 手段——降噪收益按 √N 增长（3 帧 42%、5 帧 55%）——但它的代价是
  /// 连开 N 次快门 + N 帧全尺寸解码 + N 帧对齐融合：
  ///
  ///   - 网页端 `compute` 在 dart2js 下退化为**同步执行**，这条路会把主
  ///     isolate 占死，界面完全冻结、连点击都排不上队；
  ///   - 原生端虽是真 isolate，低端机上同样要等十几秒。
  ///
  /// 实拍表现为「一直正在拍摄中，怎么点都没反应」。稳定优先，故默认退回
  /// 单张（单张时 [_fuseFrames] 直接返回，整条融合分支被跳过）。
  /// 追求画质的用户可在「相机设置 → 连拍张数」里手动调回 3 / 5 / 10 张。
  BurstCount _burstShots = BurstCount.single;
  /// 最近一次连拍挑中的帧，用于给用户一句明确反馈。
  ({int index, int total})? _lastBurstPick;

  // ───────────── 切片F：宠物眼睛定位 ─────────────
  /// 眼睛定位器。模型未就位时是空实现，行为等价于"没有眼睛坐标"。
  /// 接入 TFLite 关键点模型时，只需在这里换成真实实现。
  final PetEyeDetector _eyeDetector = const NoPetEyeDetector();
  /// 最近一次定位到的双眼位置（每帧/每次抓帧更新）。
  PetEyeResult? _lastEyeResult;

  // ───────────── 实时宠物跟踪（自动捕捉） ─────────────
  /// 每 N 帧做一次推理。30fps 的流按 6 抽 1 ≈ 每秒 5 次，
  /// 足够跟上宠物移动，又把主 isolate 占用压到可感知阈值以下。
  static const int _detectFrameStride = 6;

  /// 自动对焦的重设节流：宠物移动超过该比例（或超过间隔）才重新对焦。
  /// 不加节流会让对焦马达每秒抽动好几次，取景画面持续"呼吸"。
  static const Duration _trackFocusInterval = Duration(milliseconds: 1500);
  static const double _trackFocusMoveThreshold = 0.12;

  /// 最近一次检测到的宠物框（按置信度降序）；空 = 画面里没找到宠物。
  List<PetDetection> _detections = const [];

  /// 推理进行中标记：帧流回调很密集，必须防重入（否则会排起长队）。
  bool _detecting = false;

  /// 帧计数器，用于抽帧推理。
  int _frameTick = 0;

  /// 图像流是否已开启。
  bool _streaming = false;

  /// 最近一次跟踪对焦的目标与时间（节流用）。
  Offset? _lastTrackedFocus;
  DateTime? _lastTrackedFocusAt;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras().timeout(_cameraInitTimeout);
      if (_cameras.isEmpty) {
        setState(() => _error = '未检测到可用摄像头');
        return;
      }
      _cameraIndex = _findCameraIndex(CameraLensDirection.back);
      // **音频轨仅在视频模式下开启**（这是改坏之前的原配置）。
      //
      // 背景：为了给动态照片录环境声，曾把它扩到"非宠物模式即开"甚至全开，
      // 但真机接连出问题——宠物模式闪退（VideoCapture 与 ImageAnalysis 互斥）、
      // 拍照模式快门无响应。动态照片没声音只是体验打折，相机不能用是功能报废，
      // 所以先退回最小配置；等确认稳定后再单独评估动态照片的音频方案。
      await _setupController(
        _cameras[_cameraIndex],
        enableAudio: _modeIndex == 1,
      );
    } on TimeoutException {
      setState(() => _error = '相机加载超时，请检查浏览器相机权限后重试');
    } catch (e) {
      setState(() => _error = '相机启动失败：$e');
    }
  }

  /// 重建相机控制器（**带重入保护**）。
  ///
  /// 重入保护是必需的：连点底部模式胶囊 / 镜头键 / 画质档时，两次调用会并发
  /// 执行——两边各自把 `_controller` 置 null、各自 dispose 旧控制器、各自
  /// 新建。结果是一个 Camerax 会话被泄漏、另一个抢不到相机，表现为
  /// **取景框全黑**或「相机启动失败」。重入请求直接忽略（用户再点一次即可）。
  ///
  /// 实现上拆成包装器 + Inner 两层，是为了不改动原逻辑的缩进与结构。
  Future<void> _setupController(
    CameraDescription desc, {
    bool enableAudio = false,
  }) async {
    if (_switching) {
      debugPrint('[相机] 正在重建控制器，忽略重复请求');
      return;
    }
    _switching = true;
    try {
      await _setupControllerInner(desc, enableAudio: enableAudio);
    } finally {
      _switching = false;
    }
  }

  Future<void> _setupControllerInner(
    CameraDescription desc, {
    // **默认 false，每个调用点必须自己声明。**
    //
    // 这个参数只决定两件事：① 录制是否带音轨 ② 建控制器时是否请求麦克风权限
    // （它并**不决定能否录制**——camera_android_camerax 的 VideoCapture 是首次
    // 调用 startVideoRecording 时才懒绑定的）。
    //
    // 正因为作用隐蔽，之前把它设成过 true 的默认值，结果宠物模式也带上了
    // 音频轨，而 CameraX 下 VideoCapture 与宠物跟踪用的 ImageAnalysis 互斥——
    // 实拍表现就是「一切到宠物模式立刻闪退」。改回必须显式声明，避免再被隐式带偏。
    bool enableAudio = false,
  }) async {
    final previousController = _controller;
    // 关键顺序：先彻底释放旧控制器，再创建新的。
    //
    // Android（Camerax）同一时刻只允许一个相机会话，旧控制器还活着时
    // 新控制器 initialize 必然失败——降级链逐档试遍也全失败，
    // 表现为「切到宠物 / 视频模式后取景框一片黑」。
    // 旧实现是「新的初始化成功后才 dispose 旧的」，在原生端必然踩这个坑。
    _controller = null;
    _recording = false;
    _audioUnsupported = false;
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _error = null;
      });
    }
    if (previousController != null) {
      try {
        await previousController.dispose();
      } catch (_) {}
      // Camerax 释放底层会话是异步的，紧接着就初始化仍会抢不到相机。
      await Future<void>.delayed(_cameraReleaseDelay);
    }

    // 切片A：按降级链逐档尝试。高分辨率初始化失败时自动退到下一档，
    // 而不是一次失败就让整个相机不可用（原实现直接抛「相机启动失败」）。
    for (final preset in _quality.fallbackChain) {
      // 需要音频时先试带音频；部分浏览器/设备不支持音频轨，再退到无声。
      final audioAttempts = enableAudio ? <bool>[true, false] : <bool>[false];
      for (final audio in audioAttempts) {
        final c = await _tryInitialize(desc, preset, audio);
        if (c == null) continue;
        _controller = c;
        _activePreset = preset;
        if (enableAudio && !audio) _audioUnsupported = true;
        if (mounted) setState(() => _isInitialized = true);
        // 切片B：控制器就绪后立即套用当前宠物参数。
        await _applyPetProfile();
        return;
      }
    }

    if (mounted) {
      setState(
        () => _error = '相机启动失败：没有可用的分辨率档位，请检查相机权限后重试',
      );
    }
  }

  /// 用指定预设尝试初始化，失败返回 null（已自行释放，不抛异常）。
  Future<CameraController?> _tryInitialize(
    CameraDescription desc,
    ResolutionPreset preset,
    bool enableAudio,
  ) async {
    final c = CameraController(desc, preset, enableAudio: enableAudio);
    try {
      await c.initialize().timeout(_cameraInitTimeout);
      return c;
    } catch (e) {
      try {
        await c.dispose();
      } catch (_) {}
      debugPrint('[相机] 预设 ${preset.name}(audio=$enableAudio) 初始化失败：$e');
      return null;
    }
  }

  /// 切片B：把当前宠物参数集应用到底层相机。
  ///
  /// 网页端 `camera_web` 未实现曝光/对焦控制，[CameraCapability] 会直接短路，
  /// 因此这里在网页上等同「只记参数、不调硬件」，不会抛异常。
  Future<void> _applyPetProfile() async {
    final c = _controller;
    if (c == null || !_isInitialized) return;
    final p = _profile;

    // 闪光策略：猫 / 兔 / 龙猫禁用闪光，强制关灯（防止伤眼与红眼）。
    if (p.flashPolicy == FlashPolicy.forbidden && _flashOn) {
      _flashOn = false;
    }
    await _capability.applyFlash(
      c,
      _flashOn ? FlashMode.torch : FlashMode.off,
    );

    // 曝光：毛色自适应。白毛加、黑毛减——这是"比系统相机好"的核心一招。
    // 测光点按「宠物眼睛 → 用户点选 → 画面中心」的优先级决定。
    final focusPoint = _resolveFocusPoint();
    await _capability.probeExposureRange(c);
    await _capability.applyExposure(
      c,
      point: focusPoint,
      ev: p.exposureCompensation + _userEvOffset,
    );

    // 对焦：**只保持自动对焦模式，不锁点**（除非用户手动点选过）。
    //
    // 旧实现无条件 setFocusPoint(_resolveFocusPoint())，等于每次都把对焦区
    // 锁在画面中心；而宠物抓拍十有八九不在正中（猫在画面左侧就是典型），
    // 结果主体虚焦、背景清晰——用户反馈的"拍出来模糊"多半来自这里。
    // 传 null 时 applyFocus 只 setFocusMode(auto)，让相机自己对整个场景 AF；
    // 用户点屏指定过对焦点时才锁到那个点（切片F接入眼睛模型后改为锁眼睛）。
    await _capability.applyFocus(c, point: _focusNormalized);

    if (mounted) setState(() {});
  }

  /// 根据镜头方向找到最合适的摄像头。
  int _findCameraIndex(CameraLensDirection direction) {
    final preferredIndex = _cameras.indexWhere(
      (camera) => camera.lensDirection == direction,
    );
    if (preferredIndex >= 0) return preferredIndex;
    final backIndex = _cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    if (backIndex >= 0) return backIndex;
    return 0;
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null || !_isInitialized) return;

    // 猫 / 兔 / 龙猫禁用闪光：伤眼，且白化种会拍出红眼。
    // 这里直接拦截，而不是让用户开了再解释。
    final policy = _profile.flashPolicy;
    if (!_flashOn && policy == FlashPolicy.forbidden) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_species.label}不建议使用闪光灯：${policy.reason}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    _flashOn = !_flashOn;
    await _capability.applyFlash(
      c,
      _flashOn ? FlashMode.torch : FlashMode.off,
    );
    if (mounted) setState(() {});
  }

  /// 切换物种 / 毛色 / 场景后重新套用参数（切片B）。
  ///
  /// 只改维度并重算参数，不重建相机控制器，避免取景框闪一下。
  Future<void> _updatePetProfile({
    PetSpecies? species,
    PetCoat? coat,
    PetScene? scene,
    PetLook? look,
  }) async {
    if (species != null) _species = species;
    if (coat != null) _coat = coat;
    if (scene != null) _scene = scene;
    if (look != null) _look = look;
    if (mounted) setState(() {});
    await _applyPetProfile();
    if (species != null) await _applySpeciesVolume();
  }

  /// 自动识别宠物并直接套用参数。
  ///
  /// 流程：抓一帧（**不保存**，只用于分析）→ 本地毛色分析 → 物种识别（若可用）
  /// → 合成参数集。目的是让用户「打开相机就能拍」，而不是从 4×5×5 个组合里自己挑。
  ///
  /// 抓的这一帧只喂给分析，不会进相册，也不会触发滤镜。
  Future<void> _autoDetectPet() async {
    final c = _controller;
    if (c == null || !_isInitialized || _autoDetecting || _recording) return;
    if (mounted) setState(() => _autoDetecting = true);
    // 抓帧要独占相机会话：图像流与拍照在 Android 上会互相抢占。
    final paused = await _pauseTracking();
    try {
      final shot = await c.takePicture().timeout(_autoDetectTimeout);
      final bytes = await shot.readAsBytes();

      // 毛色分析放 isolate（网页端 compute 会退化为同步执行）。
      final coat = await compute(runPetCoatAnalysis, (
        bytes: bytes,
        sampleTarget: 160,
      ));

      // 物种识别走平台能力（ML Kit / 云端）。
      // 未接入时 isAvailable 为 false，直接跳过——此时
      // PetAutoProfiler 会沿用当前物种并标记"需要用户确认"，
      // 这是如实告知，而不是假装识别成功。
      PetSpeciesGuess? guess;
      if (_speciesDetector.isAvailable) {
        // width/height 传 0：ML Kit 这类实现用文件路径入参，
        // 不需要调用方先解一遍图（省一次内存拷贝）。
        guess = await _speciesDetector.detect(bytes, width: 0, height: 0);
      }

      final setup = PetAutoProfiler.resolve(
        coat: coat,
        speciesGuess: guess,
        fallbackSpecies: _species,
      );
      if (!mounted) return;
      setState(() {
        _species = setup.species;
        _coat = setup.coat;
        _lastAutoSetup = setup;
        _autoDetectedThisSession = true;
      });
      await _applyPetProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(setup.summary),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('[自动识别] 失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('自动识别失败，可在「宠物参数」里手动选择'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _autoDetecting = false);
      await _resumeTracking(paused);
    }
  }

  /// 切换画质档位（切片A）。
  ///
  /// 分辨率只能在创建 [CameraController] 时指定，所以改档位必须重建控制器。
  Future<void> _changeQuality(CaptureQuality quality) async {
    if (quality == _quality || _recording || _cameras.isEmpty) return;
    // 动态短片正在录：先让它收尾再重建控制器。否则旧控制器被 dispose 后，
    // 录制会在它身上抛异常，这一张的动态就白录了（照片本身不受影响）。
    await _stopLiveClipEarly();
    _quality = quality;
    if (mounted) setState(() {});
    await _setupController(
      _cameras[_cameraIndex],
      // 恒开音频轨：动态照片要录下环境声（对齐 iOS 实况照片），而音轨只能
      // 在 initialize 时确定。
      //
      // 注意**不是**为了"绑定 VideoCapture 用例"——camera_android_camerax 的
      // VideoCapture 是首次调用 startVideoRecording 时才懒绑定的，
      // enableAudio 并不决定能否录制，它只决定两件事：
      //   ① 录制是否带音轨   ② 建控制器时是否请求麦克风权限
      //
      // 仅在视频模式开启（原配置），原因见 _initCamera 的说明。
      enableAudio: _modeIndex == 1,
    );
  }

  /// 当前实际生效的分辨率档位文案（降级后可能低于所选档位）。
  String get _activePresetLabel {
    switch (_activePreset) {
      case ResolutionPreset.low:
        return '240p';
      case ResolutionPreset.medium:
        return '480p';
      case ResolutionPreset.high:
        return '720p';
      case ResolutionPreset.veryHigh:
        return '1080p';
      case ResolutionPreset.ultraHigh:
        return '2160p';
      case ResolutionPreset.max:
        return '设备最高';
      case null:
        return '—';
    }
  }

  /// 所选档位没跑起来时提示用户已自动降级。
  String get _downgradeHint {
    if (_activePreset == null || _activePreset == _quality.preset) return '';
    return '（设备不支持「${_quality.label}」，已自动降级到可用档位）';
  }

  /// 切片E：播放/停止引诱音效。
  ///
  /// 第一次播放时按物种设置默认音量——猫与龙猫听觉更敏感，音量低一档，
  /// 既不容易吓到宠物，也不至于在家外放扰民。
  Future<void> _toggleLureSound(LureSound sound) async {
    if (_lurePlayer.current == null) {
      await _lurePlayer.setVolume(defaultVolumeFor(_species));
    }
    await _lurePlayer.toggle(sound);
    if (mounted) setState(() {});
  }

  /// 切换物种时同步调整音量档位。
  Future<void> _applySpeciesVolume() async {
    if (!_lurePlayer.isPlaying) return;
    await _lurePlayer.setVolume(defaultVolumeFor(_species));
  }

  // ───────────── 切片C：曝光 / 对焦 / 缩放 ─────────────

  /// 点按取景框 = 在该点同时完成「测光」与「对焦」。
  ///
  /// 这是把相机从"全自动"变成"可控"的最短路径，也是手机摄影里最常用的
  /// 一个动作。宠物眼睛在哪就点哪，比让相机自己猜准得多。
  Future<void> _handleTapToFocus(
    Offset localPosition,
    Size viewport,
    Size scaledPreview,
  ) async {
    if (scaledPreview.width <= 0 || scaledPreview.height <= 0) return;
    // 预览做了 cover 缩放 + 居中裁切，必须把点击位置反解回预览坐标系，
    // 否则越靠画面边缘的点偏移越大。
    final originX = (viewport.width - scaledPreview.width) / 2;
    final originY = (viewport.height - scaledPreview.height) / 2;
    var nx = ((localPosition.dx - originX) / scaledPreview.width).clamp(
      0.0,
      1.0,
    );
    final ny = ((localPosition.dy - originY) / scaledPreview.height).clamp(
      0.0,
      1.0,
    );
    // 前置摄像头预览是镜像显示的：屏幕左边对应传感器右边，不翻转的话
    // 对焦点会落到点击位置的镜像一侧（后置不受影响）。
    // 若真机验证发现前置左右仍相反，删掉这一段即可。
    final isFront =
        _cameraIndex < _cameras.length &&
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
    if (isFront) nx = 1.0 - nx;
    if (mounted) {
      setState(() {
        _focusTapLocal = localPosition;
        _focusNormalized = Offset(nx, ny);
      });
    }
    await _applyFocusAndExposure(_focusNormalized);
    // 对焦框 1.2 秒后淡出，不长期挡画面。
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _focusTapLocal = null);
  }

  /// 把对焦点与曝光补偿一起送给相机。
  ///
  /// 曝光值 = 物种/毛色算出的基准 **+** 用户手动微调。
  /// 网页端 [CameraCapability] 会直接短路，因此这里不抛异常、只是不生效。
  Future<void> _applyFocusAndExposure(Offset? point) async {
    final c = _controller;
    if (c == null || !_isInitialized) return;
    await _capability.applyExposure(
      c,
      point: point,
      ev: _profile.exposureCompensation + _userEvOffset,
    );
    await _capability.applyFocus(c, point: point);
  }

  /// 双指缩放。
  void _handleZoomUpdate(ScaleUpdateDetails details) {
    // 单指拖动不触发缩放——否则点按对焦会和缩放抢手势。
    if (details.pointerCount < 2) return;
    final next = (_zoomAtGestureStart * details.scale).clamp(1.0, 8.0);
    if ((next - _zoom).abs() < 0.02) return;
    _zoom = next;
    if (mounted) setState(() {});
    final c = _controller;
    if (c != null) _capability.applyZoom(c, _zoom);
  }

  /// 复位对焦、曝光微调与缩放。
  ///
  /// 只改本页状态——相机的实际参数由随后的 `_setupController` → `_applyPetProfile`
  /// 统一重新下发，免得在即将销毁的旧控制器上白做一轮调用。
  void _resetFocusAndZoom() {
    _focusNormalized = null;
    _focusTapLocal = null;
    _zoom = 1.0;
  }

  /// 切片F：决定本次对焦/测光用哪个点。
  ///
  /// 优先级：**宠物眼睛 → 用户点选的位置 → 画面中心**。
  /// 眼睛排在最前，是因为宠物摄影的第一原则是「眼神 > 构图」——
  /// 眼睛糊了，整张就是废片。
  ///
  /// 说明：`_eyeDetector` 目前是 [NoPetEyeDetector]（关键点模型尚未接入），
  /// `isAvailable` 恒为 false，于是自动退回后两级。模型接进来后这里无需改动，
  /// 只需补一个"低频抓帧 → detect → 写入 `_lastEyeResult`"的循环——
  /// 注意网页端不支持 `startImageStream`，必须走定时抓帧而不是逐帧推理。
  Offset _resolveFocusPoint() {
    if (_eyeDetector.isAvailable) {
      final eye = PetEyeTargeting.nearestEye(_lastEyeResult);
      if (eye != null) return eye;
    }
    return _focusNormalized ?? const Offset(0.5, 0.5);
  }

  // ───────────── 实时宠物跟踪：帧流 → 检测 → 对焦 ─────────────

  /// 按当前模式同步图像流的开关（只有宠物模式 + 原生端才开启）。
  ///
  /// 图像流与预览/拍照在 Android 上会争抢相机会话，因此：
  ///   - 仅在宠物模式下开启（其他模式零开销）
  ///   - 拍照前必须停流，拍完再恢复（否则 takePicture 可能失败）
  ///   - 任何失败都退回"不跟踪"，绝不让跟踪拖垮取景
  Future<void> _syncTracking() async {
    final wantTracking = _modeIndex == 2 && PetDetector.isAvailable;
    if (wantTracking == _streaming) return;
    final c = _controller;
    if (c == null || !_isInitialized) return;
    try {
      if (wantTracking) {
        await c.startImageStream(_onCameraFrame);
        _streaming = true;
      } else {
        await c.stopImageStream();
        _streaming = false;
        if (mounted) setState(() => _detections = const []);
      }
    } catch (e) {
      debugPrint('[宠物跟踪] 图像流切换失败，本次会话不跟踪：$e');
      _streaming = false;
    }
  }

  /// 临时让出图像流：拍照 / 抓帧需要独占相机会话
  /// （Android 上图像流与 takePicture 会互相抢占，不停流拍照可能直接失败）。
  /// 返回原本是否在流中，供 [_resumeTracking] 恢复。
  Future<bool> _pauseTracking() async {
    if (!_streaming) return false;
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    _streaming = false;
    // 等正在进行的这一次推理跑完再返回。
    //
    // 停流只是不再产生新帧，但可能已经有一帧正在 TFLite 里跑：那一次推理
    // 自己占着解释器与中间张量，与紧接着的连拍/融合叠加，会在内存紧张的
    // 机型上顶穿进程上限——宠物模式拍照比普通模式更容易闪退，差别就在这里。
    // 最多等 1 秒，超时也放行：宁可冒内存风险，也不能让快门卡死。
    for (var i = 0; i < 50 && _detecting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return true;
  }

  /// 恢复此前让出的图像流。
  Future<void> _resumeTracking(bool wasStreaming) async {
    if (!wasStreaming || !mounted) return;
    await _syncTracking();
  }

  /// 帧流回调（在平台的图像线程上触发，回到 Dart 后要尽快返回）。
  void _onCameraFrame(CameraImage image) {
    _frameTick++;
    if (_frameTick % _detectFrameStride != 0) return;
    if (_detecting || !mounted) return; // 上一帧还没算完就直接丢弃，不排队
    _detecting = true;
    unawaited(_runFrameDetection(image));
  }

  Future<void> _runFrameDetection(CameraImage image) async {
    try {
      final rgb = cameraFrameToRgb(
        width: image.width,
        height: image.height,
        planes: image.planes.map((p) => p.bytes).toList(growable: false),
        bytesPerRow: image.planes
            .map((p) => p.bytesPerRow)
            .toList(growable: false),
        bytesPerPixel: image.planes
            .map((p) => p.bytesPerPixel ?? 1)
            .toList(growable: false),
        format: _frameFormatOf(image.format.group),
      );
      if (rgb == null) return;
      final found = await PetDetector.detect(rgb);
      if (!mounted) return;
      setState(() => _detections = found);
      await _trackFocusToPet(found);
    } catch (e) {
      debugPrint('[宠物跟踪] 帧处理失败：$e');
    } finally {
      _detecting = false;
    }
  }

  FrameFormat _frameFormatOf(ImageFormatGroup group) {
    switch (group) {
      case ImageFormatGroup.yuv420:
        return FrameFormat.yuv420;
      case ImageFormatGroup.bgra8888:
        return FrameFormat.bgra8888;
      default:
        return FrameFormat.unknown;
    }
  }

  /// 把对焦点跟到宠物身上。
  ///
  /// 三条抑制规则，缺一个体验就崩：
  ///   1. 用户手动点选过对焦点 → 尊重用户，不再自动抢；
  ///   2. 宠物位置没怎么动且距上次对焦不久 → 跳过（否则对焦马达持续抽动）；
  ///   3. 没检测到宠物 → 什么也不做，保持上一次对焦。
  Future<void> _trackFocusToPet(List<PetDetection> found) async {
    final c = _controller;
    if (c == null || !_isInitialized || found.isEmpty) return;
    if (_focusNormalized != null) return;

    final pet = found.first;
    final target = _framePointToPreview(pet.centerX, pet.centerY);
    final last = _lastTrackedFocus;
    final lastAt = _lastTrackedFocusAt;
    final now = DateTime.now();
    if (last != null &&
        lastAt != null &&
        (target - last).distance < _trackFocusMoveThreshold &&
        now.difference(lastAt) < _trackFocusInterval) {
      return;
    }
    _lastTrackedFocus = target;
    _lastTrackedFocusAt = now;
    await _capability.applyFocus(c, point: target);
  }

  /// 帧坐标 → 预览坐标（归一化）。
  ///
  /// Android 的相机帧是**横向**的（sensor 原始输出），而预览在竖屏手机上
  /// 旋转 90° 显示；`setFocusPoint` 要的是**预览坐标系**，所以必须转一次。
  /// 后置摄像头按顺时针 90° 处理。**若真机上发现对焦点落在镜像位置，
  /// 只改这一行即可**——这是唯一需要按机型校准的地方。
  Offset _framePointToPreview(double fx, double fy) =>
      Offset((1.0 - fy).clamp(0.0, 1.0), fx.clamp(0.0, 1.0));

  /// 检测框 → 取景区内的屏幕矩形（含上面那次旋转）。
  Rect _detectionRect(PetDetection d, Size viewport) {
    final p1 = _framePointToPreview(d.left, d.top);
    final p2 = _framePointToPreview(d.right, d.bottom);
    final left = math.min(p1.dx, p2.dx);
    final right = math.max(p1.dx, p2.dx);
    final top = math.min(p1.dy, p2.dy);
    final bottom = math.max(p1.dy, p2.dy);
    return Rect.fromLTRB(
      left * viewport.width,
      top * viewport.height,
      right * viewport.width,
      bottom * viewport.height,
    );
  }

  /// 切片G：按当前档位连拍，并返回最清晰的一张。
  ///
  /// 单张时直接返回、不做评分。多张时把解码与打分放到 isolate 上
  /// （网页端 `compute` 会退化为同步执行）。任何失败都退回最后一张——
  /// 选帧不成功也绝不能让用户按了快门却没有照片。
  /// 连拍，返回**全部帧**（交给 [_fuseFrames] 做多帧融合）。
  Future<List<Uint8List>> _captureBurst() async {
    final count = _burstShots.count;
    final shots = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      // 单张加超时：相机处于异常状态时 takePicture 可能**永久不返回**，
      // 会把整条拍照链路连同快门标志一起挂死（实拍反馈的"点了没反应"）。
      //
      // 超时后的策略：**已经拍到几张就用几张**，不因为最后一张卡住就把整次
      // 拍照判死。5 连拍要连开 5 次快门，中途卡一张很常见；为了第 5 张丢掉
      // 前 4 张（用户白按一次快门）比少融合几帧严重得多。
      try {
        final shot = await _controller!
            .takePicture()
            .timeout(const Duration(seconds: 8));
        shots.add(await shot.readAsBytes());
      } catch (e) {
        // 一张都没拿到 → 这次确实拍不出来，交给 _takePicture 统一报错。
        if (shots.isEmpty) rethrow;
        debugPrint('[连拍] 第 ${i + 1}/$count 张失败，用已拍到的 ${shots.length} 张继续：$e');
        break;
      }
    }
    return shots;
  }

  /// 把连拍帧融合成一张成片。
  ///
  /// 两步配合，各司其职：
  ///   1. **选帧**——挑出最清晰的一帧当参考帧（保证清晰度不被融合拖累）；
  ///   2. **融合**——其余帧对齐到它做抗离群平均，把随机噪声压掉约 40%。
  ///
  /// 这是"画质优于原生相机"的核心手段：单帧后处理只能靠"模糊换降噪"，
  /// 而多帧融合是**降噪但完全不动细节**。
  ///
  /// **两步合并成一次 compute**：旧实现先跑选帧、再跑融合，各自把每帧
  /// **全尺寸**解码一遍——同一批字节被纯 Dart JPEG 解码 2N 次（5 连拍
  /// 就是 10 次，单帧解码几百毫秒），这是「连拍非常慢」的最大一笔开销。
  /// 现在由 [fuseFramesWithPick] 一次解码同时完成打分与融合，只解 N 次。
  Future<Uint8List> _fuseFrames(List<Uint8List> frames) async {
    if (frames.isEmpty) {
      throw StateError('没有拍到画面，请重试');
    }
    if (frames.length == 1) {
      _lastBurstPick = null;
      return frames.first;
    }

    try {
      // 加超时：这两步此前**没有任何上限**，一旦卡住就是"永远正在拍摄中"
      // （快门被 _capturing 锁死，用户只能杀掉页面）。
      final result = await compute(fuseFramesWithPick, (
        frames: frames,
        maxSide: kIsWeb ? 1800 : _fusionMaxSide,
        jpegQuality: PetFilter.defaultJpegQuality,
        sampleTarget: 320,
      )).timeout(const Duration(seconds: 25));
      _lastBurstPick = result.total > 1
          ? (index: result.pickedIndex, total: result.total)
          : null;
      return result.bytes;
    } catch (e) {
      // 融合是加分项：超时/失败都退回**参考帧**这张完整成片，
      // 宁可噪一点，也不能让用户按了快门却什么也拿不到。
      debugPrint('[融合] 失败，退回参考帧：$e');
      _lastBurstPick = null;
      return frames.first;
    }
  }

  /// 切片D：对刚拍下的原始照片套用当前宠物滤镜。
  ///
  /// 放在 isolate 上跑（网页端 `compute` 会退化为同步执行），
  /// 任何失败都原样返回原图——滤镜出问题绝不能让用户丢照片。
  Future<Uint8List> _applyPetFilter(Uint8List raw) async {
    if (!_filterEnabled) return raw;
    var busy = false;
    try {
      final request = PetFilter.buildRequest(
        raw,
        _profile,
        // 原生端相机已通过硬件加过曝光补偿，这里不重复加；
        // 网页端没有硬件补偿，必须靠滤镜的数字增益兜底，
        // 否则白毛提不亮、黑毛压不暗——"比系统相机好"就落空了。
        exposureAlreadyApplied: _capability.exposureSupported,
        // 网页端 dart2js 的逐像素性能明显弱于原生 AOT，长边压到 1800
        // 换取可接受的等待时间；原生端保留 2400。
        maxSide: kIsWeb ? 1800 : PetFilter.defaultMaxSide,
        // 把检测到的宠物框带给滤镜：眼区/泪痕锚定框内、清晰度按主体分区。
        subjectRect: _subjectRectForFilter(),
      );
      if (mounted) {
        busy = true;
        setState(() => _filtering = true);
        // 关键：先让出一次事件循环，把"处理中"这一帧真正画出来再开算。
        // 网页端 compute 是同步执行的，不让出的话界面会被冻住，
        // 提示文案一个字都看不到。
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      // 同融合：没有超时的话，一次慢到极致的调色会把快门永久锁死。
      return await compute(runPetFilter, request).timeout(
        const Duration(seconds: 25),
      );
    } catch (e) {
      debugPrint('[滤镜] 处理失败，改用原图：$e');
      return raw;
    } finally {
      if (busy && mounted) setState(() => _filtering = false);
    }
  }

  /// 取当前检测到的宠物框，转成滤镜用的归一化坐标 record。
  ///
  /// 检测框来自 startImageStream 的完整 sensor 帧，与 takePicture 的成片
  /// 同一坐标系（都是 sensor 全幅，未经过显示层的 cover 裁切），故直接透传。
  /// 没检测到宠物 → null，滤镜的眼区/主体分区退回画面中央近似。
  ({double left, double top, double right, double bottom})?
  _subjectRectForFilter() {
    if (_detections.isEmpty) return null;
    // _detections 已按置信度降序，第一个即主目标。
    final d = _detections.first;
    return (left: d.left, top: d.top, right: d.right, bottom: d.bottom);
  }

  Future<void> _switchLens() async {
    if (_cameras.length < 2 || _recording) return;
    // 动态短片正在录：先收尾再重建控制器，否则录制会落在被 dispose 的
    // 旧控制器上而抛异常，丢掉这一张的动态。
    await _stopLiveClipEarly();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    // 换镜头后原来的对焦点与缩放不再适用，先复位再重建控制器。
    _resetFocusAndZoom();
    await _setupController(
      _cameras[_cameraIndex],
      // 仅在视频模式开启（原因见 _initCamera 的说明）。
      enableAudio: _modeIndex == 1,
    );
  }

  void _cyclePhotoRatio() {
    setState(() {
      _photoRatioIndex = (_photoRatioIndex + 1) % _photoRatioLabels.length;
    });
  }

  /// 切换动态照片开关。
  ///
  /// 宠物模式下拦截：CameraX 的 VideoCapture 与 ImageAnalysis（宠物实时
  /// 追踪依赖的图像流）互斥，同时开启会导致相机会话初始化失败——即取景框
  /// 全黑。与其让用户开一个"看起来能用、实际拍不出动态"的开关，不如直说。
  void _toggleLivePhoto() {
    if (_modeIndex == 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('宠物模式要实时追踪，与动态照片不能同时开启，请切到「拍照」模式'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    ref
        .read(livePhotoEnabledProvider.notifier)
        .setEnabled(!ref.read(livePhotoEnabledProvider));
  }

  Future<void> _capture() async {
    if (_controller == null || !_isInitialized) {
      // 相机尚未就绪（仍在初始化、或启动失败）时这里原本是**静默 return**：
      // 用户看到取景框（或加载态）却按快门毫无反应，正是"点了没反应"的
      // 一号来源。把原因明确回给用户，顺带把失败信息带出来。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_error ?? '相机还没准备好，请稍候再试'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    if (_modeIndex == 1) {
      await _toggleRecording();
      return;
    }
    // 快门去重：快门挂在 onTapDown 上，连点会让两次连拍在同一控制器上
    // 交错——轻则串帧，重则 takePicture 抛异常把照片丢掉。
    //
    // 看门狗：去重本身有风险——底层 takePicture 一旦永久挂起（相机异常时
    // 并不罕见），这个标志会永远是 true，表现就是「快门彻底没反应」
    // （实拍反馈过）。超过 30 秒强制复位：宁可偶发重入，
    // 也不能让用户永久失去快门。
    final now = DateTime.now();
    if (_capturing) {
      final since = _capturingSince;
      if (since != null && now.difference(since).inSeconds < 30) return;
      debugPrint('[快门] 上一次拍照超过 30 秒未结束，强制复位');
    }
    _capturing = true;
    _capturingSince = now;
    try {
      // 按下的第一帧就给出反馈，别让连拍/融合这几秒的空白被当成"没反应"。
      if (mounted) setState(() => _shootingHint = '正在拍摄…');
      // 动态短片正在录：先让它提前收尾，把相机让给拍照。
      if (!await _stopLiveClipEarly()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('上一段动态正在收尾，请稍候再拍'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        return;
      }
      await _takePicture();
    } finally {
      _capturing = false;
      _capturingSince = null;
      if (mounted) setState(() => _shootingHint = null);
    }
  }

  /// 请求正在录制的动态短片提前收尾，并**等它真正停止**。
  ///
  /// 返回 true = 相机已让出来（可以拍照）；false = 等超时了它还没停。
  ///
  /// 为什么必须等：CameraX 同一时刻只接受一个采集请求，硬抢会让
  /// takePicture 直接失败——那意味着"照片丢了"，比没有动态照片严重得多。
  /// 所以超时宁可**放弃这次拍照**并明确告诉用户，也不去赌。
  /// 录制循环每 20ms 检查一次 [_liveAbort]，正常在 100ms 内收尾。
  Future<bool> _stopLiveClipEarly() async {
    if (!_liveRecording) return true;
    _liveAbort = true;
    for (var i = 0; i < 25 && _liveRecording; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return !_liveRecording;
  }

  /// 动态照片：拍照完成后自动录一小段短片，关联到刚拍的那张照片。
  ///
  /// 为什么录的是"之后"而不是苹果那样的"前后各 1.5 秒"：拍照走多帧融合，
  /// 连拍期间独占相机会话，无法同时抓帧流。二者只能取其一，这里保画质。
  ///
  /// 全程静默降级：任何失败都只是"这张没有动态照片"，绝不影响已经拍到手的
  /// 照片。Web 端 `PhotoStorage.saveLive` 返回 null，自然跳过。
  Future<void> _captureLiveClip(CapturedPhoto photo) async {
    // 上一段还在录 → 跳过这张（相机同一时刻只能录一路）。
    if (_liveRecording || _recording || _liveAbort) return;
    final c = _controller;
    if (c == null || !_isInitialized) return;

    setState(() => _liveRecording = true);
    try {
      // 加超时：相机异常时 startVideoRecording 可能**永不返回**，那样
      // _liveRecording 会永远停在 true，快门被 _stopLiveClipEarly 永久拦截
      // （表现为每次按快门都提示"上一段动态正在收尾"）——与之前快门卡死
      // 属同一类"一个标志卡死全功能"的问题。
      await c.startVideoRecording().timeout(const Duration(seconds: 5));
      // 分段等待而非一次睡满：用户中途按快门时能立刻收尾。
      final deadline = DateTime.now().add(
        const Duration(seconds: liveClipSeconds),
      );
      while (DateTime.now().isBefore(deadline) && !_liveAbort) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // 用捕获的 c 停止，而不是重新读 _controller：等待期间用户可能切了
      // 镜头/模式，_controller 已是另一个实例，去停它只会抛异常。
      final file = await c.stopVideoRecording();
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      final path = await PhotoStorage.saveLive(
        bytes,
        takenAt: photo.takenAt,
      );
      if (path == null || !mounted) return;
      ref.read(capturedPhotosProvider.notifier).attachLive(photo, path);
    } catch (e) {
      debugPrint('[动态照片] 录制失败，跳过：$e');
      // 失败可能留下半个文件，清掉避免成为孤儿。
      unawaited(PhotoStorage.deleteLive(photo.takenAt));
    } finally {
      _liveAbort = false;
      if (mounted) setState(() => _liveRecording = false);
    }
  }

  /// 拍照并在保存前按设置的比例生成最终成片。
  /// 比例外区域补纯黑，避免直接裁掉原图内容。
  Future<void> _takePicture() async {
    if (_controller == null || !_isInitialized) return;
    // 拍照要独占相机会话：宠物模式下图像流正开着，必须先让出来。
    final paused = await _pauseTracking();
    try {
      // 切片G：先连拍（单张时就是普通拍照）。
      final frames = await _captureBurst();
      // 切片H：多帧融合 —— 选最清晰的一帧作参考，其余帧对齐后融合降噪。
      // 阶段提示分细：这一步是整条链路的耗时大头，卡住时要能一眼看出。
      if (mounted) setState(() => _shootingHint = '正在合成…');
      final rawBytes = await _fuseFrames(frames);
      // 切片D：先套宠物滤镜（调色 + 美颜），再按所选比例加框。
      // 顺序很重要——先加框的话，黑边也会被卷进滤镜计算。
      // 交棒给 _filtering：它有自己的文案，这里先把通用提示撤掉。
      if (mounted) setState(() => _shootingHint = null);
      final filtered = await _applyPetFilter(rawBytes);
      final bytes = await _composePhotoToSelectedRatio(filtered);
      // 本地即时展示。返回的时间戳用于关联稍后录完的动态短片。
      final photo = ref.read(capturedPhotosProvider.notifier).add(bytes);
      // 动态照片：照片已经进列表了，短片在后台补录、录完再关联回来。
      // 这里**不能 await**——否则用户按完快门要干等 2 秒才能继续拍。
      // 宠物模式不录（VideoCapture 与它的实时图像流互斥，见 _setupController）。
      if (_modeIndex != 2 && ref.read(livePhotoEnabledProvider)) {
        unawaited(_captureLiveClip(photo));
      }
      // 自动存进系统相册。
      //
      // 原生相机拍完照片就躺在系统相册里，而我们的成片原先只活在 App 内部，
      // 用户想发朋友圈/给别人看还得回 App 手动导出——这违背了"相机"的直觉
      // （实拍反馈"原始照片不能下载"就是这一条）。这里拍到就存。
      // 失败不打扰用户：相册权限被拒时，照片仍在 App 相册与云端。
      unawaited(() async {
        final problem = await savePhotoToGallery(bytes);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(problem ?? '已保存到系统相册'),
            duration: const Duration(seconds: 2),
          ),
        );
      }());
      // 异步上传 COS 并登记 works.json（失败不阻断拍摄流程）。
      unawaited(() async {
        try {
          await ref
              .read(worksProvider.notifier)
              .add(
                bytes: bytes,
                type: LibraryType.capturedPhoto,
                ext: 'jpg',
                label: '拍摄照片',
              );
        } catch (e) {
          debugPrint('[拍照] 上传 COS 失败：$e');
        }
      }());
      setState(() {
        _captured = true;
        _lastBytes = bytes;
      });
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) setState(() => _captured = false);

      // 连拍时告诉用户"自动选了第几张"，否则用户不知道发生了什么。
      final pick = _lastBurstPick;
      if (pick != null && pick.total > 1 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已从 ${pick.total} 张里自动选出最清晰的第 ${pick.index + 1} 张',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拍照失败：$e')));
      }
    } finally {
      await _resumeTracking(paused);
    }
  }

  /// 按当前照片比例输出带黑边的成片。
  /// 这里保留原图完整内容，只在比例外补纯黑区域。
  ///
  /// 内存注意（「拍照后闪退」的两大来源）：
  ///  1. 合成结果要转 rawRgba（4 字节/像素）才能编 JPEG，4000px 就是 48MB，
  ///     跨 isolate 还要再拷一份 —— 因此输出长边封顶到与滤镜同一档。
  ///  2. `ui.Image` / `ui.Picture` / `ui.Codec` 占的是**引擎侧内存**，
  ///     Dart GC 的 finalizer 回收很慢；不显式 dispose，连拍几张就会把
  ///     进程内存顶爆被系统杀掉。旧实现在这三处全都泄漏。
  Future<Uint8List> _composePhotoToSelectedRatio(Uint8List bytes) async {
    final targetRatio = _photoRatioValues[_photoRatioIndex];
    // 原图比例无需补边，连解码都省掉。
    if (targetRatio == null) return bytes;

    ui.Codec? codec;
    ui.Image? source;
    ui.Picture? picture;
    ui.Image? composed;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final sourceImage = frame.image;
      source = sourceImage;
      final sourceWidth = sourceImage.width.toDouble();
      final sourceHeight = sourceImage.height.toDouble();

      // UI 里的比例值是「竖屏视角」（`3/4` 表示 3:4、`9/16` 表示 9:16），
      // 而相机传感器出图是**横向**的（如 4000×3000）。
      //
      // 直接套用会把横图塞进竖框：源图缩到 2250×1687 后两侧补满黑边，
      // 用户看到的就是"拍出来变窄了"。这里按源图方向换算一次——
      // 横图取倒数，让「4:3」真的输出 4:3 横图、满幅无黑边。
      final effectiveRatio = sourceWidth >= sourceHeight
          ? 1 / targetRatio
          : targetRatio;

      // 目标宽高由原图长边决定，但不超过封顶值（内存保护）。
      final maxSide = math.min(
        math.max(sourceWidth, sourceHeight),
        PetFilter.defaultMaxSide.toDouble(),
      );
      late final int outputWidth;
      late final int outputHeight;
      if (effectiveRatio >= 1) {
        outputWidth = maxSide.round();
        outputHeight = (maxSide / effectiveRatio).round();
      } else {
        outputHeight = maxSide.round();
        outputWidth = (maxSide * effectiveRatio).round();
      }

      // 使用 contain 方式完整放下原图，剩余区域用纯黑补齐。
      final scale = math.min(
        outputWidth / sourceWidth,
        outputHeight / sourceHeight,
      );
      final drawWidth = sourceWidth * scale;
      final drawHeight = sourceHeight * scale;
      final offsetX = (outputWidth - drawWidth) / 2;
      final offsetY = (outputHeight - drawHeight) / 2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        Paint()..color = const Color(0xFF000000),
      );
      canvas.drawImageRect(
        sourceImage,
        Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
        Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight),
        // 默认 FilterQuality.none 是**最近邻**采样：选非原图比例时这里实际
        // 在做缩放（如 4:3 档缩到 0.75×），会丢像素、产生锯齿与摩尔纹。
        // 改成 medium（双线性）让缩放平滑——这是"看起来更清楚"里最廉价的一处。
        Paint()..filterQuality = FilterQuality.medium,
      );
      picture = recorder.endRecording();
      composed = await picture.toImage(outputWidth, outputHeight);
      final byteData = await composed.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final rgba = byteData?.buffer.asUint8List();
      if (rgba == null) return bytes;
      // 输出 JPEG 而非 PNG：PNG 无损会把 12MP 成片撑到十几 MB，
      // 且此前一直以 ext:'jpg' 上传，扩展名与实际编码不符。
      //
      // 用 TransferableTypedData **移交**像素，而不是直接传 Uint8List：
      // 后者会被 compute 复制一份（3000px 就是 27MB），而这一步已在拍照
      // 链路的尾端、内存余量最小。移交后本地 rgba 即失效——这里本来
      // 也不再读它。
      return await compute(
        encodeJpegFromTransferable,
        (TransferableTypedData.fromList([rgba]), outputWidth, outputHeight),
      ).timeout(const Duration(seconds: 25));
    } catch (e) {
      debugPrint('[比例合成] 失败，改用原图：$e');
      return bytes;
    } finally {
      composed?.dispose();
      picture?.dispose();
      source?.dispose();
      codec?.dispose();
    }
  }

  /// 视频模式：开始/停止录制。停止后把视频字节存入短片库，可在「一键成片」加字幕配乐。
  Future<void> _toggleRecording() async {
    if (_controller == null || !_isInitialized) return;
    if (_recording) {
      // 停止录制
      try {
        final x = await _controller!.stopVideoRecording();
        final bytes = await x.readAsBytes();
        ref
            .read(shortVideosProvider.notifier)
            .add(
              ShortVideoEdit(
                videoBytes: bytes,
                // camera_web 录制为 webm（iPhone Safari 同为 Web 端）
                mimeType: 'video/webm',
                trimStartMs: 0,
                trimEndMs: 0,
                caption: '',
                captionStyle: 0,
              ),
            );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('视频已存入短片库')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('停止录制失败：$e')));
        }
      } finally {
        if (mounted) setState(() => _recording = false);
      }
      return;
    }
    // 开始录制
    try {
      await _controller!.startVideoRecording();
      if (mounted) setState(() => _recording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('开始录制失败：$e')));
      }
    }
  }

  /// 切换拍照/视频/宠物模式；进入视频模式时重建控制器以开启音频轨。
  Future<void> _switchMode(int i) async {
    if (i == _modeIndex || _recording || _cameras.isEmpty) return;
    // 动态短片正在录：先收尾再重建控制器，否则录制会落在被 dispose 的
    // 旧控制器上抛异常，丢掉这一张的动态。
    await _stopLiveClipEarly();
    // 切模式会重建控制器，对焦点与缩放先复位。
    _resetFocusAndZoom();
    setState(() {
      _modeIndex = i;
      _audioUnsupported = false;
    });
    // 仅在视频模式开启音频轨（原因见 _initCamera 的说明）。
    await _setupController(_cameras[_cameraIndex], enableAudio: i == 1);
    // 进入宠物模式时自动识别一次——这才叫"打开相机就能拍"，
    // 而不是"打开相机先选四个维度"。整个会话只自动跑一次，
    // 之后由用户点按钮手动重跑。
    // 实时跟踪只在宠物模式开启（其他模式零开销）。
    await _syncTracking();
    if (i == 2 && !_autoDetectedThisSession) {
      unawaited(
        Future<void>.delayed(_autoDetectDelay).then((_) {
          if (mounted) _autoDetectPet();
        }),
      );
    }
  }

  void _showCameraSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            void refreshSheet(void Function() action) {
              setState(action);
              sheetSetState(() {});
            }

            Future<void> refreshSheetAsync(
              Future<void> Function() action,
            ) async {
              await action();
              if (!mounted) return;
              sheetSetState(() {});
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  // 弹窗高度设上限 + 内部滚动。加入宠物参数区后内容变多，
                  // 不能再靠「内容自适应高度」，否则会撑出屏幕。
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.78,
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E4E6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '相机设置',
                        style: TextStyle(
                          fontSize: 20,
                          height: 28 / 20,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF000000),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _CameraSettingSection(
                        title: '拍摄参数',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final itemWidth =
                                    (constraints.maxWidth - 8) / 2;
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: List.generate(
                                    _photoRatioLabels.length,
                                    (index) => _CameraChoiceChip(
                                      label: _photoRatioLabels[index],
                                      width: itemWidth,
                                      selected: index == _photoRatioIndex,
                                      onTap: () => refreshSheet(
                                        () => _photoRatioIndex = index,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            // 切片G：连拍张数。宠物表情只有一帧，多拍几张再自动挑。
                            const _CameraFieldLabel('连拍张数'),
                            _CameraChipRow(
                              labels: [
                                for (final b in BurstCount.values)
                                  // 3 连拍性价比最高：降噪已到 42%，耗时只有
                                  // 5 连拍的六成。5/10 档留给愿意等的人。
                                  b == BurstCount.three
                                      ? '${b.label}（推荐）'
                                      : b.label,
                              ],
                              selectedIndex: _burstShots.index,
                              onSelect: (i) => refreshSheet(
                                () => _burstShots = BurstCount.values[i],
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '单张最快；每多一张就多开一次快门，且张数越多越慢。'
                              '推荐 3 连拍：降噪已到约 42%，耗时约为 5 连拍的六成。'
                              '宠物在动时运动区域会自动退回参考帧，此时收益主要来自'
                              '「自动挑出最清晰的一张」，而非降噪。',
                              style: TextStyle(
                                fontSize: 12,
                                height: 18 / 12,
                                color: Color(0xFF999999),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const _CameraFieldLabel('画质'),
                            _CameraChipRow(
                              labels: [
                                for (final q in CaptureQuality.values) q.label,
                              ],
                              selectedIndex: _quality.index,
                              onSelect: (i) => refreshSheetAsync(
                                () => _changeQuality(CaptureQuality.values[i]),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '当前取景 $_activePresetLabel$_downgradeHint',
                              style: const TextStyle(
                                fontSize: 12,
                                height: 18 / 12,
                                color: Color(0xFF999999),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _CameraSwitchTile(
                              title: '闪光灯',
                              value: _flashOn ? '开启' : '关闭',
                              onTap: () => refreshSheetAsync(_toggleFlash),
                            ),
                            const SizedBox(height: 14),
                            const _CameraFieldLabel('曝光补偿微调'),
                            _ExposureSlider(
                              baseEv: _profile.exposureCompensation,
                              offset: _userEvOffset,
                              onChanged: (v) => refreshSheetAsync(() async {
                                _userEvOffset = v;
                                await _applyFocusAndExposure(_focusNormalized);
                              }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 切片B：宠物参数（物种 × 毛色 × 场景）→ 自动改相机参数
                      _CameraSettingSection(
                        title: '宠物参数',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 自动识别是"减少用户选择"的主入口：
                            // 先替用户猜一次，用户只需要确认或微调。
                            _AutoDetectButton(
                              busy: _autoDetecting,
                              setup: _lastAutoSetup,
                              onTap: () => refreshSheetAsync(_autoDetectPet),
                            ),
                            const SizedBox(height: 16),
                            const _CameraFieldLabel('拍谁'),
                            _CameraChipRow(
                              labels: [
                                for (final s in PetSpecies.values)
                                  '${s.emoji} ${s.label}',
                              ],
                              selectedIndex: _species.index,
                              onSelect: (i) => refreshSheetAsync(
                                () => _updatePetProfile(
                                  species: PetSpecies.values[i],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const _CameraFieldLabel('什么毛色'),
                            _CameraChipRow(
                              labels: [
                                for (final c in PetCoat.values) c.label,
                              ],
                              selectedIndex: _coat.index,
                              onSelect: (i) => refreshSheetAsync(
                                () => _updatePetProfile(coat: PetCoat.values[i]),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const _CameraFieldLabel('什么场景'),
                            _CameraChipRow(
                              labels: [
                                for (final s in PetScene.values) s.label,
                              ],
                              selectedIndex: _scene.index,
                              onSelect: (i) => refreshSheetAsync(
                                () => _updatePetProfile(
                                  scene: PetScene.values[i],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // 滤镜模板：参数取自公开社区配方，但做了宠物专用改造
                            // （不跟冷调、保留高光滚降），说明见 PetLook 的文档。
                            const _CameraFieldLabel('滤镜模板'),
                            _CameraChipRow(
                              labels: [
                                for (final l in PetLook.values) l.label,
                              ],
                              selectedIndex: _look.index,
                              onSelect: (i) => refreshSheetAsync(
                                () => _updatePetProfile(
                                  look: PetLook.values[i],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _look.hint,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 18 / 12,
                                color: Color(0xFF999999),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _PetProfileSummary(
                              profile: _profile,
                              exposureOffline: !_capability.exposureSupported,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _CameraSettingSection(
                        title: '辅助功能',
                        child: Column(
                          children: [
                            // 切片D：出片时套用宠物滤镜（调色 + 美颜）。
                            _CameraSwitchTile(
                              title: '宠物滤镜',
                              value: _filterEnabled ? '开启' : '关闭',
                              onTap: () => refreshSheet(
                                () => _filterEnabled = !_filterEnabled,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _CameraSwitchTile(
                              title: '参考线',
                              value: _showGridGuide ? '显示' : '隐藏',
                              onTap: () => refreshSheet(
                                () => _showGridGuide = !_showGridGuide,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _CameraSwitchTile(
                              title: '宠物取景框',
                              value: _showPetGuide ? '显示' : '隐藏',
                              onTap: () => refreshSheet(
                                () => _showPetGuide = !_showPetGuide,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    // 动态短片还在录时通知它立刻收尾：否则录制循环会一直跑到 2 秒 deadline
    // 才去 stopVideoRecording，而那时控制器已经释放——异常虽被吞掉不会崩，
    // 但白白多占用两秒、并可能残留一个临时文件。
    _liveAbort = true;
    // 先停图像流再释放控制器：某些机型上直接 dispose 会让帧回调留在原地跑，
    // 而回调里还会去碰已释放的会话。
    final c = _controller;
    if (_streaming && c != null) {
      _streaming = false;
      unawaited(c.stopImageStream().catchError((_) {}));
    }
    _lurePlayer.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPreview()),
          if (_isInitialized) Positioned.fill(child: _buildCameraGuides()),
          // 切片C：点按对焦的对焦框，1.2 秒后由 _handleTapToFocus 清掉。
          if (_focusTapLocal != null)
            Positioned(
              left: _focusTapLocal!.dx - 34,
              top: _focusTapLocal!.dy - 34,
              child: const IgnorePointer(child: _FocusReticle()),
            ),
          if (_captured) Positioned.fill(child: Container(color: Colors.white)),
          // 快门按下即提示：连拍与多帧融合期间原本没有任何反馈，
          // 用户会以为"点了没反应"（见 _shootingHint 的说明）。
          // 滤镜阶段另有自己的提示，二者同时出现时只显示更靠后的那一个。
          if (_shootingHint != null && !_filtering)
            Positioned(
              left: 0,
              right: 0,
              bottom: 148,
              child: Center(child: _CameraToast(_shootingHint!)),
            ),
          // 切片D：滤镜是纯 Dart 逐像素处理，大图要花点时间，给个明确反馈。
          if (_filtering)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 148,
              child: Center(child: _CameraToast('宠物滤镜处理中…')),
            ),
          // 自动识别中（切到宠物模式时会自动跑一次）。
          if (_autoDetecting)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 196,
              child: Center(child: _CameraToast('正在识别宠物…')),
            ),
          if (_recording)
            Positioned(
              top: 72,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF3B30),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _audioUnsupported ? '录制中（无声）' : '录制中',
                        style: TextStyle(
                          fontSize: AppUi.fontBody,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AppBackButton(
                    onTap: () => Navigator.pop(context),
                    color: Colors.white,
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _toggleFlash,
                    child: MingCuteIcon(
                      _flashOn
                          ? MingCuteIcons.flashFill
                          : MingCuteIcons.flashLine,
                      color: _flashOn ? t.brand : Colors.white,
                      size: AppUi.iconLarge,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // 动态照片开关（对齐 iOS 相机顶部的实况照片同心圆按钮：
                  // 亮起=开、空心=关）。宠物模式下置灰，原因见 _toggleLivePhoto。
                  _LiveToggleButton(
                    supported: _modeIndex != 2,
                    enabled:
                        _modeIndex != 2 &&
                        ref.watch(livePhotoEnabledProvider),
                    onTap: _toggleLivePhoto,
                  ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    // 参考线直接放到外层，点击即可开关。
                    onTap: () =>
                        setState(() => _showGridGuide = !_showGridGuide),
                    child: MingCuteIcon(
                      MingCuteIcons.layoutGrid,
                      size: AppUi.iconLarge,
                      color: _showGridGuide ? t.brand : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 20),
                  GestureDetector(
                    onTap: _cyclePhotoRatio,
                    child: const MingCuteIcon(
                      MingCuteIcons.squareLine,
                      color: Colors.white,
                      size: AppUi.iconLarge,
                    ),
                  ),
                  const SizedBox(width: 20),
                  GestureDetector(
                    // 相机页设置应打开相机功能设置，而不是跳到全局设置页。
                    onTap: _showCameraSettingsSheet,
                    child: const MingCuteIcon(
                      MingCuteIcons.settings2Line,
                      color: Colors.white,
                      size: AppUi.iconLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 切片E：宠物模式下的引诱音效条。
                    // 宠物不看镜头是废片头号原因，声音是把它拉回来的最便宜手段。
                    if (_modeIndex == 2) ...[
                      _LureSoundBar(
                        sounds: _profile.lureSounds,
                        playing: _lurePlayer.current,
                        onTap: _toggleLureSound,
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: 188,
                      height: 34,
                      child: DecoratedBox(
                        // 相机模式切换严格按用户给的 CSS：188x34、2px 内边距、黑色 20% 背景。
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Row(
                            children: List.generate(_modes.length, (i) {
                              final active = i == _modeIndex;
                              return Padding(
                                padding: EdgeInsets.only(
                                  right: i == _modes.length - 1 ? 0 : 2,
                                ),
                                child: GestureDetector(
                                  onTap: _recording
                                      ? null
                                      : () => _switchMode(i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 60,
                                    height: 30,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: active
                                          ? const Color(0xFFFFEE35)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Text(
                                      _modes[i],
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 22 / 14,
                                        fontWeight: FontWeight.w400,
                                        color: active
                                            ? const Color(0xFF000000)
                                            : const Color(0xFFFFFFFF),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/album'),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: _lastBytes != null
                                ? ClipOval(
                                    // 有最近照片时直接显示缩略图，不再显示相册图标。
                                    child: Image.memory(
                                      _lastBytes!,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Center(
                                    child: MingCuteIcon(
                                      MingCuteIcons.pic2Line,
                                      size: 24,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        GestureDetector(
                          onTapDown: (_) => _capture(),
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _recording
                                    ? const Color(0xFFFF3B30)
                                    : Colors.white,
                                width: 4,
                              ),
                            ),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: _recording ? 28 : 60,
                                height: _recording ? 28 : 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    _recording ? 8 : 30,
                                  ),
                                  color: _recording
                                      ? const Color(0xFFFF3B30)
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _switchLens,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: MingCuteIcon(
                                MingCuteIcons.refresh2Line,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final t = context.tokens;
    if (_error != null) {
      return Container(
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MingCuteIcon(
                  MingCuteIcons.camera,
                  size: AppUi.iconLarge,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 8),
                Text(
                  '演示环境无摄像头时，可前往「相册」查看金元宝种子照片',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppUi.fontCaption,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/album'),
                  style: FilledButton.styleFrom(
                    backgroundColor: t.brand,
                    foregroundColor: t.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('前往相册'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_isInitialized || _controller == null) {
      return Container(
        color: const Color(0xFF1A1A1A),
        child: Center(child: CircularProgressIndicator(color: t.brand)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = _controller!.value.previewSize;
        if (previewSize == null) {
          return CameraPreview(_controller!);
        }
        final isViewportPortrait =
            constraints.maxHeight >= constraints.maxWidth;
        final isPreviewPortrait = previewSize.height >= previewSize.width;
        // 只有当相机原始方向和屏幕方向不一致时才交换宽高，避免某些设备上把本来竖向的画面误当成横向处理。
        final displayWidth = isViewportPortrait == isPreviewPortrait
            ? previewSize.width
            : previewSize.height;
        final displayHeight = isViewportPortrait == isPreviewPortrait
            ? previewSize.height
            : previewSize.width;
        // cover 铺满视口：**先算好最终绘制尺寸，再用 OverflowBox 解除约束**。
        //
        // 这里的坑在于约束传递：`Center > SizedBox(displayW x displayH) >
        // CameraPreview` 这条链里，SizedBox 会被父级（视口尺寸的 tight 约束）
        // 直接压扁，CameraPreview 内部的 AspectRatio 再退一步收缩——于是
        // Transform.scale 实际作用在"已经缩到视口内"的尺寸上。缩放系数小于 1
        // 时，画面就不进反退，缩成屏幕中间一小块（实拍反馈过）。
        //
        // 所以既不用 Transform.scale，也不依赖 SizedBox 的原始尺寸：
        // 直接算出 drawW x drawH 让 SizedBox 一步到位，OverflowBox 放开父约束
        // 允许它超出视口，最后交给 ClipRect 裁掉溢出——这正是 cover 的定义。
        final scale = math.max(
          constraints.maxWidth / displayWidth,
          constraints.maxHeight / displayHeight,
        );
        final drawWidth = displayWidth * scale;
        final drawHeight = displayHeight * scale;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 切片C：点按 = 对焦 + 测光；双指 = 缩放。
          // 网页端这些能力不可用，CameraCapability 会静默跳过，不会崩。
          onTapDown: (d) => _handleTapToFocus(
            d.localPosition,
            Size(constraints.maxWidth, constraints.maxHeight),
            Size(drawWidth, drawHeight),
          ),
          onScaleStart: (_) => _zoomAtGestureStart = _zoom,
          onScaleUpdate: _handleZoomUpdate,
          child: ClipRect(
            child: OverflowBox(
              // 放开约束：cover 的本质就是"放大到铺满 + 裁掉溢出部分"，
              // 不允许溢出就永远铺不满。
              maxWidth: drawWidth,
              maxHeight: drawHeight,
              child: SizedBox(
                width: drawWidth,
                height: drawHeight,
                child: CameraPreview(_controller!),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 统一在取景层叠加照片比例框、参考线和宠物取景框。
  Widget _buildCameraGuides() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final frame = _resolveGuideFrame(viewport);
        final hasRatioMask = _photoRatioValues[_photoRatioIndex] != null;
        final t = context.tokens;
        return IgnorePointer(
          child: Stack(
            children: [
              if (hasRatioMask)
                Positioned.fill(
                  // 非原图比例时，用纯黑蒙版遮住比例外区域，中间比例区保持完全透明。
                  child: CustomPaint(
                    painter: _CameraRatioMaskPainter(frameRect: frame),
                  ),
                ),
              if (_showGridGuide)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CameraGridPainter(frameRect: frame),
                  ),
                ),
              // 跟踪到宠物 → 画跟随框（带识别标签）；没跟踪到 → 回落到静态引导框。
              if (_modeIndex == 2)
                for (final d in _detections.take(1))
                  Positioned.fromRect(
                    rect: _detectionRect(d, viewport),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: t.brand, width: 2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: -22,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: t.brand,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${d.label} ${(d.confidence * 100).round()}%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2B2622),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              if (_modeIndex == 2 && _showPetGuide && _detections.isEmpty)
                Positioned.fromRect(
                  rect: frame,
                  child: Center(
                    child: Container(
                      width: 220,
                      height: 280,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MingCuteIcon(
                            MingCuteIcons.paw,
                            size: AppUi.iconLarge,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '宠物取景框',
                            style: TextStyle(
                              fontSize: AppUi.fontBody,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 计算比例框在当前取景区域里的最大可用区域，避免压住上下操作区。
  Rect _resolveGuideFrame(Size viewport) {
    final targetRatio = _photoRatioValues[_photoRatioIndex];
    final padding = MediaQuery.paddingOf(context);
    final availableWidth = viewport.width;
    final availableHeight = math.max(
      0.0,
      viewport.height - padding.top - padding.bottom,
    );
    if (targetRatio == null) {
      return Rect.fromLTWH(0, padding.top, availableWidth, availableHeight);
    }

    final heightByWidth = availableWidth / targetRatio;
    final useWidth = heightByWidth <= availableHeight;
    final frameWidth = useWidth
        ? availableWidth
        : availableHeight * targetRatio;
    final frameHeight = useWidth ? heightByWidth : availableHeight;
    return Rect.fromLTWH(
      (viewport.width - frameWidth) / 2,
      padding.top + ((availableHeight - frameHeight) / 2),
      frameWidth,
      frameHeight,
    );
  }
}

/// 动态照片开关按钮（对齐 iOS 相机顶部的实况照片同心圆）。
///
/// 自绘而非用图标：MingCute 里没有同心圆，自绘能精确还原"外圈 + 内实心点"
/// 这个用户已经被苹果教育过的视觉。关闭时内圈收缩为零（空心圆）。
class _LiveToggleButton extends StatelessWidget {
  const _LiveToggleButton({
    required this.supported,
    required this.enabled,
    required this.onTap,
  });

  /// 当前模式是否支持动态照片。不支持时置灰但仍可点击（点了给原因）。
  final bool supported;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = !supported
        ? Colors.white.withValues(alpha: 0.35)
        : (enabled ? t.brand : Colors.white);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: AppUi.iconLarge,
        height: AppUi.iconLarge,
        child: Center(
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.6),
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: enabled ? 10 : 0,
                height: enabled ? 10 : 0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraSettingSection extends StatelessWidget {
  const _CameraSettingSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            height: 22 / 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF000000),
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _CameraChoiceChip extends StatelessWidget {
  const _CameraChoiceChip({
    required this.label,
    this.width,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double? width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? t.brand : const Color(0xFFE2E4E6),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            height: 22 / 14,
            fontWeight: FontWeight.w400,
            color: selected ? const Color(0xFF000000) : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }
}

/// 设置项里的小标题（如「拍谁」「什么毛色」）。
class _CameraFieldLabel extends StatelessWidget {
  const _CameraFieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          height: 20 / 13,
          fontWeight: FontWeight.w400,
          color: Color(0xFF999999),
        ),
      ),
    );
  }
}

/// 横向滚动的胶囊选择行。
///
/// 用横向滚动而不是两列网格：宠物参数有三组选择（物种/毛色/场景），
/// 网格会占掉太多竖向空间，把弹窗撑高。
class _CameraChipRow extends StatelessWidget {
  const _CameraChipRow({
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _CameraChoiceChip(
          label: labels[i],
          selected: i == selectedIndex,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

/// 当前宠物参数摘要：把 [_PetCaptureProfile] 解析出的数值摊开给用户看。
///
/// 这是"宠物相机"和"普通相机"最直观的差别——用户能看见相机为自己家的
/// 毛孩子改了什么。
class _PetProfileSummary extends StatelessWidget {
  const _PetProfileSummary({
    required this.profile,
    required this.exposureOffline,
  });

  final PetCaptureProfile profile;

  /// 当前平台不支持硬件曝光控制（网页端），需要如实告知。
  final bool exposureOffline;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('快门', profile.shutterLabel),
      ('曝光补偿', profile.evLabel),
      ('ISO', '${profile.isoMin}–${profile.isoMax}'),
      ('白平衡', '${profile.whiteBalanceK}K'),
      ('对焦', profile.focusTarget.label),
      ('快门声', profile.silentShutter ? '电子静音' : '常规'),
      ('闪光灯', profile.flashPolicy.label),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${profile.species.emoji} ${profile.species.label}参数已生效',
                style: const TextStyle(
                  fontSize: 14,
                  height: 22 / 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF000000),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (k, v) in rows)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$k $v',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 18 / 12,
                      color: Color(0xFF555555),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            profile.summary,
            style: const TextStyle(
              fontSize: 12,
              height: 18 / 12,
              color: Color(0xFF888888),
            ),
          ),
          if (exposureOffline) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6EC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '当前在网页端：曝光/对焦控制不可用（浏览器限制）。'
                '这些参数会在 iOS / Android 原生版自动生效，'
                '网页端仍可使用滤镜与美颜。',
                style: TextStyle(
                  fontSize: 12,
                  height: 18 / 12,
                  color: Color(0xFFB26A2B),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 宠物模式下的引诱音效条（切片E）。
///
/// 横向排列当前物种适用的音效，点击播放、再点停止。
/// 文案与音效都由 [PetCaptureProfile.lureSounds] 按物种给出，不会串种
/// （不会把狗的哨声推给猫）。
class _LureSoundBar extends StatelessWidget {
  const _LureSoundBar({
    required this.sounds,
    required this.playing,
    required this.onTap,
  });

  final List<LureSound> sounds;
  final LureSound? playing;
  final ValueChanged<LureSound> onTap;

  @override
  Widget build(BuildContext context) {
    if (sounds.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sounds.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final sound = sounds[i];
          final active = sound == playing;
          return GestureDetector(
            onTap: () => onTap(sound),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFFFFEE35)
                    : Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(19),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MingCuteIcon(
                    active ? MingCuteIcons.pause : MingCuteIcons.music,
                    size: 15,
                    color: active ? const Color(0xFF000000) : Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    sound.label,
                    style: TextStyle(
                      fontSize: 13,
                      height: 20 / 13,
                      fontWeight: FontWeight.w400,
                      color: active ? const Color(0xFF000000) : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 取景框上的轻量提示条（滤镜处理中 / 自动识别中等）。
class _CameraToast extends StatelessWidget {
  const _CameraToast(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          height: 20 / 13,
        ),
      ),
    );
  }
}

/// 点按对焦的对焦框（切片C）。
///
/// 画成四角括号而不是整框：中间留空才不会挡住宠物眼睛——
/// 用户点哪儿，哪儿就是他想看清的地方。
class _FocusReticle extends StatelessWidget {
  const _FocusReticle();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 68,
      height: 68,
      child: CustomPaint(painter: _FocusReticlePainter()),
    );
  }
}

class _FocusReticlePainter extends CustomPainter {
  const _FocusReticlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFEE35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    const arm = 15.0;
    final w = size.width;
    final h = size.height;
    void seg(Offset a, Offset b) => canvas.drawLine(a, b, paint);

    // 左上
    seg(const Offset(0, arm), Offset.zero);
    seg(Offset.zero, const Offset(arm, 0));
    // 右上
    seg(Offset(w - arm, 0), Offset(w, 0));
    seg(Offset(w, 0), Offset(w, arm));
    // 右下
    seg(Offset(w, h - arm), Offset(w, h));
    seg(Offset(w, h), Offset(w - arm, h));
    // 左下
    seg(Offset(arm, h), Offset(0, h));
    seg(Offset(0, h), Offset(0, h - arm));
  }

  @override
  bool shouldRepaint(covariant _FocusReticlePainter oldDelegate) => false;
}

/// 曝光补偿微调滑杆（切片C）。
///
/// 基准值由物种/毛色自动算出（白毛加、黑毛减），这里允许用户在基准之上
/// 再手动加减——自动给对了还要能被推翻，"可控"才是相机该有的样子。
class _ExposureSlider extends StatelessWidget {
  const _ExposureSlider({
    required this.baseEv,
    required this.offset,
    required this.onChanged,
  });

  /// 参数引擎给出的基准曝光补偿。
  final double baseEv;

  /// 用户手动微调量。
  final double offset;

  final ValueChanged<double> onChanged;

  static String _fmt(double v) =>
      '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final total = baseEv + offset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Slider(
                value: offset.clamp(-2.0, 2.0),
                min: -2,
                max: 2,
                divisions: 40,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 74,
              child: Text(
                '${_fmt(total)} EV',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  height: 20 / 13,
                  color: Color(0xFF666666),
                ),
              ),
            ),
          ],
        ),
        Text(
          '基准 ${_fmt(baseEv)}EV（按毛色自动）　微调 ${_fmt(offset)}EV',
          style: const TextStyle(
            fontSize: 12,
            height: 18 / 12,
            color: Color(0xFF999999),
          ),
        ),
      ],
    );
  }
}

/// 「自动识别」按钮 + 上次识别结果。
///
/// 这是"减少用户选择"的主入口：先替用户猜一次，用户只需确认或微调，
/// 而不是从 4×5×5 个组合里自己挑。
class _AutoDetectButton extends StatelessWidget {
  const _AutoDetectButton({
    required this.busy,
    required this.setup,
    required this.onTap,
  });

  final bool busy;
  final PetAutoSetup? setup;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = setup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: busy ? null : onTap,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: busy ? const Color(0xFFEFEFEF) : const Color(0xFFFFEE35),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              busy ? '识别中…' : '自动识别我的宠物',
              style: const TextStyle(
                fontSize: 14,
                height: 22 / 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF000000),
              ),
            ),
          ),
        ),
        if (s != null) ...[
          const SizedBox(height: 8),
          Text(
            s.summary,
            style: const TextStyle(
              fontSize: 12,
              height: 18 / 12,
              color: Color(0xFF888888),
            ),
          ),
          if (s.needsConfirmation) ...[
            const SizedBox(height: 6),
            const Text(
              '把握不大，建议确认一下下面的选项',
              style: TextStyle(
                fontSize: 12,
                height: 18 / 12,
                color: Color(0xFFB26A2B),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _CameraSwitchTile extends StatelessWidget {
  const _CameraSwitchTile({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  height: 22 / 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF000000),
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                height: 22 / 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF999999),
              ),
            ),
            const SizedBox(width: 8),
            const MingCuteIcon(
              MingCuteIcons.rightLine,
              size: 20,
              color: Color(0xFF999999),
            ),
          ],
        ),
      ),
    );
  }
}

/// 参考线只画在可用取景区里，避免压到顶部导航和底部按钮。
class _CameraGridPainter extends CustomPainter {
  const _CameraGridPainter({required this.frameRect});

  final Rect frameRect;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1;

    final thirdWidth = frameRect.width / 3;
    final thirdHeight = frameRect.height / 3;

    for (var i = 1; i <= 2; i++) {
      final dx = frameRect.left + (thirdWidth * i);
      canvas.drawLine(
        Offset(dx, frameRect.top),
        Offset(dx, frameRect.bottom),
        paint,
      );
      final dy = frameRect.top + (thirdHeight * i);
      canvas.drawLine(
        Offset(frameRect.left, dy),
        Offset(frameRect.right, dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CameraGridPainter oldDelegate) {
    return oldDelegate.frameRect != frameRect;
  }
}

/// 比例外区域用纯黑遮罩，取景时就能看到最终成片范围。
class _CameraRatioMaskPainter extends CustomPainter {
  const _CameraRatioMaskPainter({required this.frameRect});

  final Rect frameRect;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(frameRect);
    canvas.drawPath(path, Paint()..color = const Color(0xFF000000));
  }

  @override
  bool shouldRepaint(covariant _CameraRatioMaskPainter oldDelegate) {
    return oldDelegate.frameRect != frameRect;
  }
}
