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

/// 浏览器下载：blob URL + <a download> 触发保存。
Future<void> downloadBytes(Uint8List bytes, String filename) async {
  final blob = html.Blob(<Object>[bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..download = filename;
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
