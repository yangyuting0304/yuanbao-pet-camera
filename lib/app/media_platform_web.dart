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

/// 把页面上所有 <video> 元素设为静音/取消静音。
///
/// 背景：video_player 2.14 没有 muted API（setVolume(0) 不等于 muted 属性），
/// 而移动/局域网浏览器的自动播放策略只放行 muted 自动播放。这里直接操作 DOM
/// 绕过该限制：静音自动播画面，用户想听声音再点按钮取消静音（有手势必成功）。
Future<void> setVideosMuted(bool muted) async {
  final videos = html.document.getElementsByTagName('video');
  for (final node in videos) {
    if (node is html.VideoElement) {
      node.muted = muted;
      if (!muted) {
        try {
          await node.play();
        } catch (_) {}
      }
    }
  }
}
