/// 编译期环境配置集中管理（`--dart-define` / `--dart-define-from-file`）。
///
/// 背景（本次修复的起因）：
/// 这些值原先只在 Web 构建脚本里注入（`build_web.cmd` / `run_web.cmd` 均带
/// `--dart-define-from-file=frontend_env.json`）。iOS / Android 打 Release 包时，
/// 若直接用 Xcode「Product > Archive」，或命令行忘记传 `--dart-define`，
/// `String.fromEnvironment` 一律返回空串，于是：
///   - [LibraryService] 解析不出代理地址，抛 `LibraryException: 未配置代理`；
///   - 图像服务因缺少配置而不可用；当前会明确提示，不生成演示结果。
///
/// 因此这里统一为每个变量配上**生产环境默认值**（与 `SeedConfig.baseUrl` 的做法一致）：
///   - 传了 `--dart-define` / `--dart-define-from-file`  -> 用注入值（本地、局域网调试照旧）
///   - 没传                                              -> 用生产默认值，任何打包方式都能联网
library;

/// 生产代理根域名（AI 写真 / 相册库共用同一套后端）。
///
/// 覆盖方式（Mac 上打 iOS 包同理）：
/// ```bash
/// flutter build ios --release --dart-define-from-file=frontend_env.json
/// ```
const String _kProdProxyRoot = 'https://yangyuting.cloud';

/// 全局编译期环境配置。
class AppEnv {
  const AppEnv._();

  /// 写真代理完整地址（含 `/api/beautify` 路径）。
  static const String aiProxyUrl = String.fromEnvironment(
    'AI_PROXY_URL',
    defaultValue: '$_kProdProxyRoot/api/beautify',
  );

  /// 相册库 / 上传 共用的代理**根地址**（不含路径）。
  /// 保留旧 AI_VIDEO_PROXY_URL 环境变量兼容既有部署；视频生成已移除。
  ///
  /// 用法：`'${AppEnv.aiVideoProxyRoot}/api/seed'`、`.../api/works`、`.../api/upload`。
  static const String aiVideoProxyUrl = String.fromEnvironment(
    'AI_VIDEO_PROXY_URL',
    defaultValue: _kProdProxyRoot,
  );

  /// FireRed 图像编辑代理完整地址（含路径）。
  ///
  /// 该服务尚未部署，默认留空 —— 未配置时 [FireRedService] 自动走演示模式回显源图。
  static const String fireredProxyUrl = String.fromEnvironment(
    'FIERED_PROXY_URL',
    defaultValue: '',
  );

  /// 宠物物种识别代理完整地址（含 `/api/pet-species` 路径）。
  ///
  /// 识别用的 API Key **只存在服务端**，客户端不持有任何识别 Key——
  /// Web 产物里的字符串可以被直接解出来，Key 进客户端就等于公开。
  ///
  /// 服务端未配置识别供应商时会返回 `available: false`，
  /// [CloudSpeciesDetector] 据此静默降级为"没识别出来"，由用户手选。
  static const String petSpeciesProxyUrl = String.fromEnvironment(
    'PET_SPECIES_PROXY_URL',
    defaultValue: '$_kProdProxyRoot/api/pet-species',
  );

  /// 是否在 **iOS** 上启用端侧 TFLite（实时宠物检测 → 自动追焦）。
  ///
  /// 默认**关**，因为 tflite_flutter 的推理在 iOS 上会触发 native 崩溃
  /// （三条已试过且都无效的路线记在 pet_detector_io.isAvailable 的注释里）。
  /// 关掉时宠物模式退回点按对焦，换来「绝不闪退」这条底线。
  ///
  /// 打开它只为**真机验证**：iOS 侧的崩溃必须用实机跑才知道成没成，
  /// 而发到 App Store 的包绝不能带这个风险。因此做成编译期开关——
  /// 云构建验证包带上它，复现崩溃拿到日志后才谈正式启用：
  ///
  /// ```bash
  /// flutter build ipa --dart-define=IOS_TFLITE_ENABLED=true
  /// ```
  static const bool iosTfliteEnabled = bool.fromEnvironment(
    'IOS_TFLITE_ENABLED',
    defaultValue: false,
  );
}
