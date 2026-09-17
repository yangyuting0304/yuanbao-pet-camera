import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_camera/app/app_back_button.dart';
import 'package:pet_camera/app/media_platform.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/ai_video_service.dart';
import 'package:pet_camera/data/library_service.dart';
import 'package:pet_camera/data/task_center.dart';
import 'package:pet_camera/data/task_store.dart';
import 'package:video_player/video_player.dart';

/// AI 成片结果区：播放器 + 文案 + 重新生成。
///
/// 「一键成片」页的结果阶段与独立结果页（顶部任务入口进入）共用同一份实现，
/// 保证两条入口的观感与能力完全一致。
class AiVideoResultView extends StatefulWidget {
  const AiVideoResultView({
    super.key,
    required this.result,
    required this.prompt,
    required this.onDownload,
    required this.onSave,
    required this.onDiscard,
    this.onRegenerate,
    this.onViewed,
  });

  final AiVideoResult result;
  final String prompt;
  final VoidCallback onDownload;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  /// 重新生成（「一键成片」页才有；独立结果页留空）。
  final VoidCallback? onRegenerate;

  /// 播放器就绪（用户真正看到画面）时回调一次，用于把任务标记为「已查看」。
  final VoidCallback? onViewed;

  @override
  State<AiVideoResultView> createState() => _AiVideoResultViewState();
}

class _AiVideoResultViewState extends State<AiVideoResultView> {
  VideoPlayerController? _player;
  String? _previewUrl;
  bool _playing = false;
  bool _muted = false; // 是否静音（浏览器自动播放策略：仅 muted 可无手势自动播）
  bool _previewBusy = false; // 正在初始化播放器（防止重复进入）
  String? _playerError; // 播放器初始化失败时的提示（不再无限转圈）
  bool _viewedNotified = false;
  final List<String> _diag = <String>[]; // 播放链路诊断日志（真机可视化）

  /// 播放器初始化超时：超时视为失败，Web 端会回退到远程直链重试。
  static const Duration _previewInitTimeout = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _initPreview(widget.result);
  }

  @override
  void didUpdateWidget(covariant AiVideoResultView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.taskId != widget.result.taskId) {
      _initPreview(widget.result);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    if (_previewUrl != null) MediaPlatform.releaseMediaUrl(_previewUrl!);
    super.dispose();
  }

  /// 结果页预览：
  /// - Web（电脑/手机浏览器）：优先直接播放远程直链（OSS mp4，支持 Range，
  ///   <video> 跨域播放无需 CORS，也不需要把整包塞进 blob —— 手机上最稳）。
  ///   远程不可用时回退本地字节 blob。
  /// - 原生端：仍走本地临时文件（无 CORS 概念，file 源最稳）。
  /// 初始化失败或超时（移动端自动播放策略拦截等），给出明确错误与「重新加载」，
  /// 避免无限转圈。
  Future<void> _initPreview(AiVideoResult result) async {
    if (_previewBusy) return;
    // 清理上一个播放器与引用。
    final old = _player;
    _player = null;
    _previewBusy = true;
    _playerError = null;
    _diag
      ..clear()
      ..add('[${_now()}] 开始初始化预览 · taskId=${result.taskId}');
    try {
      old?.dispose();
    } catch (_) {}
    if (_previewUrl != null) {
      await MediaPlatform.releaseMediaUrl(_previewUrl!);
      _previewUrl = null;
    }
    if (!mounted) {
      _previewBusy = false;
      return;
    }
    setState(() {});

    VideoPlayerController? c;

    if (kIsWeb) {
      // 1) Web：优先后端代理流（faststart + Range，手机上秒开）；代理不可用
      //    时退 OSS 直链（<video> 跨域播放本身不需要 CORS）。
      final candidates = <String>[
        if (result.streamUrl != null && result.streamUrl!.trim().isNotEmpty)
          result.streamUrl!.trim(),
        if (result.sourceUrl != null && result.sourceUrl!.trim().isNotEmpty)
          result.sourceUrl!.trim(),
      ];
      _diagAdd('候选地址 ${candidates.length} 个');
      for (var i = 0; i < candidates.length; i++) {
        final u = candidates[i];
        _diagAdd('尝试 #${i + 1}: ${_short(u)}');
        final sw = Stopwatch()..start();
        c = await _tryInitialize(
          VideoPlayerController.networkUrl(Uri.parse(u)),
          label: '#${i + 1}',
        );
        sw.stop();
        if (c != null) {
          _diagAdd('尝试 #${i + 1}: ✔ 成功 ${_fmtMs(sw.elapsedMilliseconds)}');
          break;
        } else {
          _diagAdd('尝试 #${i + 1}: ✖ 失败/超时 ${_fmtMs(sw.elapsedMilliseconds)}');
        }
      }
    }

    // 2) 回退：本地字节源（Web: blob URL；原生: 临时文件）。
    if (c == null && result.videoBytes.isNotEmpty) {
      final url = await MediaPlatform.createMediaUrl(
        result.videoBytes,
        'video/mp4',
      );
      c = await _tryInitialize(MediaPlatform.videoController(url));
      if (!mounted) {
        c?.dispose();
        await MediaPlatform.releaseMediaUrl(url);
        _previewBusy = false;
        return;
      }
      if (c != null) {
        _previewUrl = url; // 仅本地源需要释放
      } else {
        await MediaPlatform.releaseMediaUrl(url);
      }
    }

    if (!mounted) {
      c?.dispose();
      _previewBusy = false;
      return;
    }
    if (c == null) {
      setState(() {
        _previewBusy = false;
        _playerError = '视频加载失败，可点击「重新加载」重试，或直接下载 / 保存到相册';
      });
      return;
    }
    final player = c; // 流分析已排除 null，提为不可空引用
    player.addListener(_syncPlaying);
    setState(() {
      _player = player;
      _previewBusy = false;
      _playing = player.value.isPlaying;
    });
    if (!_viewedNotified) {
      _viewedNotified = true;
      widget.onViewed?.call();
    }
    // 自动播放策略分平台：
    // - Web：移动浏览器禁止无手势自动播（"play() can only be initiated by a
    //   user gesture"），观感像卡死 —— 不自动播，显示「点击播放」按钮。
    // - 原生（Android/iOS App）：无浏览器策略限制，保持自动播放（体验不变）。
    if (!kIsWeb) {
      try {
        await player.play();
      } catch (_) {}
    } else {
      _diagAdd('视频已就绪，点击画面播放');
    }
    if (mounted) setState(() => _playing = player.value.isPlaying);
  }

  /// 初始化播放器，失败或超时返回 null（异常内部消化，不外抛；原因进诊断日志）。
  Future<VideoPlayerController?> _tryInitialize(
    VideoPlayerController c, {
    String label = '',
  }) async {
    try {
      await c.initialize().timeout(_previewInitTimeout);
      return c;
    } catch (e) {
      _diagAdd('$label 初始化异常: $e');
      try {
        await c.dispose();
      } catch (_) {}
      return null;
    }
  }

  /// 跟随播放器真实状态，避免自动播放被拦截后仍显示「暂停」导致看起来卡死。
  void _syncPlaying() {
    final c = _player;
    if (c == null || !mounted) return;
    final err = c.value.errorDescription;
    if (err != null && err.isNotEmpty) {
      _diagAdd('播放器错误: $err');
    }
    if (c.value.isPlaying != _playing) {
      setState(() => _playing = c.value.isPlaying);
    }
  }

  void _diagAdd(String line) {
    _diag.add('[${_now()}] $line');
    if (_diag.length > 30) _diag.removeRange(0, _diag.length - 30);
    if (mounted) setState(() {});
  }

  static String _now() {
    final t = DateTime.now();
    return '${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';
  }

  static String _fmtMs(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';

  static String _short(String url) {
    if (url.length <= 64) return url;
    return '${url.substring(0, 56)}…${url.substring(url.length - 8)}';
  }

  void _retryLoad() => _initPreview(widget.result);

  Future<void> _togglePlay() async {
    final c = _player;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      try {
        await c.play();
      } catch (_) {}
    }
    if (mounted) setState(() => _playing = c.value.isPlaying);
  }

  /// 切换静音（按钮点击 = 用户手势，取消静音必成功）。
  Future<void> _toggleMuted() async {
    final next = !_muted;
    await MediaPlatform.setVideosMuted(!next); // next=false 表示取消静音
    if (mounted) setState(() => _muted = next);
  }

  /// 预览未就绪时的黑框内容：失败给出明确提示+重新加载；否则转圈。
  Widget _buildPreviewLoading() {
    final err = _playerError;
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MingCuteIcon(
                MingCuteIcons.warning,
                size: AppUi.iconLarge,
                color: Colors.white70,
              ),
              const SizedBox(height: 8),
              Text(
                err,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppUi.fontCaption,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _retryLoad,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white24,
                ),
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_diag.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _diag.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Color(0xFF7EE787),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = _player;
    final ready = c != null && c.value.isInitialized;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      children: [
        AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
            ),
            clipBehavior: Clip.antiAlias,
            child: ready
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(child: VideoPlayer(c)),
                      Center(
                        child: GestureDetector(
                          onTap: _togglePlay,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
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
                              if (!_playing) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  '点击播放',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // 静音切换（右下角，仅 Web）：浏览器自动播放策略只允许
                      // muted 自动播，点这里恢复/关闭声音（点击是手势，必成功）。
                      // 原生端无此限制（setVideosMuted 为空实现），不显示。
                      if (kIsWeb)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: GestureDetector(
                            onTap: _toggleMuted,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _muted
                                    ? Icons.volume_off
                                    : Icons.volume_up,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : _buildPreviewLoading(),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.result.demo ? '演示视频（未接入真实模型）' : '生成完成',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppUi.fontTitle,
            fontWeight: FontWeight.w500,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.prompt,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppUi.fontBody, color: t.textSecondary),
        ),
        if (widget.onRegenerate != null) ...[
          const SizedBox(height: 16),
          TextButton(
            onPressed: widget.onRegenerate,
            child: const Text(
              '重新生成',
              style: TextStyle(fontSize: AppUi.fontBody, color: Colors.black),
            ),
          ),
        ],
      ],
    );
  }
}

/// 结果页底部操作栏：主按钮「保存到相册」、次级「下载」、三级「丢弃」。
/// 「一键成片」页与独立结果页共用，保证操作一致。
///
/// 下载 / 上传耗时较长（请求约 20s），进行中在按钮上显示转圈并禁用，
/// 避免重复点击；两个动作互斥，期间「丢弃」也不可点。
class AiVideoResultActionsBar extends StatelessWidget {
  const AiVideoResultActionsBar({
    super.key,
    required this.onDownload,
    required this.onSave,
    required this.onDiscard,
    this.downloading = false,
    this.saving = false,
  });

  final VoidCallback onDownload;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  /// 下载中（/api/ai-video/video 拉字节或浏览器下载）。
  final bool downloading;

  /// 保存/上传中（/api/upload 上传 COS）。
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final busy = downloading || saving;
    return Container(
      color: t.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: busy ? null : onDownload,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: t.textPrimary,
                        side: const BorderSide(color: Color(0xFFE2E4E6)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (downloading)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          else
                            const MingCuteIcon(
                              MingCuteIcons.download,
                              size: AppUi.iconSmall,
                              color: Colors.black,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            downloading ? '下载中…' : '下载',
                            style: const TextStyle(
                              fontSize: AppUi.fontTitle,
                              fontWeight: FontWeight.w400,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: busy ? null : onSave,
                      style: FilledButton.styleFrom(
                        backgroundColor: t.brand,
                        foregroundColor: t.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (saving)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          else
                            const MingCuteIcon(
                              MingCuteIcons.album,
                              size: AppUi.iconSmall,
                              color: Colors.black,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            saving ? '上传中…' : '保存到相册',
                            style: const TextStyle(
                              fontSize: AppUi.fontTitle,
                              fontWeight: FontWeight.w400,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // 三级操作：丢弃当前任务（任务结束，顶部入口不再提醒）。
            TextButton(
              onPressed: busy ? null : onDiscard,
              child: Text(
                '丢弃这个视频',
                style: TextStyle(
                  fontSize: AppUi.fontCaption,
                  color: busy ? t.textTertiary : t.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 独立结果页：由顶部导航栏的「当前任务」入口进入，带着本地缓存的 taskId，
/// 直接复用 [AiVideoResultView] 展示结果。
class AiVideoResultPage extends ConsumerStatefulWidget {
  const AiVideoResultPage({super.key});

  @override
  ConsumerState<AiVideoResultPage> createState() => _AiVideoResultPageState();
}

enum _PageStatus { loading, generating, ready, error }

class _AiVideoResultPageState extends ConsumerState<AiVideoResultPage> {
  _PageStatus _status = _PageStatus.loading;
  AiVideoResult? _result;
  String? _error;
  bool _downloading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final task = ref.read(taskCenterProvider).task;
    if (task == null) {
      if (!mounted) return;
      setState(() {
        _status = _PageStatus.error;
        _error = '没有正在处理的任务';
      });
      return;
    }
    if (task.stage == TaskStage.generating) {
      // 若自动轮询已超限停止（超过约 10 分钟），进来时自动续一次命，
      // 用户无需手动点「继续查询」也能接着等结果。
      if (!ref.read(taskCenterProvider).polling) {
        ref.read(taskCenterProvider.notifier).resume();
      }
      if (!mounted) return;
      setState(() {
        _status = _PageStatus.generating;
        _error = null;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _status = _PageStatus.loading;
      _error = null;
    });
    try {
      final result = await ref.read(taskCenterProvider.notifier).loadResult();
      if (!mounted) return;
      setState(() {
        _result = result;
        _status = _PageStatus.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _PageStatus.error;
        _error = e is AiVideoException ? e.message : '加载失败：$e';
      });
    }
  }

  /// 取得可用的视频字节：优先用内存里的，没有再按需经代理拉取。
  Future<Uint8List> _ensureVideoBytes(AiVideoResult result) async {
    if (result.videoBytes.isNotEmpty) return result.videoBytes;
    return ref.read(aiVideoServiceProvider).fetchVideoBytes(result.taskId);
  }

  Future<void> _download() async {
    final result = _result;
    if (result == null || _downloading || _saving) return;
    setState(() => _downloading = true);
    try {
      final bytes = await _ensureVideoBytes(result);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await MediaPlatform.downloadBytes(bytes, 'yuanbao_video_$stamp.mp4');
      ref.read(taskCenterProvider.notifier).markProcessed();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('视频已开始下载')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('下载失败：$e')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// 保存到相册「我的创作」（整段视频）：上传 COS 后登记 works.json。
  Future<void> _saveToAlbum() async {
    final result = _result;
    if (result == null || _downloading || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _ensureVideoBytes(result);
      final prompt = ref.read(taskCenterProvider).task?.prompt ?? '';
      await ref
          .read(worksProvider.notifier)
          .add(
            bytes: bytes,
            type: LibraryType.createdVideo,
            ext: 'mp4',
            label: prompt,
          );
      ref.read(taskCenterProvider.notifier).markProcessed();
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('已上传云端并保存到相册·我的创作')),
        );
    } catch (e) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 丢弃：二次确认后结束任务，顶部入口不再提醒。
  Future<void> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('丢弃这个视频？'),
        content: const Text('丢弃后本次生成结果将不再保留，需要重新生成（会再次消耗额度）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('丢弃'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(taskCenterProvider.notifier).discard();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已丢弃该视频')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final center = ref.watch(taskCenterProvider);
    // 任务从「生成中」推进到终态时，自动重新拉一次结果。
    ref.listen(taskCenterProvider, (prev, next) {
      final wasGenerating = prev?.task?.stage == TaskStage.generating;
      if (wasGenerating && next.task?.stage != TaskStage.generating) _load();
    });

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 44,
        leading: AppBackButton(onTap: () => Navigator.pop(context)),
        centerTitle: true,
        title: Text(
          '当前视频任务',
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
      bottomNavigationBar: _status == _PageStatus.ready
          ? AiVideoResultActionsBar(
              onDownload: _download,
              onSave: _saveToAlbum,
              onDiscard: _confirmDiscard,
              downloading: _downloading,
              saving: _saving,
            )
          : null,
      body: switch (_status) {
        _PageStatus.ready => AiVideoResultView(
          result: _result!,
          prompt: center.task?.prompt ?? '',
          onDownload: _download,
          onSave: _saveToAlbum,
          onDiscard: _confirmDiscard,
          onViewed: () => ref.read(taskCenterProvider.notifier).markViewed(),
        ),
        _PageStatus.generating => _buildGenerating(t, center),
        _PageStatus.loading => const Center(child: CircularProgressIndicator()),
        _PageStatus.error => _buildError(t),
      },
    );
  }

  Widget _buildGenerating(AppTokens t, TaskCenterState center) {
    final hint = center.error ?? center.task?.errorMessage;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              center.polling ? '正在生成视频，约 1-5 分钟' : '生成时间比预期长',
              style: TextStyle(
                fontSize: AppUi.fontTitle,
                fontWeight: FontWeight.w500,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              center.polling
                  ? 'AI 正在让毛孩动起来，可以先去逛逛，好了会提醒你'
                  : '任务仍在服务端排队，可以点下方按钮继续查询',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppUi.fontBody, color: t.textSecondary),
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppUi.fontCaption, color: t.error),
              ),
            ],
            if (!center.polling) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.read(taskCenterProvider.notifier).resume(),
                child: const Text('继续查询'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildError(AppTokens t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MingCuteIcon(
              MingCuteIcons.warning,
              size: AppUi.iconLarge,
              color: t.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? '加载失败',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppUi.fontBody, color: t.textPrimary),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
