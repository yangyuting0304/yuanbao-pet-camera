/// 动态照片播放器（原生端真实播放，Web 端回落为静态图）。
///
/// 为什么要单独分文件：播放需要 `dart:io` 的 File 与 `video_player`，
/// 直接写在 pages.dart 里会让 Web 构建失败——与 photo_storage /
/// media_platform 同一套条件导入模式。
library;

import 'package:flutter/widgets.dart';

import 'live_player_stub.dart'
    if (dart.library.io) 'live_player_io.dart' as impl;

/// 构造一个播放 [path] 短片的组件；无法播放时显示 [fallback]。
Widget buildLivePlayer(String path, {required Widget fallback}) =>
    impl.buildLivePlayer(path, fallback: fallback);
