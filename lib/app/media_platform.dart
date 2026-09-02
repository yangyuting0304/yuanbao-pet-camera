/// 平台相关媒体工具：把字节流转成当前平台可播放的引用。
///
/// 背景：短片剪辑页此前直接 `import 'dart:html'`（blob URL），导致 Android/iOS
/// 编译失败（`dart:html` 仅 Web 可用）。本层用条件导入做平台分流：
///   - Web：字节 → blob URL（dart:html），`networkUrl` 播放。
///   - Android / iOS：字节 → 临时文件（dart:io），`file` 路径播放。
///
/// 页面侧统一调用 [MediaPlatform]，不再直接触碰 dart:html / dart:io。
library;

import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';

import 'media_platform_stub.dart'
    if (dart.library.io) 'media_platform_io.dart'
    if (dart.library.html) 'media_platform_web.dart' as impl;

abstract final class MediaPlatform {
  const MediaPlatform._();

  /// 把字节流转成平台可播放的引用（Web: blob URL；原生: 临时文件路径）。
  static Future<String> createMediaUrl(Uint8List bytes, String mime) =>
      impl.createMediaUrl(bytes, mime);

  /// 释放引用（Web: revoke blob URL；原生: 删除临时文件）。
  static Future<void> releaseMediaUrl(String url) =>
      impl.releaseMediaUrl(url);

  /// 创建视频控制器（Web: networkUrl(blob)；原生: file(临时文件)）。
  static VideoPlayerController videoController(String url) =>
      impl.videoController(url);

  /// 创建音频源（Web: UrlSource(blob)；原生: DeviceFileSource(临时文件)）。
  static Source audioSource(String url) => impl.audioSource(url);

  /// 下载字节到用户本地（Web: 浏览器下载；原生: 写临时文件）。
  static Future<void> downloadBytes(Uint8List bytes, String filename) =>
      impl.downloadBytes(bytes, filename);
}
