/// 编译期环境配置集中管理（`--dart-define` / `--dart-define-from-file`）。
///
/// 背景（本次修复的起因）：
/// 这些值原先只在 Web 构建脚本里注入（`build_web.cmd` / `run_web.cmd` 均带
/// `--dart-define-from-file=frontend_env.json`）。iOS / Android 打 Release 包时，
/// 若直接用 Xcode「Product > Archive」，或命令行忘记传 `--dart-define`，
/// `String.fromEnvironment` 一律返回空串，于是：
///   - [LibraryService] 解析不出代理地址，抛 `LibraryException: 未配置代理`；
///   - 各 AI 服务静默降级为「演示模式」（回显原图 / 内置视频），看起来像功能坏了。
///
/// 因此这里统一为每个变量配上**生产环境默认值**（与 `SeedConfig.baseUrl` 的做法一致）：
///   - 传了 `--dart-define` / `--dart-define-from-file`  -> 用注入值（本地、局域网调试照旧）
///   - 没传                                              -> 用生产默认值，任何打包方式都能联网
library;

/// 生产代理根域名（AI 写真 / 图生视频 / 相册库共用同一套后端）。
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

  /// 图生视频 / 相册库 / 上传 共用的代理**根地址**（不含路径）。
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
}
