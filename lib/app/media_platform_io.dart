/// Android / iOS 实现：字节 → 临时文件（dart:io），file / DeviceFileSource 播放。
///
/// file_picker 在原生端同样返回字节（withData: true），但 video_player /
/// audioplayers 需要的是文件路径，因此必须先落盘到系统临时目录。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:gal/gal.dart';
import 'package:file_picker/file_picker.dart';

int _seq = 0;

String _extFor(String mime) {
  if (mime.contains('webm')) return 'webm';
  if (mime.contains('ogg')) return 'ogg';
  if (mime.contains('mpeg') || mime.contains('mp3')) return 'mp3';
  if (mime.contains('wav')) return 'wav';
  return 'mp4';
}

Future<String> createMediaUrl(Uint8List bytes, String mime) async {
  final dir = await Directory.systemTemp.createTemp('yuanbao_media_');
  final file = File('${dir.path}/clip_${_seq++}.${_extFor(mime)}');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> releaseMediaUrl(String url) async {
  try {
    final f = File(url);
    if (await f.exists()) {
      await f.delete();
      final parent = f.parent;
      if (await parent.exists()) await parent.delete();
    }
  } catch (_) {
    /* 清理失败不影响播放 */
  }
}

VideoPlayerController videoController(String url) =>
    VideoPlayerController.file(File(url));

Source audioSource(String url) => DeviceFileSource(url);

/// 原生端图片/视频写入系统相册，文档使用保存对话框。
Future<void> downloadBytes(Uint8List bytes, String filename) async {
  if (Platform.isAndroid || Platform.isIOS) {
    if (filename.endsWith('.mp4') ||
        filename.endsWith('.webm') ||
        filename.endsWith('.mov')) {
      final dir = await Directory.systemTemp.createTemp('yuanbao_gallery_');
      final file = File('${dir.path}/$filename');
      try {
        await file.writeAsBytes(bytes, flush: true);
        await Gal.putVideo(file.path);
      } finally {
        await dir.delete(recursive: true);
      }
    } else if (RegExp(
      r'\.(jpg|jpeg|png)$',
      caseSensitive: false,
    ).hasMatch(filename)) {
      await Gal.putImageBytes(bytes, name: filename);
    } else {
      final path = await FilePicker.platform.saveFile(
        fileName: filename,
        bytes: bytes,
      );
      if (path == null) throw StateError('已取消保存');
    }
    return;
  }
  final destination = await FilePicker.platform.saveFile(fileName: filename);
  if (destination == null) throw StateError('已取消保存');
  final file = File(destination);
  await file.writeAsBytes(bytes, flush: true);
}

/// 原生端：video_player 由系统播放器承载，无 DOM 可操作。
/// 有声自动播放在原生端不受浏览器策略限制，此函数为空实现。
Future<void> setVideosMuted(bool muted) async {}
