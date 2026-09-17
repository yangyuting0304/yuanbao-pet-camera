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
  });

  /// 磁盘文件名（`cap_<毫秒时间戳>.jpg`），唯一标识一张落盘照片。
  final String fileName;

  final Uint8List bytes;
  final DateTime takenAt;
}

abstract final class PhotoStorage {
  /// 落盘一张照片，返回文件名。
  ///
  /// 失败返回 null 而**不抛异常**：持久化只是兜底，绝不能阻断拍照主流程。
  static Future<String?> save(Uint8List bytes) => impl.save(bytes);

  /// 读取全部历史照片，最新在前。
  static Future<List<SavedPhoto>> loadAll() => impl.loadAll();

  /// 清空全部落盘照片（对应设置页「清除相册缓存」，不可恢复）。
  static Future<void> clearAll() => impl.clearAll();
}
