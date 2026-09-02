import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pet_camera/app/app_back_button.dart';
import 'package:pet_camera/app/app_primary_action_button.dart';
import 'package:pet_camera/app/media_platform.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/short_video_page.dart' show ShortVideoLibraryPage;
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/ai_video_service.dart';
import 'package:pet_camera/data/captured_photos.dart';
import 'package:pet_camera/data/models.dart';
import 'package:pet_camera/data/library_service.dart';
import 'package:pet_camera/data/seed_repository.dart';
import 'package:video_player/video_player.dart';

const _fieldBorderColor = Color(0xFFE2E4E6);

/// 页面阶段：填写素材 -> 生成中 -> 结果预览。
enum _Phase { compose, generating, result }

/// AI 一键成片页：选首帧图 + 场景提示词 -> 万相图生视频 -> 保存到相册「我的创作」。
/// 素材来源：毛孩相册 / 图库导入 / 拍一张。
class AiVideoPage extends ConsumerStatefulWidget {
  const AiVideoPage({super.key});
  @override
  ConsumerState<AiVideoPage> createState() => _AiVideoPageState();
}

class _AiVideoPageState extends ConsumerState<AiVideoPage> {
  _Phase _phase = _Phase.compose;

  // 素材（首帧图）。
  Uint8List? _imageBytes;
  String? _imageError; // 图片未选时的原处提示

  // 提示词。
  final _promptCtrl = TextEditingController();
  final _negativeCtrl = TextEditingController(text: kAiVideoNegativePrompt);
  String? _promptError; // 提示词为空时的原处提示

  // 生成参数。
  double _duration = 8;
  bool _watermark = true;

  // 生成结果与错误。
  AiVideoResult? _result;
  String? _error;

  // 结果预览播放器。
  VideoPlayerController? _player;
  String? _previewUrl;
  bool _playing = false;

  @override
  void dispose() {
    _player?.dispose();
    _promptCtrl.dispose();
    _negativeCtrl.dispose();
    if (_previewUrl != null) MediaPlatform.releaseMediaUrl(_previewUrl!);
    super.dispose();
  }

  // ============ 素材选择 ============

  Future<void> _pickImage() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            _sheetItem(
              icon: MingCuteIcons.album,
              label: '从毛孩相册选',
              onTap: () => Navigator.pop(context, 'album'),
            ),
            _sheetItem(
              icon: MingCuteIcons.addLine,
              label: '从图库导入',
              onTap: () => Navigator.pop(context, 'file'),
            ),
            _sheetItem(
              icon: MingCuteIcons.camera,
              label: '拍一张',
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'album':
        await _pickFromAlbum();
      case 'file':
        await _pickFromFile();
      case 'camera':
        await _pickFromCamera();
    }
  }

  Widget _sheetItem({
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: MingCuteIcon(icon, size: AppUi.iconMedium, color: Colors.black),
      title: Text(
        label,
        style: const TextStyle(fontSize: AppUi.fontBody, color: Colors.black),
      ),
      onTap: onTap,
    );
  }

  /// 相册：毛孩相册（远程种子图）+ 拍摄照片（内存字节）混合网格。
  Future<void> _pickFromAlbum() async {
    final photos = ref
        .read(photosProvider)
        .maybeWhen(data: (p) => p, orElse: () => const <Photo>[]);
    final captured = ref.read(capturedPhotosProvider);
    if (photos.isEmpty && captured.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('相册还是空的，先拍一张吧')));
      }
      return;
    }
    final picked = await showModalBottomSheet<_AlbumPick>(
      context: context,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AlbumPickerSheet(photos: photos, captured: captured),
    );
    if (picked == null) return;
    try {
      if (picked.bytes != null) {
        setState(() {
          _imageBytes = picked.bytes;
          _imageError = null;
        });
      } else if (picked.url != null) {
        final resp = await http.get(Uri.parse(picked.url!));
        if (resp.statusCode != 200) {
          throw Exception('读取图片失败（${resp.statusCode}）');
        }
        setState(() {
          _imageBytes = resp.bodyBytes;
          _imageError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '读取图片失败：$e');
    }
  }

  /// 图库：系统文件选择器。
  Future<void> _pickFromFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final f = res?.files.firstOrNull;
      if (f == null || f.bytes == null) return;
      setState(() {
        _imageBytes = f.bytes;
        _imageError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '导入图片失败：$e');
    }
  }

  /// 拍照：跳相机页，返回后取最新一张拍摄照片。
  Future<void> _pickFromCamera() async {
    await Navigator.pushNamed(context, '/camera');
    final latest = ref.read(capturedPhotosProvider).firstOrNull;
    if (latest != null && mounted) {
      setState(() {
        _imageBytes = latest.bytes;
        _imageError = null;
      });
    }
  }

  // ============ 生成 ============

  Future<void> _generate() async {
    final bytes = _imageBytes;
    final prompt = _promptCtrl.text.trim();
    if (bytes == null) {
      setState(() {
        _imageError = '请先选择一张毛孩照片';
        _promptError = null;
      });
      return;
    }
    if (prompt.isEmpty) {
      setState(() {
        _promptError = '请选择场景或描述画面';
        _imageError = null;
      });
      return;
    }
    setState(() {
      _phase = _Phase.generating;
      _imageError = null;
      _promptError = null;
      _error = null;
    });
    try {
      final result = await ref.read(aiVideoServiceProvider).generate(
        AiVideoRequest(
          imageBytes: bytes,
          prompt: prompt,
          negativePrompt: _negativeCtrl.text.trim(),
          duration: _duration.round(),
          watermark: _watermark,
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.result;
      });
      _initPreview(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.compose;
        _error = e is AiVideoException ? e.message : '生成失败：$e';
      });
    }
  }

  /// 结果页预览：blob URL + video_player。
  Future<void> _initPreview(AiVideoResult result) async {
    _player?.dispose();
    if (_previewUrl != null) MediaPlatform.releaseMediaUrl(_previewUrl!);
    final url = await MediaPlatform.createMediaUrl(
      result.videoBytes,
      'video/mp4',
    );
    if (!mounted) return;
    final c = MediaPlatform.videoController(url);
    await c.initialize();
    if (!mounted) return;
    setState(() {
      _previewUrl = url;
      _player = c;
    });
    c.play();
    setState(() => _playing = true);
  }

  void _togglePlay() {
    final c = _player;
    if (c == null || !c.value.isInitialized) return;
    if (_playing) {
      c.pause();
      setState(() => _playing = false);
    } else {
      c.play();
      setState(() => _playing = true);
    }
  }

  /// 下载视频到用户本地（Web 触发浏览器下载）。
  Future<void> _download() async {
    final result = _result;
    if (result == null) return;
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await MediaPlatform.downloadBytes(
        result.videoBytes,
        'yuanbao_video_$stamp.mp4',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('视频已开始下载')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载失败：$e')));
      }
    }
  }

  /// 保存到相册「我的创作」（整段视频）。
  /// 先上传到 COS 拿到公网 URL，再存入「我的创作」分类。
  Future<void> _saveToAlbum() async {
    final result = _result;
    if (result == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Text('正在上传到云端…'),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      // 步骤 1+2：上传 COS 并登记 works.json（「我的创作」）。
      await ref
          .read(worksProvider.notifier)
          .add(
            bytes: result.videoBytes,
            type: LibraryType.createdVideo,
            ext: 'mp4',
            label: _promptCtrl.text.trim(),
          );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('已上传云端并保存到相册·我的创作'),
          ),
        );
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  void _resetForRegenerate() {
    _player?.dispose();
    if (_previewUrl != null) MediaPlatform.releaseMediaUrl(_previewUrl!);
    setState(() {
      _player = null;
      _previewUrl = null;
      _playing = false;
      _result = null;
      _phase = _Phase.compose;
    });
  }

  // ============ 构建 ============

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
          'AI 一键成片',
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
      bottomNavigationBar: switch (_phase) {
        _Phase.compose => AppPrimaryActionBottomBar(
          label: '开始生成 · 消耗 1 次生成额度',
          onPressed: _generate,
        ),
        _Phase.generating => AppPrimaryActionBottomBar(
          label: '生成中…',
          isLoading: true,
          onPressed: null,
        ),
        _Phase.result => _ResultActionsBar(
          onDownload: _download,
          onSave: _saveToAlbum,
        ),
      },
      body: switch (_phase) {
        _Phase.compose => _buildCompose(t),
        _Phase.generating => _buildGenerating(t),
        _Phase.result => _buildResult(t),
      },
    );
  }

  Widget _buildCompose(AppTokens t) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      children: [
        Text(
          '素材 · 首帧图',
          style: TextStyle(
            fontSize: AppUi.fontHeadline,
            fontWeight: FontWeight.w400,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FA),
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              border: Border.all(
                color: _imageBytes == null ? _fieldBorderColor : Colors.black,
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
                    child: _imageBytes == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MingCuteIcon(
                        MingCuteIcons.camera,
                        size: AppUi.iconLarge,
                        color: t.textSecondary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '选一张毛孩照片',
                        style: TextStyle(
                          fontSize: AppUi.fontCaption,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                  )
                : Image.memory(_imageBytes!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'JPG/PNG ≤20MB · 相册 / 图库 / 拍照',
          style: TextStyle(
            fontSize: AppUi.fontCaption,
            color: t.textSecondary,
          ),
        ),
        if (_imageError != null) ...[
          const SizedBox(height: 6),
          Text(
            _imageError!,
            style: TextStyle(
              fontSize: AppUi.fontCaption,
              color: t.error,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          '选个场景，让毛孩动起来',
          style: TextStyle(
            fontSize: AppUi.fontHeadline,
            height: 28 / AppUi.fontHeadline,
            fontWeight: FontWeight.w400,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: kAiVideoScenes.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 40,
          ),
          itemBuilder: (context, index) {
            final scene = kAiVideoScenes[index];
            final selected = _promptCtrl.text.trim() == scene.prompt;
            return GestureDetector(
              onTap: () => setState(() {
                _promptCtrl.text = scene.prompt;
                _promptError = null;
              }),
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
                    scene.label,
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
        const SizedBox(height: 12),
        TextField(
          controller: _promptCtrl,
          minLines: 2,
          maxLines: 3,
          onChanged: (_) {
            if (_promptError != null) setState(() => _promptError = null);
          },
          style: TextStyle(
            fontSize: AppUi.fontBody,
            height: AppUi.lineHeight(AppUi.fontBody),
            color: t.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: '也可以自己描述动作与氛围',
            hintStyle: TextStyle(
              fontSize: AppUi.fontBody,
              height: AppUi.lineHeight(AppUi.fontBody),
              color: t.textSecondary,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              borderSide: BorderSide(
                color: _promptError != null ? t.error : _fieldBorderColor,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              borderSide: BorderSide(
                color: _promptError != null ? t.error : _fieldBorderColor,
              ),
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
        if (_promptError != null) ...[
          const SizedBox(height: 6),
          Text(
            _promptError!,
            style: TextStyle(fontSize: AppUi.fontCaption, color: t.error),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          '反向提示词',
          style: TextStyle(
            fontSize: AppUi.fontHeadline,
            height: 28 / AppUi.fontHeadline,
            fontWeight: FontWeight.w400,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '不希望在画面中出现的内容，已按宠物优化，可自行修改',
          style: TextStyle(fontSize: AppUi.fontCaption, color: t.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _negativeCtrl,
          minLines: 2,
          maxLines: 3,
          style: TextStyle(
            fontSize: AppUi.fontCaption,
            height: AppUi.lineHeight(AppUi.fontCaption),
            color: t.textPrimary,
          ),
          decoration: InputDecoration(
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
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '时长',
              style: TextStyle(
                fontSize: AppUi.fontHeadline,
                height: 28 / AppUi.fontHeadline,
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            Text(
              '${_duration.round()} 秒（2-15）',
              style: TextStyle(
                fontSize: AppUi.fontBody,
                color: t.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.black,
            inactiveTrackColor: const Color(0xFFE6E6E6),
            thumbColor: Colors.black,
            overlayColor: Colors.transparent,
            trackHeight: 4,
          ),
          child: Slider(
            min: 2,
            max: 15,
            value: _duration,
            divisions: 13,
            label: '${_duration.round()} 秒',
            onChanged: (v) => setState(() => _duration = v),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '清晰度',
              style: TextStyle(
                fontSize: AppUi.fontHeadline,
                height: 28 / AppUi.fontHeadline,
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            Text(
              '720P（默认）',
              style: TextStyle(fontSize: AppUi.fontBody, color: t.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'AI 水印',
              style: TextStyle(
                fontSize: AppUi.fontHeadline,
                height: 28 / AppUi.fontHeadline,
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            Switch(
              value: _watermark,
              activeThumbColor: Colors.black,
              onChanged: (v) => setState(() => _watermark = v),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: t.error, fontSize: AppUi.fontBody),
          ),
        ],
      ],
    );
  }

  Widget _buildGenerating(AppTokens t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                child: Image.memory(
                  _imageBytes!,
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              '正在生成视频，约 1-5 分钟',
              style: TextStyle(
                fontSize: AppUi.fontTitle,
                fontWeight: FontWeight.w500,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI 正在让毛孩动起来，请稍候',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppUi.fontBody,
                color: t.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(AppTokens t) {
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
                          child: Container(
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
                        ),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _result?.demo == true ? '演示视频（未接入真实模型）' : '生成完成',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppUi.fontTitle,
            fontWeight: FontWeight.w500,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _promptCtrl.text.trim(),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppUi.fontBody, color: t.textSecondary),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _resetForRegenerate,
          child: const Text(
            '重新生成',
            style: TextStyle(fontSize: AppUi.fontBody, color: Colors.black),
          ),
        ),
      ],
    );
  }
}

/// 相册选择返回：内存字节 或 远程 URL（二选一）。
class _AlbumPick {
  const _AlbumPick({this.bytes, this.url});
  final Uint8List? bytes;
  final String? url;
}

/// 相册选择底部弹层：拍摄照片在前，毛孩相册在后。
class _AlbumPickerSheet extends StatelessWidget {
  const _AlbumPickerSheet({required this.photos, required this.captured});
  final List<Photo> photos;
  final List<CapturedPhoto> captured;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择照片',
              style: TextStyle(
                fontSize: AppUi.fontTitle,
                fontWeight: FontWeight.w500,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: captured.length + photos.length,
                itemBuilder: (context, index) {
                  if (index < captured.length) {
                    final bytes = captured[index].bytes;
                    return GestureDetector(
                      onTap: () =>
                          Navigator.pop(context, _AlbumPick(bytes: bytes)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      ),
                    );
                  }
                  final photo = photos[index - captured.length];
                  return GestureDetector(
                    onTap: () => Navigator.pop(
                      context,
                      _AlbumPick(url: photo.remoteUrl),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      child: Image.network(photo.remoteUrl, fit: BoxFit.cover),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 结果页底部操作栏：下载 + 保存到相册 两个并排主按钮。
class _ResultActionsBar extends StatelessWidget {
  const _ResultActionsBar({
    required this.onDownload,
    required this.onSave,
  });
  final VoidCallback onDownload;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: onDownload,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.textPrimary,
                    side: const BorderSide(color: Color(0xFFE2E4E6)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MingCuteIcon(
                        MingCuteIcons.download,
                        size: AppUi.iconSmall,
                        color: Colors.black,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '下载',
                        style: TextStyle(
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
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: t.brand,
                    foregroundColor: t.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MingCuteIcon(
                        MingCuteIcons.album,
                        size: AppUi.iconSmall,
                        color: Colors.black,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '保存到相册',
                        style: TextStyle(
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
      ),
    );
  }
}
