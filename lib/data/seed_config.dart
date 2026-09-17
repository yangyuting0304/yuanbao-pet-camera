/// 种子图远程地址配置。
///
/// 背景：assets/seed/photos/ 共 212 个图片文件 / 57.2 MB，全量打进安装包会让
/// APK 虚胖、Web 部署包臃肿。现改为外置到对象存储，直接按
///「COS 对象 URL + 文件名」拼出远程地址，seed_manifest.json 无需改。
///
/// 云端结构（2026-09-01 上传实测）：
///   云对象  https://pet-camera-1322296918.cos.ap-guangzhou.myqcloud.com/
///           seed/photos/「fileName」
///   文件名在 photos/ 下平铺（feat_album.jpg、xiaomianhua_001.jpg … 共 212 个），
///   与本地 assets/seed/photos/ 的文件名一一对应。
///   全部对象公开读（HTTP 200），App 可直接加载。
library;

/// 种子图在对象存储中的根地址。
///
/// 该值直接指向图片文件所在目录的上一级（含 /photos/），`photoUrl` 负责拼接文件名。
/// 构建期可用 `--dart-define=SEED_BASE_URL=...` 覆盖。
class SeedConfig {
  const SeedConfig._();

  /// 种子图根地址，编译期注入。
  static const String baseUrl = String.fromEnvironment(
    'SEED_BASE_URL',
    defaultValue: 'https://pet-camera-1322296918.cos.ap-guangzhou.myqcloud.com/seed',
  );

  /// 拼出某张种子图的完整远程地址。
  static String photoUrl(String fileName) => '$baseUrl/photos/$fileName';
}
