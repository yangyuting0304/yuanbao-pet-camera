import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_camera/data/prepare_local_photo.dart';
import 'package:pet_camera/data/app_font.dart';
import 'package:pet_camera/app/share_media.dart';
import 'package:pet_camera/app/media_platform.dart';
import 'package:pet_camera/app/short_video_page.dart';
import 'package:pet_camera/data/captured_photos.dart';
import 'package:pet_camera/data/movie_export.dart';
import 'package:pet_camera/data/short_videos.dart';
import 'package:video_player/video_player.dart';

/// Photo templates and real clip editing. Export happens entirely on the device.
class MoviePage extends ConsumerStatefulWidget {
  const MoviePage({super.key});
  @override
  ConsumerState<MoviePage> createState() => _MoviePageState();
}

class _MoviePageState extends ConsumerState<MoviePage> {
  final _caption = TextEditingController();
  final _photos = <Uint8List>[];
  final _names = <String>[];
  Uint8List? _video, _music;
  String _videoExtension = 'mp4', _musicExtension = 'mp3', _musicName = '';
  VideoPlayerController? _player;
  String? _videoUrl, _resultUrl, _error;
  VideoPlayerController? _resultPlayer;
  MovieExportResult? _result;
  int _seconds = 3, _template = 0;
  RangeValues _range = const RangeValues(0, 10);
  bool _mute = false, _busy = false, _saving = false, _saved = false;
  String _stage = '';
  static const _templates = ['日常留白', '奶油相册', '主体全屏'];
  bool _loadedArgument = false;
  bool _subjectFill = false, _momentSlow = false;
  double _focusX = .5, _focusY = .5, _zoom = 1, _speed = 1;
  int? _cueMs;
  String _cueLabel = '';

  List<MovieSegment> get _segments {
    final start = (_range.start * 1000).round(),
        end = (_range.end * 1000).round();
    if (_momentSlow && _cueMs != null && _cueMs! >= start && _cueMs! <= end) {
      return momentRecipe(
        _cueMs!,
        start,
        end,
        speed: _speed == 1 ? .5 : _speed,
      );
    }
    return [MovieSegment(start, end, speed: _speed)];
  }

  bool get _hasSlow => _segments.any((s) => s.speed != 1);

  Future<void> _findMoment() async {
    if (_video == null || _busy) return;
    setState(() {
      _busy = true;
      _stage = '正在本机挑选动作片段…';
      _error = null;
    });
    try {
      await _player?.pause();
      final samples = await analyzeMovie(
        _video!,
        _videoExtension,
        startMs: (_range.start * 1000).round(),
        durationMs: ((_range.end - _range.start) * 1000).round(),
        focusX: _focusX,
        focusY: _focusY,
      );
      final best = bestActionMoment(samples);
      if (!mounted) return;
      if (best == null) {
        _message('没有找到清晰的动作候选，可以播放后手动标记眨眼或转头');
        return;
      }
      await _player?.seekTo(Duration(milliseconds: best.timeMs));
      if (mounted) {
        setState(() {
          _cueMs = best.timeMs;
          _cueLabel = '动作候选，请确认';
          _momentSlow = true;
          _speed = .5;
          _result = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '选片未完成：$e，可以手动标记');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sourcePreview() {
    final player = _player!;
    final size = player.value.size;
    final crop = subjectCrop(size.width, size.height, _focusX, _focusY, _zoom);
    return GestureDetector(
      onTapUp: (tap) {
        final box = tap.localPosition;
        // In fill mode, taps select a point in the currently visible crop.
        final render =
            _previewKey.currentContext?.findRenderObject() as RenderBox?;
        if (render == null) return;
        final x = (box.dx / render.size.width).clamp(0.0, 1.0),
            y = (box.dy / render.size.height).clamp(0.0, 1.0);
        var targetX = crop.x + x * crop.width,
            targetY = crop.y + y * crop.height;
        if (!_subjectFill) {
          final scale =
              (render.size.width / size.width <
                  render.size.height / size.height)
              ? render.size.width / size.width
              : render.size.height / size.height;
          final left = (render.size.width - size.width * scale) / 2;
          final top = (render.size.height - size.height * scale) / 2;
          targetX = (box.dx - left) / (size.width * scale);
          targetY = (box.dy - top) / (size.height * scale);
          if (targetX < 0 || targetX > 1 || targetY < 0 || targetY > 1) return;
        }
        setState(() {
          _focusX = targetX;
          _focusY = targetY;
          _subjectFill = true;
          _result = null;
        });
      },
      child: AspectRatio(
        key: _previewKey,
        aspectRatio: 9 / 16,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = _subjectFill
                ? constraints.maxWidth / (crop.width * size.width)
                : (constraints.maxWidth / size.width <
                          constraints.maxHeight / size.height
                      ? constraints.maxWidth / size.width
                      : constraints.maxHeight / size.height);
            return ClipRect(
              child: ColoredBox(
                color: const Color(0xFF262421),
                child: Stack(
                  children: [
                    Positioned(
                      left: _subjectFill
                          ? -crop.x * size.width * scale
                          : (constraints.maxWidth - size.width * scale) / 2,
                      top: _subjectFill
                          ? -crop.y * size.height * scale
                          : (constraints.maxHeight - size.height * scale) / 2,
                      width: size.width * scale,
                      height: size.height * scale,
                      child: VideoPlayer(player),
                    ),
                    const Center(
                      child: IgnorePointer(
                        child: Icon(
                          Icons.center_focus_strong,
                          color: Colors.white70,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  final _previewKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedArgument) return;
    _loadedArgument = true;
    final clip = ModalRoute.of(context)?.settings.arguments;
    if (clip is ShortVideoEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadStored(clip));
    }
  }

  Future<void> _loadStored(ShortVideoEdit clip) async {
    try {
      final bytes = await clip.readVideoBytes();
      if (!mounted) return;
      if (bytes.length > 80 * 1024 * 1024) {
        throw StateError('视频超过80MB，请从系统相册选取较短的片段');
      }
      _videoExtension = clip.mimeType.contains('webm') ? 'webm' : 'mp4';
      _videoUrl = await MediaPlatform.createMediaUrl(bytes, clip.mimeType);
      if (!mounted) {
        await MediaPlatform.releaseMediaUrl(_videoUrl!);
        return;
      }
      final player = MediaPlatform.videoController(_videoUrl!);
      _player = player;
      await player.initialize();
      if (!mounted) return;
      final seconds = player.value.duration.inMilliseconds / 1000;
      if (seconds < 1) throw StateError('视频不足1秒');
      setState(() {
        _video = bytes;
        _range = RangeValues(0, seconds.clamp(1, 30));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '短片读取失败：$e');
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _pickPhotos() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (!mounted || picked == null) return;
      if (_photos.length + picked.files.length > 8) {
        _message('最多选择8张照片');
        return;
      }
      // Decode and downscale immediately. Never retain full-size RGBA images.
      for (final f in picked.files) {
        if (f.size > 25 * 1024 * 1024) throw StateError('单张照片请小于25MB');
        if (f.bytes == null) throw StateError('照片读取失败，请重新选择');
        final bytes = await prepareLocalPhoto(f.bytes!);
        if (!mounted) return;
        _photos.add(bytes);
        _names.add(f.name);
      }
      await _clearVideo();
      if (mounted) {
        setState(() {
          _result = null;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _albumPhotos() async {
    final photos = ref.read(capturedPhotosProvider);
    if (photos.isEmpty) {
      _message('还没有本地照片，可以先拍照或从手机选照片');
      return;
    }
    final choice = await showModalBottomSheet<CapturedPhoto>(
      context: context,
      builder: (context) => GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: photos.length,
        itemBuilder: (context, i) => InkWell(
          onTap: () => Navigator.pop(context, photos[i]),
          child: Image.memory(
            photos[i].bytes,
            fit: BoxFit.cover,
            cacheWidth: 180,
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (_photos.length >= 8) {
      _message('最多8张照片');
      return;
    }
    try {
      final bytes = await prepareLocalPhoto(choice.bytes);
      await _clearVideo();
      if (mounted) {
        setState(() {
          _photos.add(bytes);
          _names.add('我的照片');
          _result = null;
        });
      }
    } catch (e) {
      _message('照片读取失败：$e');
    }
  }

  Future<void> _clearVideo() async {
    final old = _player;
    _player = null;
    _video = null;
    _cueMs = null;
    _momentSlow = false;
    _speed = 1;
    _focusX = .5;
    _focusY = .5;
    _zoom = 1;
    await old?.dispose();
    if (_videoUrl != null) await MediaPlatform.releaseMediaUrl(_videoUrl!);
    _videoUrl = null;
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: true,
      );
      if (!mounted || picked == null) return;
      final f = picked.files.single;
      if (f.bytes == null || f.size > 80 * 1024 * 1024) {
        throw StateError('请选择80MB以内的视频');
      }
      await _clearVideo();
      _videoExtension = (f.extension ?? 'mp4').toLowerCase();
      _videoUrl = await MediaPlatform.createMediaUrl(
        f.bytes!,
        _videoExtension == 'webm' ? 'video/webm' : 'video/mp4',
      );
      final player = MediaPlatform.videoController(_videoUrl!);
      _player = player;
      await player.initialize();
      if (!mounted) return;
      final seconds = player.value.duration.inMilliseconds / 1000;
      if (seconds < 1) throw StateError('视频不足1秒');
      setState(() {
        _video = f.bytes;
        _photos.clear();
        _names.clear();
        _range = RangeValues(0, seconds.clamp(1, 30));
        _error = null;
        _result = null;
      });
    } catch (e) {
      await _clearVideo();
      if (mounted) setState(() => _error = '视频读取失败：$e');
    }
  }

  Future<void> _pickMusic() async {
    try {
      final p = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: true,
      );
      if (!mounted || p == null) return;
      final f = p.files.single;
      if (f.bytes == null || f.size > 10 * 1024 * 1024) {
        throw StateError('请选择10MB以内的配乐');
      }
      setState(() {
        _music = f.bytes;
        _musicExtension = f.extension ?? 'mp3';
        _musicName = f.name;
        _result = null;
      });
    } catch (e) {
      _message('配乐读取失败：$e');
    }
  }

  Future<Uint8List> _renderSlide(
    Uint8List? bytes, {
    bool overlayOnly = false,
  }) async {
    const size = Size(540, 960);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    ui.Image? image;
    ui.Codec? codec;
    if (!overlayOnly) {
      canvas.drawColor(
        [
          const Color(0xFFECE4D8),
          const Color(0xFFFFF5E5),
          Colors.black,
        ][_template],
        BlendMode.src,
      );
      codec = await ui.instantiateImageCodec(
        bytes!,
        targetWidth: 540,
        allowUpscaling: false,
      );
      image = (await codec.getNextFrame()).image;
      final rect = _template == 2
          ? const Rect.fromLTWH(0, 0, 540, 960)
          : const Rect.fromLTWH(24, 80, 492, 710);
      if (_template != 2) {
        final title = TextPainter(
          text: TextSpan(
            text: _templates[_template],
            style: const TextStyle(
              color: Color(0xFF5C401C),
              fontFamily: kBrandFontFamily,
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 492);
        title.paint(canvas, const Offset(24, 26));
      }
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(_template == 2 ? 0 : 24)),
      );
      paintImage(
        canvas: canvas,
        rect: rect,
        image: image,
        fit: _template == 2 ? BoxFit.contain : BoxFit.cover,
      );
      canvas.restore();
    }
    final text = _caption.text.trim();
    if (text.isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            fontFamily: kBrandFontFamily,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: 444);
      final top = size.height - 58 - painter.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(24, top - 14, 492, painter.height + 28),
          const Radius.circular(16),
        ),
        Paint()..color = Colors.black.withValues(alpha: .62),
      );
      painter.paint(canvas, Offset((540 - painter.width) / 2, top));
    }
    final picture = recorder.endRecording();
    final frame = await picture.toImage(540, 960);
    try {
      final data = await frame.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      frame.dispose();
      picture.dispose();
      image?.dispose();
      codec?.dispose();
    }
  }

  Future<void> _export() async {
    if (_busy || (_photos.isEmpty && _video == null)) return;
    setState(() {
      _busy = true;
      _error = null;
      _stage = '正在制作画面…';
      _result = null;
      _saved = false;
    });
    try {
      await loadBrandFont();
      await _player?.pause();
      await _resultPlayer?.dispose();
      _resultPlayer = null;
      if (_resultUrl != null) await MediaPlatform.releaseMediaUrl(_resultUrl!);
      final slides = <Uint8List>[];
      for (var i = 0; i < _photos.length; i++) {
        slides.add(await _renderSlide(_photos[i]));
        if (!mounted) return;
        setState(() => _stage = '已制作 ${i + 1}/${_photos.length} 张画面');
      }
      if (mounted) {
        setState(() => _stage = kIsWeb ? '浏览器正在编码视频，请保持页面在前台…' : '正在本机编码 MP4…');
      }
      final result = await exportMovie(
        MovieExportRequest(
          slides: slides,
          secondsPerSlide: _seconds,
          videoBytes: _video,
          videoExtension: _videoExtension,
          trimStartMs: (_range.start * 1000).round(),
          videoDurationMs: ((_range.end - _range.start) * 1000).round(),
          overlay: _video == null
              ? null
              : await _renderSlide(null, overlayOnly: true),
          musicBytes: _music,
          musicExtension: _musicExtension,
          muteOriginal: _mute || _music != null || (_video != null && _hasSlow),
          segments: _video == null ? const [] : _segments,
          subjectFill: _subjectFill,
          focusX: _focusX,
          focusY: _focusY,
          zoom: _zoom,
        ),
      );
      if (!mounted) return;
      _resultUrl = await MediaPlatform.createMediaUrl(
        result.bytes,
        result.mimeType,
      );
      final player = MediaPlatform.videoController(_resultUrl!);
      _resultPlayer = player;
      try {
        await player.initialize();
      } catch (_) {
        /* Export remains downloadable if preview codec is unavailable. */
      }
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || _saving) return;
    setState(() => _saving = true);
    try {
      if (!_saved) {
        await ref
            .read(shortVideosProvider.notifier)
            .add(
              ShortVideoEdit(
                videoBytes: result.bytes,
                trimStartMs: 0,
                trimEndMs: result.durationMs,
                caption: _caption.text.trim(),
                captionStyle: 0,
                mimeType: result.mimeType,
                rendered: true,
              ),
            );
        _saved = true;
      }
      await MediaPlatform.downloadBytes(
        result.bytes,
        'yuanbao_${DateTime.now().millisecondsSinceEpoch}.${result.extension}',
      );
      _message(kIsWeb ? '已加入我的短片，并发起浏览器下载' : '已加入我的短片，并保存到系统相册');
    } catch (e) {
      _message('保存未完成：$e，可再次点击重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _player?.dispose();
    _resultPlayer?.dispose();
    if (_videoUrl != null) MediaPlatform.releaseMediaUrl(_videoUrl!);
    if (_resultUrl != null) MediaPlatform.releaseMediaUrl(_resultUrl!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasInput = _photos.isNotEmpty || _video != null;
    final preview = _resultPlayer;
    return PopScope(
      canPop: !_busy && !_saving,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F0E8),
        appBar: AppBar(
          title: const Text('一键成片'),
          actions: [
            IconButton(
              tooltip: '我的短片',
              onPressed: _busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const ShortVideoLibraryPage(),
                      ),
                    ),
              icon: const Icon(Icons.video_library_outlined),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _busy || _saving,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                '把日常，剪成珍藏',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('照片做相册短片，视频可裁剪。全部在本机处理，无需生成算力。'),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickPhotos,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('选照片'),
                  ),
                  OutlinedButton(
                    onPressed: _albumPhotos,
                    child: const Text('我的相册'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.video_file_outlined),
                    label: const Text('选一段视频'),
                  ),
                ],
              ),
              if (!hasInput)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    '选择1～8张照片或一段视频开始创作。\n照片和视频分开制作，不混用；最长40秒。',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (var i = 0; i < _photos.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Image.memory(
                    _photos[i],
                    width: 48,
                    height: 54,
                    fit: BoxFit.cover,
                    cacheWidth: 100,
                  ),
                  title: Text(
                    '${i + 1}. ${_names[i]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '上移',
                        onPressed: i == 0
                            ? null
                            : () => setState(() {
                                final p = _photos.removeAt(i);
                                final n = _names.removeAt(i);
                                _photos.insert(i - 1, p);
                                _names.insert(i - 1, n);
                                _result = null;
                              }),
                        icon: const Icon(Icons.arrow_upward, size: 20),
                      ),
                      IconButton(
                        tooltip: '移除',
                        onPressed: () => setState(() {
                          _photos.removeAt(i);
                          _names.removeAt(i);
                          _result = null;
                        }),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
              if (_video != null && _player?.value.isInitialized == true) ...[
                _sourcePreview(),
                const SizedBox(height: 8),
                const Text(
                  '点猫咪的位置突出主体；固定构图，不是自动跟踪',
                  style: TextStyle(fontSize: 12),
                ),
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _player!,
                  builder: (context, value, _) {
                    return Column(
                      children: [
                        Slider(
                          min: 0,
                          max: value.duration.inMilliseconds.toDouble(),
                          value: value.position.inMilliseconds.toDouble().clamp(
                            0.0,
                            value.duration.inMilliseconds.toDouble(),
                          ),
                          onChanged: (v) async {
                            await _player!.pause();
                            await _player!.seekTo(
                              Duration(milliseconds: v.round()),
                            );
                          },
                        ),
                        Text(
                          '${(value.position.inMilliseconds / 1000).toStringAsFixed(2)} 秒',
                        ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          children: [
                            IconButton(
                              tooltip: '后退0.03秒',
                              icon: const Icon(Icons.skip_previous),
                              onPressed: () async {
                                await _player!.pause();
                                await _player!.seekTo(
                                  Duration(
                                    milliseconds:
                                        (value.position.inMilliseconds - 33)
                                            .clamp(
                                              0,
                                              value.duration.inMilliseconds,
                                            ),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              tooltip: value.isPlaying ? '暂停' : '播放源视频',
                              icon: Icon(
                                value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              onPressed: () async {
                                if (value.isPlaying) {
                                  await _player!.pause();
                                } else {
                                  await _player!.setPlaybackSpeed(.5);
                                  await _player!.play();
                                }
                              },
                            ),
                            IconButton(
                              tooltip: '前进0.03秒',
                              icon: const Icon(Icons.skip_next),
                              onPressed: () async {
                                await _player!.pause();
                                await _player!.seekTo(
                                  Duration(
                                    milliseconds:
                                        (value.position.inMilliseconds + 33)
                                            .clamp(
                                              0,
                                              value.duration.inMilliseconds,
                                            ),
                                  ),
                                );
                              },
                            ),
                            OutlinedButton(
                              onPressed: () async {
                                await _player!.pause();
                                setState(() {
                                  _cueMs = value.position.inMilliseconds;
                                  _cueLabel = '手动精彩标记';
                                  _momentSlow = true;
                                  _speed = .5;
                                  _result = null;
                                });
                              },
                              child: const Text('标记这一刻'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                FilledButton.tonalIcon(
                  onPressed: _findMoment,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('一键挑选动作片段'),
                ),
                if (_cueMs != null) ...[
                  Text('$_cueLabel · ${(_cueMs! / 1000).toStringAsFixed(2)}秒'),
                  const Text(
                    '眨眼、转头、伸爪可手动标记；动作候选不代表已识别眨眼。',
                    style: TextStyle(fontSize: 12),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('精彩处局部慢放'),
                    value: _momentSlow,
                    onChanged: (v) => setState(() {
                      _momentSlow = v;
                      _result = null;
                    }),
                  ),
                ],
                ExpansionTile(
                  title: const Text('构图与节奏'),
                  children: [
                    SwitchListTile(
                      title: const Text('主体铺满竖屏'),
                      value: _subjectFill,
                      onChanged: (v) => setState(() {
                        _subjectFill = v;
                        _result = null;
                      }),
                    ),
                    if (_subjectFill)
                      Slider(
                        min: 1,
                        max: 2,
                        divisions: 10,
                        value: _zoom,
                        label: '${_zoom.toStringAsFixed(1)}倍',
                        onChanged: (v) => setState(() {
                          _zoom = v;
                          _result = null;
                        }),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final speed in [1.0, .5, .25])
                          ChoiceChip(
                            label: Text('${speed}x'),
                            selected: _speed == speed,
                            onSelected: (_) => setState(() {
                              _speed = speed;
                              _result = null;
                            }),
                          ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        '慢放自动关闭原声，可另加配乐。普通视频慢放不会增加真实细节；优先使用60/120fps素材。',
                      ),
                    ),
                  ],
                ),
                Text(
                  '预计成片 ${(_segments.fold<int>(0, (n, s) => n + s.outputMs) / 1000).toStringAsFixed(1)} 秒',
                ),
                Text(
                  '截取 ${_range.start.toStringAsFixed(1)}～${_range.end.toStringAsFixed(1)} 秒（最多30秒）',
                ),
                RangeSlider(
                  min: 0,
                  max: _player!.value.duration.inMilliseconds / 1000,
                  values: _range,
                  onChanged: (v) {
                    if (v.end - v.start >= 1 && v.end - v.start <= 30) {
                      setState(() {
                        _range = v;
                        _result = null;
                      });
                    }
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('关闭视频原声'),
                  value: _mute,
                  onChanged: (v) => setState(() {
                    _mute = v;
                    _result = null;
                  }),
                ),
              ],
              if (_photos.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('选择模板'),
                Wrap(
                  spacing: 8,
                  children: List.generate(
                    3,
                    (i) => ChoiceChip(
                      label: Text(_templates[i]),
                      selected: _template == i,
                      onSelected: (_) => setState(() {
                        _template = i;
                        _result = null;
                      }),
                    ),
                  ),
                ),
                DropdownButton<int>(
                  value: _seconds,
                  items: [2, 3, 4]
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text('每张 $n 秒 · 共 ${_photos.length * n} 秒'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _seconds = v!;
                    _result = null;
                  }),
                ),
              ],
              TextField(
                controller: _caption,
                maxLength: 60,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '字幕（选填，会写入导出的视频）'),
                onChanged: (_) => setState(() => _result = null),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_music == null ? '配乐（选填）' : _musicName),
                subtitle: const Text('配乐会循环至结尾；选择后替换视频原声'),
                trailing: _music == null
                    ? const Icon(Icons.music_note)
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _music = null;
                          _result = null;
                        }),
                      ),
                onTap: _pickMusic,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              FilledButton.icon(
                onPressed: !hasInput || _busy ? null : _export,
                icon: const Icon(Icons.movie_creation_outlined),
                label: Text(_busy ? _stage : '制作并预览视频'),
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const Text('处理时请保持页面在前台，不要退出。'),
              ],
              if (_result != null) ...[
                const SizedBox(height: 24),
                const Text(
                  '成片预览',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                Text(
                  '${(_result!.durationMs / 1000).toStringAsFixed(1)}秒 · ${(_result!.bytes.length / 1048576).toStringAsFixed(1)}MB · ${_result!.extension.toUpperCase()}',
                ),
                if (preview != null && preview.value.isInitialized) ...[
                  AspectRatio(aspectRatio: 9 / 16, child: VideoPlayer(preview)),
                  TextButton(
                    onPressed: () async {
                      if (preview.value.isPlaying) {
                        await preview.pause();
                      } else {
                        await preview.seekTo(Duration.zero);
                        await preview.play();
                      }
                    },
                    child: const Text('播放 / 暂停成片'),
                  ),
                ] else
                  const Text('浏览器暂不能预览此编码，仍可下载文件检查。'),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.download),
                  label: Text(
                    _saving
                        ? '正在保存…'
                        : kIsWeb
                        ? '下载视频并加入我的短片'
                        : '保存视频到相册',
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await shareMedia(
                        context,
                        _result!.bytes,
                        filename: 'yuanbao_movie.${_result!.extension}',
                        mime: _result!.mimeType,
                      );
                    } catch (e) {
                      _message('分享未完成：$e，可先保存视频后分享');
                    }
                  },
                  icon: const Icon(Icons.share_outlined),
                  label: Text(kIsWeb ? '分享文件（不支持时下载）' : '分享视频'),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
