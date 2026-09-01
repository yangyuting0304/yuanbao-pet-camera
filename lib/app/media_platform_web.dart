/// Web 端实现：字节 → blob URL（dart:html），networkUrl / UrlSource 播放。
library;

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';

Future<String> createMediaUrl(Uint8List bytes, String mime) async =>
    html.Url.createObjectUrlFromBlob(html.Blob(<Object>[bytes], mime));

Future<void> releaseMediaUrl(String url) async {
  if (url.startsWith('blob:')) html.Url.revokeObjectUrl(url);
}

VideoPlayerController videoController(String url) =>
    VideoPlayerController.networkUrl(Uri.parse(url));

Source audioSource(String url) => UrlSource(url);
