// 原生端：写系统相册（Android MediaStore / iOS PhotoKit，由 gal 包封装）。
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

const bool gallerySaveSupported = true;

Future<String?> savePhotoToGallery(Uint8List bytes, {String? fileName}) async {
  try {
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) return '没有相册权限，请在系统设置里允许后重试';
    }
    await Gal.putImageBytes(
      bytes,
      name: fileName ?? 'yuanbao_${DateTime.now().millisecondsSinceEpoch}',
    );
    return null;
  } catch (e) {
    debugPrint('[保存照片] 失败：$e');
    return '保存失败：$e';
  }
}
