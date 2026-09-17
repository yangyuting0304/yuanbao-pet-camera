import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用户剪辑的萌宠短片（短片剪辑功能）。
/// 与 captured_photos 一致：采用内存态 Riverpod，跨页面可见、刷新后清空（演示态）。
/// 后续如需持久化，可仿 captured_photos 接 Hive/IndexedDB，无需改动 UI 层。
class ShortVideoEdit {
  const ShortVideoEdit({
    required this.videoBytes,
    this.musicBytes,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.caption,
    required this.captionStyle,
    this.mimeType = 'video/mp4',
    this.muteOriginal = false,
  });

  final Uint8List videoBytes;
  final Uint8List? musicBytes;
  final int trimStartMs;
  final int trimEndMs;
  final String caption;
  final int captionStyle; // 索引，对应 short_video_page 的 _captionStyles
  // Web 端相机录制为 video/webm；用户导入的剪辑文件多为 video/mp4。
  // 影响 blob 播放时的 MIME，必须与真实字节格式一致，否则 HTML <video> 拒绝加载。
  final String mimeType;
  final bool muteOriginal;

  int get durationMs => (trimEndMs - trimStartMs).clamp(0, 1 << 30);
  String get label => caption.isEmpty ? '萌宠短片' : caption;
}

/// 短片库状态：最新剪辑排在列表最前。
class ShortVideosNotifier extends Notifier<List<ShortVideoEdit>> {
  @override
  List<ShortVideoEdit> build() => const [];

  void add(ShortVideoEdit edit) {
    state = [edit, ...state];
  }

  void clear() => state = const [];
}

final shortVideosProvider =
    NotifierProvider<ShortVideosNotifier, List<ShortVideoEdit>>(
      ShortVideosNotifier.new,
    );
