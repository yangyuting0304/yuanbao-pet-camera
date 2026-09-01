/// 兜底实现（非 Web / 非移动端平台，实际不会走到）。
library;

import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';

Future<String> createMediaUrl(Uint8List bytes, String mime) =>
    throw UnsupportedError('当前平台不支持短片媒体播放');

Future<void> releaseMediaUrl(String url) async {}

VideoPlayerController videoController(String url) =>
    throw UnsupportedError('当前平台不支持短片媒体播放');

Source audioSource(String url) =>
    throw UnsupportedError('当前平台不支持短片媒体播放');
