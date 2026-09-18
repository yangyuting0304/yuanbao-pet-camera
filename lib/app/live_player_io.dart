// 原生端实现：循环播放本地的动态照片短片。
//
// 只编译进 Android / iOS 产物（dart:io 依赖由 live_player.dart 的条件导入隔离）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 动态照片播放器：循环播放本地短片，失败时回落到静态图。
class LivePlayer extends StatefulWidget {
  const LivePlayer({super.key, required this.path, required this.fallback});

  final String path;

  /// 短片未就绪 / 播放失败时显示的静态图（就是这张照片本身）。
  final Widget fallback;

  @override
  State<LivePlayer> createState() => _LivePlayerState();
}

class _LivePlayerState extends State<LivePlayer> {
  VideoPlayerController? _player;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.file(File(widget.path));
      await controller.initialize();
      // 动态照片是"一小段循环"，不是正片——循环播放才符合直觉。
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        // 加载期间弹窗被关掉了，直接释放，避免播放器常驻。
        await controller.dispose();
        return;
      }
      setState(() => _player = controller);
    } catch (e) {
      // 短片损坏 / 已被清理时保持静态图，不让用户看到黑屏。
      debugPrint('[动态照片] 播放失败：$e');
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _player;
    if (controller == null) return widget.fallback;
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }
}

Widget buildLivePlayer(String path, {required Widget fallback}) =>
    LivePlayer(path: path, fallback: fallback);
