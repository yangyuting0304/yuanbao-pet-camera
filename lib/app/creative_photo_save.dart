import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_camera/data/captured_photos.dart';
import 'package:pet_camera/data/library_service.dart';
import 'package:pet_camera/data/photo_saver.dart';

/// Save locally first. Cloud or gallery failures never turn into fake success.
Future<String> saveCreativePhoto(
  WidgetRef ref,
  Uint8List bytes, {
  required LibraryType type,
  required String label,
}) async {
  await ref.read(capturedPhotosProvider.notifier).addDurable(bytes);
  final ext = bytes.length > 4 && bytes[0] == 137 && bytes[1] == 80
      ? 'png'
      : 'jpg';
  final galleryError = await savePhotoToGallery(
    bytes,
    fileName: 'yuanbao_${DateTime.now().millisecondsSinceEpoch}.$ext',
  );
  var synced = false;
  try {
    await ref
        .read(worksProvider.notifier)
        .add(
          bytes: bytes,
          type: type,
          ext: ext,
          contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
          label: label,
        )
        .timeout(const Duration(seconds: 12));
    synced = true;
  } catch (_) {
    /* Original remains in durable local storage. */
  }
  return '已保存到本地相册${galleryError == null ? '，已导出' : '；$galleryError'}${synced ? '，已同步云端' : '；云端未同步'}';
}
