import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_camera/app/app_back_button.dart';
import 'package:pet_camera/app/media_platform.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/short_videos.dart';
import 'package:video_player/video_player.dart';

/// 字幕样式（内容层，用户可选）：白字黑描边 / 黄字 / 粉字 / 黑字白描边。
class _CaptionStyle {
  const _CaptionStyle(this.label, this.color, this.stroke, this.size);
  final String label;
  final Color color;
  final Color stroke;
  final double size;
}

const _captionStyles = <_CaptionStyle>[
  _CaptionStyle(
    '白字描边',
    Color(0xFFFFFFFF),
    Color(0xFF000000),
    AppUi.fontHeadline,
  ),
  _CaptionStyle('黄字', Color(0xFFFFE14D), Color(0xFF5A4A00), AppUi.fontHeadline),
  _CaptionStyle('粉字', Color(0xFFFF9EC4), Color(0xFF7A2E4A), AppUi.fontHeadline),
  _CaptionStyle(
    '黑字白描边',
    Color(0xFF2B2622),
    Color(0xFFFFFFFF),
    AppUi.fontHeadline,
  ),
];

/// 我的短片页：独立展示已保存的短片列表（AI 成片 / 相机录制）。
class ShortVideoLibraryPage extends ConsumerWidget {
  const ShortVideoLibraryPage({super.key});

  void _openPlayback(BuildContext context, ShortVideoEdit edit) {
    showDialog(
      context: context,
      builder: (_) => _PlaybackDialog(edit: edit),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final shorts = ref.watch(shortVideosProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 44,
        leading: AppBackButton(onTap: () => Navigator.pop(context)),
        centerTitle: true,
        title: Text(
          '我的短片',
          style: TextStyle(
            fontSize: AppUi.fontTitle,
            height: AppUi.lineHeight(AppUi.fontTitle),
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        backgroundColor: t.surface,
        foregroundColor: t.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: shorts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MingCuteIcon(
                    MingCuteIcons.clapperboardLine,
                    size: 24,
                    color: t.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI 生成的短片会显示在这里',
                    style: TextStyle(
                      fontSize: AppUi.fontBody,
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              children: [
                _LibrarySection(
                  showHeader: false,
                  onPlay: (edit) => _openPlayback(context, edit),
                ),
              ],
            ),
    );
  }
}

/// 短片库：网格展示已保存剪辑，点击播放。
class _LibrarySection extends ConsumerWidget {
  const _LibrarySection({required this.onPlay, this.showHeader = true});
  final void Function(ShortVideoEdit) onPlay;
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final shorts = ref.watch(shortVideosProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              MingCuteIcon(
                MingCuteIcons.playlist,
                size: AppUi.iconMedium,
                color: t.brand,
              ),
              const SizedBox(width: 8),
              Text(
                '我的短片',
                style: TextStyle(
                  fontSize: AppUi.fontTitle,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${shorts.length}',
                style: TextStyle(
                  fontSize: AppUi.fontBody,
                  color: t.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (shorts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
            ),
            child: Column(
              children: [
                MingCuteIcon(
                  MingCuteIcons.clapperboardLine,
                  size: AppUi.iconLarge,
                  color: t.textSecondary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'AI 生成的短片会显示在这里',
                  style: TextStyle(
                    fontSize: AppUi.fontBody,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: shorts.length,
            itemBuilder: (c, i) {
              final s = shorts[i];
              final secs = (s.durationMs / 1000).ceil();
              return GestureDetector(
                onTap: () => onPlay(s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: Colors.black),
                            const Center(
                              child: MingCuteIcon(
                                MingCuteIcons.playCircle,
                                size: AppUi.iconLarge,
                                color: Colors.white70,
                              ),
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${secs}s',
                                  style: const TextStyle(
                                    fontSize: AppUi.fontCaption,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppUi.fontTitle,
                        fontWeight: FontWeight.w400,
                        color: t.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// 短片回放弹窗：按保存的剪辑重建播放（裁剪段 + 字幕 + 配乐）。
/// AI 成片与相机录制共用：trimEndMs=0 表示整段播放。
class _PlaybackDialog extends StatefulWidget {
  const _PlaybackDialog({required this.edit});
  final ShortVideoEdit edit;

  @override
  State<_PlaybackDialog> createState() => _PlaybackDialogState();
}

class _PlaybackDialogState extends State<_PlaybackDialog> {
  VideoPlayerController? _c;
  AudioPlayer? _audio;
  AudioPlayer _ensureAudio() {
    _audio ??= AudioPlayer();
    return _audio!;
  }

  bool _playing = false;
  bool _ready = false;
  int _durationMs = 0;
  String? _videoUrl;
  String? _musicUrl;

  // 录制产生的视频 trimEndMs=0（未知时长），视为「整段」；
  // 仅当 trimEndMs 明确大于 start 时才作为裁剪终点。
  int get _effectiveStart => widget.edit.trimStartMs;
  int get _effectiveEnd => widget.edit.trimEndMs > widget.edit.trimStartMs
      ? widget.edit.trimEndMs
      : _durationMs;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final e = widget.edit;
    _videoUrl = await MediaPlatform.createMediaUrl(e.videoBytes, e.mimeType);
    if (e.musicBytes != null) {
      _musicUrl = await MediaPlatform.createMediaUrl(e.musicBytes!, 'audio/mpeg');
    }
    final c = MediaPlatform.videoController(_videoUrl!);
    _c = c;
    await c.initialize();
    _durationMs = c.value.duration.inMilliseconds;
    c.addListener(_tick);
    if (mounted) setState(() => _ready = true);
  }

  void _tick() {
    final c = _c;
    if (c == null) return;
    if (_playing && c.value.position >= Duration(milliseconds: _effectiveEnd)) {
      _pause();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (_playing) {
      _pause();
      return;
    }
    await c.seekTo(Duration(milliseconds: _effectiveStart));
    await c.setVolume(widget.edit.muteOriginal ? 0 : 1);
    await c.play();
    if (_musicUrl != null) {
      try {
        await _ensureAudio().play(MediaPlatform.audioSource(_musicUrl!), volume: 0.6);
      } catch (_) {}
    }
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _pause() async {
    await _c?.pause();
    await _audio?.pause();
    if (mounted) setState(() => _playing = false);
  }

  @override
  void dispose() {
    _c?.dispose();
    _audio?.dispose();
    if (_videoUrl != null) MediaPlatform.releaseMediaUrl(_videoUrl!);
    if (_musicUrl != null) MediaPlatform.releaseMediaUrl(_musicUrl!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = _captionStyles[widget.edit.captionStyle];
    final caption = widget.edit.caption;
    return Dialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 9 / 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _ready && _c != null && _c!.value.isInitialized
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(child: VideoPlayer(_c!)),
                            if (caption.isNotEmpty)
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 24,
                                child: Text(
                                  caption,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: style.size,
                                    fontWeight: FontWeight.w700,
                                    color: style.color,
                                    shadows: [
                                      Shadow(
                                        color: style.stroke,
                                        offset: const Offset(1.5, 1.5),
                                        blurRadius: 2,
                                      ),
                                      Shadow(
                                        color: style.stroke,
                                        offset: const Offset(-1.5, -1.5),
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            Center(
                              child: GestureDetector(
                                onTap: _toggle,
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    shape: BoxShape.circle,
                                  ),
                                  child: MingCuteIcon(
                                    _playing
                                        ? MingCuteIcons.pause
                                        : MingCuteIcons.play,
                                    size: AppUi.iconLarge,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : const Center(child: CircularProgressIndicator()),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: t.brand,
                    foregroundColor: t.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
