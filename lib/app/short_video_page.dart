import 'dart:async';
import 'dart:html'
    as html; // Web 端用 blob URL 播放用户选取的视频/音频（仅 Web 演示端，Android 端接入时需改文件源）
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_camera/app/app_back_button.dart';
import 'package:pet_camera/app/app_primary_action_button.dart';
import 'package:pet_camera/app/app_segmented_toggle.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/short_videos.dart';
import 'package:video_player/video_player.dart';

const _fieldBorderColor = Color(0xFFE2E4E6);

/// 裁剪滑块按钮。
/// 按用户给的 CSS 固定为 24x24、黄色填充、4px 黑色描边。
class _TrimRangeThumbShape extends RangeSliderThumbShape {
  const _TrimRangeThumbShape();

  static const double _outerRadius = 12;
  static const double _innerRadius = 8;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size.square(_outerRadius * 2);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool isOnTop = false,
    TextDirection textDirection = TextDirection.ltr,
    required SliderThemeData sliderTheme,
    Thumb thumb = Thumb.start,
    bool isPressed = false,
  }) {
    final canvas = context.canvas;
    final outerPaint = Paint()..color = Colors.black;
    final innerPaint = Paint()..color = const Color(0xFFFFF032);

    // 先画黑色外圆，再画黄色内圆，得到 4px 描边效果。
    canvas.drawCircle(center, _outerRadius, outerPaint);
    canvas.drawCircle(center, _innerRadius, innerPaint);
  }
}

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

/// 短片剪辑页：选视频 → 裁剪 → 加字幕 → 加配乐 → 存入短片库。
/// Web 端用 file_picker 取字节 + blob URL 驱动 video_player / audioplayers。
class ShortVideoPage extends ConsumerStatefulWidget {
  const ShortVideoPage({super.key});
  @override
  ConsumerState<ShortVideoPage> createState() => _ShortVideoPageState();
}

class _ShortVideoPageState extends ConsumerState<ShortVideoPage> {
  VideoPlayerController? _controller;
  AudioPlayer? _audio;

  AudioPlayer _ensureAudio() {
    if (_audio == null) {
      try {
        _audio = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      } catch (_) {
        _audio = AudioPlayer();
      }
    }
    return _audio!;
  }

  Uint8List? _videoBytes;
  String? _videoUrl;
  Uint8List? _musicBytes;
  String? _musicUrl;
  String? _musicName;

  int _durationMs = 0;
  double _trimStart = 0; // ms
  double _trimEnd = 0; // ms
  bool _ready = false;
  bool _playing = false;
  bool _muteOriginal = false;

  final _captionCtrl = TextEditingController();
  int _captionStyle = 0;

  String? _error;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _audio?.dispose();
    _captionCtrl.dispose();
    _revoke(_videoUrl);
    _revoke(_musicUrl);
    super.dispose();
  }

  void _revoke(String? url) {
    if (url != null && url.startsWith('blob:')) html.Url.revokeObjectUrl(url);
  }

  String _blobUrl(Uint8List bytes, String mime) =>
      html.Url.createObjectUrlFromBlob(html.Blob(<Object>[bytes], mime));

  Future<void> _pickVideo() async {
    setState(() => _error = null);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: true,
      );
      final f = res?.files.firstOrNull;
      if (f == null || f.bytes == null) return;
      _revoke(_videoUrl);
      _controller?.dispose();
      final url = _blobUrl(f.bytes!, 'video/mp4');
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      c.addListener(_onVideoTick);
      if (mounted) {
        setState(() {
          _videoBytes = f.bytes;
          _videoUrl = url;
          _controller = c;
          _durationMs = c.value.duration.inMilliseconds;
          _trimStart = 0;
          _trimEnd = _durationMs.toDouble();
          _ready = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '选取视频失败：$e');
    }
  }

  Future<void> _pickMusic() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: true,
      );
      final f = res?.files.firstOrNull;
      if (f == null || f.bytes == null) return;
      _revoke(_musicUrl);
      if (mounted) {
        setState(() {
          _musicBytes = f.bytes;
          _musicUrl = _blobUrl(f.bytes!, 'audio/mpeg');
          _musicName = f.name;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '选取配乐失败：$e');
    }
  }

  void _onVideoTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    // 裁剪段结束自动暂停
    if (_playing &&
        c.value.position >= Duration(milliseconds: _trimEnd.round())) {
      _pause();
    }
    if (mounted) setState(() {});
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_playing) {
      _pause();
      return;
    }
    await c.seekTo(Duration(milliseconds: _trimStart.round()));
    await c.setVolume(_muteOriginal ? 0 : 1);
    await c.play();
    if (_musicUrl != null) {
      try {
        await _ensureAudio().play(UrlSource(_musicUrl!), volume: 0.6);
      } catch (_) {}
    }
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _pause() async {
    await _controller?.pause();
    await _audio?.pause();
    if (mounted) setState(() => _playing = false);
  }

  void _onTrimChanged(RangeValues v) {
    setState(() {
      _trimStart = v.start;
      _trimEnd = v.end;
    });
    // 拖动时预览定位到裁剪起点
    _controller?.seekTo(Duration(milliseconds: v.start.round()));
  }

  void _save() {
    if (_videoBytes == null || !_ready) return;
    ref
        .read(shortVideosProvider.notifier)
        .add(
          ShortVideoEdit(
            videoBytes: _videoBytes!,
            musicBytes: _musicBytes,
            trimStartMs: _trimStart.round(),
            trimEndMs: _trimEnd.round(),
            caption: _captionCtrl.text.trim(),
            captionStyle: _captionStyle,
            muteOriginal: _muteOriginal,
          ),
        );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已存入短片库')));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 44,
        leading: AppBackButton(onTap: () => Navigator.pop(context)),
        centerTitle: true,
        title: Text(
          '短片剪辑',
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ShortVideoLibraryPage(),
                  ),
                );
              },
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: MingCuteIcon(
                    MingCuteIcons.videoLine,
                    size: AppUi.iconMedium,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _ready
          ? AppPrimaryActionIconBottomBar(
              label: '保存到短片库',
              iconWidget: const MingCuteIcon(
                MingCuteIcons.videoLine,
                size: AppUi.iconSmall,
                color: Colors.black,
              ),
              onPressed: _save,
            )
          : null,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 24, 16, _ready ? 120 : 16),
        children: [
          _VideoStage(
            controller: _controller,
            ready: _ready,
            playing: _playing,
            caption: _captionCtrl.text,
            captionStyle: _captionStyle,
            onTogglePlay: _togglePlay,
            onPick: _pickVideo,
          ),
          if (_ready) ...[
            const SizedBox(height: 24),
            _TrimBar(
              durationMs: _durationMs,
              start: _trimStart,
              end: _trimEnd,
              onChanged: _onTrimChanged,
            ),
            const SizedBox(height: 24),
            _CaptionRow(
              controller: _captionCtrl,
              style: _captionStyle,
              onStyle: (i) => setState(() => _captionStyle = i),
            ),
            const SizedBox(height: 24),
            _MusicRow(
              musicName: _musicName,
              onPick: _pickMusic,
              muteOriginal: _muteOriginal,
              onMute: (v) {
                setState(() => _muteOriginal = v);
                _controller?.setVolume(v ? 0 : 1);
              },
            ),
          ] else if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: t.error, fontSize: AppUi.fontBody),
            ),
          ],
        ],
      ),
    );
  }
}

/// 我的短片页：独立展示已保存的短片列表。
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
              // 空状态在页面可视区域内上下左右居中显示。
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
                    '剪辑好的短片会显示在这里',
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

/// 视频舞台：未选时显示选取按钮，已选时显示预览 + 播放浮层 + 字幕。
class _VideoStage extends StatelessWidget {
  const _VideoStage({
    required this.controller,
    required this.ready,
    required this.playing,
    required this.caption,
    required this.captionStyle,
    required this.onTogglePlay,
    required this.onPick,
  });
  final VideoPlayerController? controller;
  final bool ready;
  final bool playing;
  final String caption;
  final int captionStyle;
  final VoidCallback onTogglePlay;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final style = _captionStyles[captionStyle];
    final hasVideo =
        ready && controller != null && controller!.value.isInitialized;
    return AspectRatio(
      // 无论是否已选择视频，预览区域都保持正方形。
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: hasVideo ? Colors.black : const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
        ),
        clipBehavior: Clip.antiAlias,
        child: hasVideo
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: controller!.value.aspectRatio,
                      child: VideoPlayer(controller!),
                    ),
                  ),
                  if (caption.isNotEmpty)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 28,
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
                      onTap: onTogglePlay,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: MingCuteIcon(
                          playing ? MingCuteIcons.pause : MingCuteIcons.play,
                          size: AppUi.iconLarge,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : InkWell(
                onTap: onPick,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    MingCuteIcon(
                      MingCuteIcons.clapperboardLine,
                      size: 24,
                      color: context.tokens.textSecondary,
                    ),
                    const SizedBox(height: AppUi.space8),
                    Text(
                      '请先选择视频',
                      style: TextStyle(
                        fontSize: AppUi.fontBody,
                        height: AppUi.lineHeight(AppUi.fontBody),
                        fontWeight: FontWeight.w400,
                        color: context.tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// 裁剪条：RangeSlider + 起止时间标签。
class _TrimBar extends StatelessWidget {
  const _TrimBar({
    required this.durationMs,
    required this.start,
    required this.end,
    required this.onChanged,
  });
  final int durationMs;
  final double start;
  final double end;
  final ValueChanged<RangeValues> onChanged;

  String _fmt(double ms) {
    final s = (ms / 1000).floor();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (durationMs <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '剪辑短片',
          style: TextStyle(
            fontSize: AppUi.fontHeadline,
            height: 28 / AppUi.fontHeadline,
            fontWeight: FontWeight.w400,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          // 去掉按钮按压扩散层后，容器上下留白收紧一点，视觉上更贴合内容高度。
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(AppUi.radiusCard),
          ),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  // 裁剪滑块改为纯黑色轨道与按钮，避免和主色按钮混淆。
                  activeTrackColor: Colors.black,
                  inactiveTrackColor: const Color(0xFFE6E6E6),
                  thumbColor: Colors.black,
                  // 去掉按住拖动按钮时的半透明黑色扩散层。
                  overlayColor: Colors.transparent,
                  rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
                  trackHeight: 4,
                  rangeThumbShape: const _TrimRangeThumbShape(),
                ),
                child: RangeSlider(
                  min: 0,
                  max: durationMs.toDouble(),
                  values: RangeValues(start, end),
                  divisions: (durationMs / 200).round().clamp(1, 2000),
                  onChanged: onChanged,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '起 ${_fmt(start)}',
                      style: TextStyle(
                        fontSize: AppUi.fontCaption,
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '共 ${((end - start) / 1000).ceil()} 秒',
                        style: TextStyle(
                          fontSize: AppUi.fontCaption,
                          color: t.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '止 ${_fmt(end)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: AppUi.fontCaption,
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 字幕行：输入框 + 样式 chips。
class _CaptionRow extends StatelessWidget {
  const _CaptionRow({
    required this.controller,
    required this.style,
    required this.onStyle,
  });
  final TextEditingController controller;
  final int style;
  final ValueChanged<int> onStyle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '加字幕',
          style: TextStyle(
            fontSize: AppUi.fontHeadline,
            height: 28 / AppUi.fontHeadline,
            fontWeight: FontWeight.w400,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 2,
          style: TextStyle(
            fontSize: AppUi.fontBody,
            height: AppUi.lineHeight(AppUi.fontBody),
            color: t.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: '例如：今天也是可爱的一天',
            hintStyle: TextStyle(
              fontSize: AppUi.fontBody,
              height: AppUi.lineHeight(AppUi.fontBody),
              color: t.textSecondary,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              borderSide: const BorderSide(color: _fieldBorderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              borderSide: const BorderSide(color: _fieldBorderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              borderSide: const BorderSide(color: Color(0xFF000000)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _captionStyles.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 36,
          ),
          itemBuilder: (context, index) {
            final selected = index == style;
            return GestureDetector(
              onTap: () => onStyle(index),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  border: Border.all(
                    color: selected ? t.brand : _fieldBorderColor,
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    _captionStyles[index].label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppUi.fontCaption,
                      height: 20 / AppUi.fontCaption,
                      fontWeight: FontWeight.w400,
                      color: t.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 配乐行：选择音频 + 静音原声。
class _MusicRow extends StatelessWidget {
  const _MusicRow({
    required this.musicName,
    required this.onPick,
    required this.muteOriginal,
    required this.onMute,
  });
  final String? musicName;
  final VoidCallback onPick;
  final bool muteOriginal;
  final ValueChanged<bool> onMute;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '配乐',
              style: TextStyle(
                fontSize: AppUi.fontHeadline,
                height: 28 / AppUi.fontHeadline,
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            AppSegmentedToggle(
              leftLabel: '保留原声',
              rightLabel: '关闭原声',
              rightSelected: muteOriginal,
              onSelectLeft: () => onMute(false),
              onSelectRight: () => onMute(true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onPick,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              border: Border.all(color: _fieldBorderColor),
            ),
            child: Row(
              children: [
                const MingCuteIcon(
                  MingCuteIcons.music,
                  size: AppUi.iconMedium,
                  color: Colors.black,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    musicName ?? '选择一段音乐',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppUi.fontBody,
                      color: t.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
                  '剪辑好的短片会显示在这里',
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
    _videoUrl = html.Url.createObjectUrlFromBlob(
      html.Blob(<Object>[e.videoBytes], e.mimeType),
    );
    if (e.musicBytes != null) {
      _musicUrl = html.Url.createObjectUrlFromBlob(
        html.Blob(<Object>[e.musicBytes!], 'audio/mpeg'),
      );
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(_videoUrl!));
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
        await _ensureAudio().play(UrlSource(_musicUrl!), volume: 0.6);
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
    if (_videoUrl != null && _videoUrl!.startsWith('blob:'))
      html.Url.revokeObjectUrl(_videoUrl!);
    if (_musicUrl != null && _musicUrl!.startsWith('blob:'))
      html.Url.revokeObjectUrl(_musicUrl!);
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
