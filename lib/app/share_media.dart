import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Share real bytes. iPad needs an explicit popover origin.
Future<void> shareMedia(
  BuildContext context,
  Uint8List bytes, {
  required String filename,
  required String mime,
}) async {
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : const Rect.fromLTWH(0, 0, 1, 1);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mime)],
      fileNameOverrides: [filename],
      sharePositionOrigin: origin,
      downloadFallbackEnabled: true,
    ),
  );
}
