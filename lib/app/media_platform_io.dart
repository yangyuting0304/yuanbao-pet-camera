/// Android / iOS 实现：字节 → 临时文件（dart:io），file / DeviceFileSource 播放。
///
/// file_picker 在原生端同样返回字节（withData: true），但 video_player /
/// audioplayers 需要的是文件路径，因此必须先落盘到系统临时目录。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';

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

/// 原生端下载：写入系统临时目录（Web 走浏览器下载；原生保存对话框后续可接
/// file_picker.saveFile 提升体验）。
Future<void> downloadBytes(Uint8List bytes, String filename) async {
  final dir = await Directory.systemTemp.createTemp('yuanbao_dl_');
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
}

/// 原生端：video_player 由系统播放器承载，无 DOM 可操作。
/// 有声自动播放在原生端不受浏览器策略限制，此函数为空实现。
Future<void> setVideosMuted(bool muted) async {}
