import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'short_video_storage.dart';

/// 用户剪辑的萌宠短片（短片剪辑功能）。
/// 元数据使用 Hive，视频使用本地文件/IndexedDB，刷新与重启后恢复。
/// 列表只保留引用，打开单条时才读取视频字节。
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
    this.rendered = false,
    this.storageRef,
    this.id = '',
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
  final bool rendered;
  final String? storageRef;
  final String id;

  Future<Uint8List> readVideoBytes() => storageRef == null
      ? Future.value(videoBytes)
      : readShortVideo(storageRef!);

  Map<String, Object?> toMap() => {
    'id': id,
    'ref': storageRef,
    'start': trimStartMs,
    'end': trimEndMs,
    'caption': caption,
    'style': captionStyle,
    'mime': mimeType,
    'mute': muteOriginal,
    'rendered': rendered,
  };

  factory ShortVideoEdit.fromMap(Map map) => ShortVideoEdit(
    videoBytes: Uint8List(0),
    trimStartMs: map['start'] as int,
    trimEndMs: map['end'] as int,
    caption: map['caption'] as String,
    captionStyle: map['style'] as int,
    mimeType: map['mime'] as String,
    muteOriginal: map['mute'] == true,
    rendered: map['rendered'] == true,
    storageRef: map['ref'] as String?,
    id: map['id'] as String,
  );

  int get durationMs => (trimEndMs - trimStartMs).clamp(0, 1 << 30);
  String get label => caption.isEmpty ? '萌宠短片' : caption;
}

/// 短片库状态：最新剪辑排在列表最前。
class ShortVideosNotifier extends Notifier<List<ShortVideoEdit>> {
  @override
  List<ShortVideoEdit> build() {
    if (!Hive.isBoxOpen('shortVideos')) return const [];
    final rows = Hive.box('shortVideos').get('items') as List? ?? [];
    final edits = <ShortVideoEdit>[];
    for (final row in rows) {
      try {
        edits.add(ShortVideoEdit.fromMap(row as Map));
      } catch (_) {
        /* Skip a corrupt record, retain others. */
      }
    }
    return edits;
  }

  Future<void> add(ShortVideoEdit edit) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final file = await storeShortVideo(
      '$id.${edit.mimeType.contains('webm') ? 'webm' : 'mp4'}',
      edit.videoBytes,
    );
    final saved = ShortVideoEdit(
      videoBytes: Uint8List(0),
      trimStartMs: edit.trimStartMs,
      trimEndMs: edit.trimEndMs,
      caption: edit.caption,
      captionStyle: edit.captionStyle,
      mimeType: edit.mimeType,
      muteOriginal: edit.muteOriginal,
      rendered: edit.rendered,
      storageRef: file,
      id: id,
    );
    final next = [saved, ...state];
    try {
      await Hive.box(
        'shortVideos',
      ).put('items', next.map((e) => e.toMap()).toList());
      state = next;
    } catch (_) {
      await deleteShortVideo(file);
      rethrow;
    }
  }

  Future<void> remove(ShortVideoEdit edit) async {
    final next = state.where((e) => e.id != edit.id).toList();
    await Hive.box(
      'shortVideos',
    ).put('items', next.map((e) => e.toMap()).toList());
    state = next;
    if (edit.storageRef != null) await deleteShortVideo(edit.storageRef!);
  }

  Future<void> clear() async {
    final old = state;
    await Hive.box('shortVideos').delete('items');
    state = const [];
    for (final e in old) {
      if (e.storageRef != null) await deleteShortVideo(e.storageRef!);
    }
  }
}

final shortVideosProvider =
    NotifierProvider<ShortVideosNotifier, List<ShortVideoEdit>>(
      ShortVideosNotifier.new,
    );
