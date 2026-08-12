import 'dart:async';
import 'dart:html' as html; // Web 端用 blob URL 播放用户选取的视频/音频（仅 Web 演示端，Android 端接入时需改文件源）
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
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
  _CaptionStyle('白字描边', Color(0xFFFFFFFF), Color(0xFF000000), 22),
  _CaptionStyle('黄字', Color(0xFFFFE14D), Color(0xFF5A4A00), 22),
  _CaptionStyle('粉字', Color(0xFFFF9EC4), Color(0xFF7A2E4A), 22),
  _CaptionStyle('黑字白描边', Color(0xFF2B2622), Color(0xFFFFFFFF), 22),
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
    if (_playing && c.value.position >= Duration(milliseconds: _trimEnd.round())) {
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
    ref.read(shortVideosProvider.notifier).add(ShortVideoEdit(
          videoBytes: _videoBytes!,
          musicBytes: _musicBytes,
          trimStartMs: _trimStart.round(),
          trimEndMs: _trimEnd.round(),
          caption: _captionCtrl.text.trim(),
          captionStyle: _captionStyle,
          muteOriginal: _muteOriginal,
        ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已存入短片库')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shorts = ref.watch(shortVideosProvider);
    return Scaffold(
      backgroundColor: t.bgBase,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.chevronLeft, color: t.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('短片剪辑',
            style: TextStyle(fontWeight: FontWeight.w700, color: t.textPrimary)),
        backgroundColor: t.surface,
        foregroundColor: t.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 12),
            _TrimBar(
              durationMs: _durationMs,
              start: _trimStart,
              end: _trimEnd,
              onChanged: _onTrimChanged,
            ),
            const SizedBox(height: 16),
            _CaptionRow(
              controller: _captionCtrl,
              style: _captionStyle,
              onStyle: (i) => setState(() => _captionStyle = i),
            ),
            const SizedBox(height: 16),
            _MusicRow(
              musicName: _musicName,
              onPick: _pickMusic,
              muteOriginal: _muteOriginal,
              onMute: (v) {
                setState(() => _muteOriginal = v);
                _controller?.setVolume(v ? 0 : 1);
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(LucideIcons.save),
                label: const Text('保存到短片库',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: t.brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25)),
                  elevation: 0,
                ),
              ),
            ),
          ] else if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: t.error, fontSize: 13)),
          ],
          const SizedBox(height: 28),
          _LibrarySection(onPlay: _openPlayback),
        ],
      ),
    );
  }

  void _openPlayback(ShortVideoEdit edit) {
    showDialog(
      context: context,
      builder: (_) => _PlaybackDialog(edit: edit),
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
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: ready && controller != null && controller!.value.isInitialized
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Center(child: VideoPlayer(controller!)),
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
                          fontWeight: FontWeight.w800,
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
                        child: Icon(
                          playing ? LucideIcons.pause : LucideIcons.play,
                          color: Colors.white,
                          size: 30,
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
                    Icon(LucideIcons.film, size: 44, color: Colors.white70),
                    const SizedBox(height: 12),
                    const Text('点击选择一段宠物视频',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
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
        Text('裁剪片段',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 8),
        RangeSlider(
          min: 0,
          max: durationMs.toDouble(),
          values: RangeValues(start, end),
          divisions: (durationMs / 200).round().clamp(1, 2000),
          activeColor: t.brand,
          inactiveColor: t.brandSoft,
          onChanged: onChanged,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('起 ${_fmt(start)}', style: TextStyle(fontSize: 12, color: t.textSecondary)),
            Text('止 ${_fmt(end)} · 共 ${_fmt(end - start)}',
                style: TextStyle(fontSize: 12, color: t.textSecondary)),
          ],
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
        Text('加字幕',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '例如：今天也是可爱的一天',
            fillColor: t.surface,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (int i = 0; i < _captionStyles.length; i++)
              GestureDetector(
                onTap: () => onStyle(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: i == style ? t.brand : t.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: i == style ? t.brand : t.brandSoft,
                      width: 1,
                    ),
                  ),
                  child: Text(_captionStyles[i].label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: i == style ? Colors.white : t.textPrimary,
                      )),
                ),
              ),
          ],
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
        Text('配乐',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onPick,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.brandSoft),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.music, size: 18, color: t.brand),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          musicName ?? '选择一段配乐',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: t.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Row(
              children: [
                Icon(LucideIcons.volumeX, size: 16, color: t.textSecondary),
                Switch(
                  value: muteOriginal,
                  activeColor: t.brand,
                  onChanged: onMute,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// 短片库：网格展示已保存剪辑，点击播放。
class _LibrarySection extends ConsumerWidget {
  const _LibrarySection({required this.onPlay});
  final void Function(ShortVideoEdit) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final shorts = ref.watch(shortVideosProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.library, size: 18, color: t.brand),
            const SizedBox(width: 8),
            Text('我的短片',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary)),
            const SizedBox(width: 6),
            Text('${shorts.length}', style: TextStyle(fontSize: 13, color: t.textSecondary)),
          ],
        ),
        const SizedBox(height: 12),
        if (shorts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Icon(LucideIcons.clapperboard, size: 32, color: t.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                Text('剪辑好的短片会显示在这里',
                    style: TextStyle(fontSize: 13, color: t.textSecondary)),
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
                child: Container(
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: Colors.black),
                            const Center(
                              child: Icon(LucideIcons.playCircle, size: 40, color: Colors.white70),
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('${secs}s',
                                    style: const TextStyle(fontSize: 11, color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.textPrimary)),
                      ),
                    ],
                  ),
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
  int get _effectiveEnd =>
      widget.edit.trimEndMs > widget.edit.trimStartMs ? widget.edit.trimEndMs : _durationMs;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final e = widget.edit;
    _videoUrl = html.Url.createObjectUrlFromBlob(html.Blob(<Object>[e.videoBytes], e.mimeType));
    if (e.musicBytes != null) {
      _musicUrl = html.Url.createObjectUrlFromBlob(html.Blob(<Object>[e.musicBytes!], 'audio/mpeg'));
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
    if (_videoUrl != null && _videoUrl!.startsWith('blob:')) html.Url.revokeObjectUrl(_videoUrl!);
    if (_musicUrl != null && _musicUrl!.startsWith('blob:')) html.Url.revokeObjectUrl(_musicUrl!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = _captionStyles[widget.edit.captionStyle];
    final caption = widget.edit.caption;
    return Dialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 9 / 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(14),
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
                                    fontWeight: FontWeight.w800,
                                    color: style.color,
                                    shadows: [
                                      Shadow(color: style.stroke, offset: const Offset(1.5, 1.5), blurRadius: 2),
                                      Shadow(color: style.stroke, offset: const Offset(-1.5, -1.5), blurRadius: 2),
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
                                  child: Icon(
                                    _playing ? LucideIcons.pause : LucideIcons.play,
                                    color: Colors.white,
                                    size: 28,
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
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
