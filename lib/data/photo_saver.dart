/// 照片导出：把成片交给用户。
///
///   - Android / iOS：写入**系统相册**（用户能在系统相册里看到、分享、发微信）
///   - Web：触发浏览器下载
///
/// 分流方式与项目其余平台层一致（条件导入）。
library;

import 'dart:typed_data';

import 'photo_saver_stub.dart'
    if (dart.library.io) 'photo_saver_io.dart' as impl;

/// 是否支持写入系统相册（Web 为浏览器下载，false）。
bool get gallerySaveSupported => impl.gallerySaveSupported;

/// 保存照片。成功返回 null，失败返回**给用户看的**提示文案。
Future<String?> savePhotoToGallery(Uint8List bytes, {String? fileName}) =>
    impl.savePhotoToGallery(bytes, fileName: fileName);
