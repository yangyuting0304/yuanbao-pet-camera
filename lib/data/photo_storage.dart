/// 拍摄照片的本地持久化层（原生端真实落盘，Web 端空实现）。
///
/// 背景：此前拍摄照片只存内存（[capturedPhotosProvider] 内存态），
/// 上传 COS 失败或未配置代理时，App 重启后照片全部丢失。
/// 本层把每张成片写入应用文档目录（无需任何系统权限），启动时回填。
///
/// 平台分流（与 media_platform 同一套条件导入模式）：
///   - Android / iOS：dart:io + path_provider，真实文件。
///   - Web：无 dart:io，全部 no-op，行为同旧版（依赖云端 works.json 兜底）。
library;

import 'dart:typed_data';

import 'photo_storage_stub.dart'
    if (dart.library.io) 'photo_storage_io.dart'
    if (dart.library.html) 'photo_storage_web.dart' as impl;

/// 一张落盘的拍摄照片。
class SavedPhoto {
  const SavedPhoto({
    required this.fileName,
    required this.bytes,
    required this.takenAt,
    this.livePath,
  });

  /// 磁盘文件名（`cap_<毫秒时间戳>.jpg`），唯一标识一张落盘照片。
  final String fileName;

  final Uint8List bytes;
  final DateTime takenAt;

  /// 动态照片的短片文件**路径**（`live_<毫秒时间戳>.mp4`），无则为 null。
  ///
  /// 存路径而不是字节：一段 2 秒短片 2~4MB，若在启动回填时全部读进内存，
  /// 200 张就是 400MB+。播放时再按路径懒加载（video_player 可直接读文件）。
  final String? livePath;

  bool get hasLive => livePath != null;
}

abstract final class PhotoStorage {
  /// 落盘一张照片，返回文件名。
  ///
  /// [takenAt] 同时决定文件名——删除时按同一时间戳定位，无需额外索引。
  /// 失败返回 null 而**不抛异常**：持久化只是兜底，绝不能阻断拍照主流程。
  static Future<String?> save(Uint8List bytes, {DateTime? takenAt}) =>
      impl.save(bytes, takenAt: takenAt);

  /// 删除一张落盘照片（连同它的动态短片）。
  static Future<void> delete(DateTime takenAt) => impl.delete(takenAt);

  /// 落盘一段动态短片，返回文件**绝对路径**（播放时按路径懒加载）。
  ///
  /// 与照片用同一 [takenAt] 关联，无需额外索引。失败返回 null 且不抛异常
  /// ——动态照片是附加价值，绝不能影响拍照主流程。
  static Future<String?> saveLive(Uint8List bytes, {required DateTime takenAt}) =>
      impl.saveLive(bytes, takenAt: takenAt);

  /// 删除某张照片的动态短片（单独删，用于录制失败后的清理）。
  static Future<void> deleteLive(DateTime takenAt) => impl.deleteLive(takenAt);

  /// 读取全部历史照片，最新在前。
  static Future<List<SavedPhoto>> loadAll() => impl.loadAll();

  /// 清空全部落盘照片（对应设置页「清除相册缓存」，不可恢复）。
  static Future<void> clearAll() => impl.clearAll();

  /// 读取「已被用户删除的云端照片 URL」。
  ///
  /// 云端（COS + works.json）没有删除接口，所以这里做**本地屏蔽**：
  /// 记录 url，相册合并时过滤掉。用户在 App 内看不到、也就等于删掉了；
  /// 服务端条目仍在（日后接入删除 API 时可一次性清理）。
  static Future<Set<String>> loadHiddenUrls() => impl.loadHiddenUrls();

  /// 记录一个被删除的云端照片 URL。
  static Future<void> hideUrl(String url) => impl.hideUrl(url);
}
