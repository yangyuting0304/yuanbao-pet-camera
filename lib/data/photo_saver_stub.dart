// Web / 兜底：浏览器没有系统相册，改为触发下载。
// 直接复用既有的 MediaPlatform.downloadBytes（它已处理 Web/原生的差异）。
import 'dart:typed_data';

import '../app/media_platform.dart';

const bool gallerySaveSupported = false;

Future<String?> savePhotoToGallery(Uint8List bytes, {String? fileName}) async {
  try {
    await MediaPlatform.downloadBytes(
      bytes,
      fileName ?? 'yuanbao_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    return null;
  } catch (e) {
    return '下载失败：$e';
  }
}
