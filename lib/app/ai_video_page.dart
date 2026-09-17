import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pet_camera/app/app_back_button.dart';
import 'package:pet_camera/app/app_primary_action_button.dart';
import 'package:pet_camera/app/ai_video_result_page.dart'
    show AiVideoResultActionsBar, AiVideoResultView;
import 'package:pet_camera/app/media_platform.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/short_video_page.dart'
    show ShortVideoLibraryPage;
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/ai_video_service.dart';
import 'package:pet_camera/data/captured_photos.dart';
import 'package:pet_camera/data/models.dart';
import 'package:pet_camera/data/library_service.dart';
import 'package:pet_camera/data/seed_repository.dart';
import 'package:pet_camera/data/task_center.dart';
import 'package:pet_camera/data/task_store.dart';

const _fieldBorderColor = Color(0xFFE2E4E6);

/// 玩法类型：首帧成片 / 参考生视频（影响素材文案等 UI 语义）。
enum _VideoModelKind { i2v, r2v }

/// 页面可选视频模型（对应请求体 model 字段，后端按此动态路由适配器）。
/// 规格表与后端保持一致（见 cloud_functions/ai_portrait/lib/videoAdapter.js
/// 与 models/dashscope-i2v.js、dashscope-r2v.js）：只列可用的具体模型，
/// 时长区间由 [minDuration]/[maxDuration] 驱动 UI，固定时长模型两者相等。
class _VideoModelOption {
  const _VideoModelOption({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.kind,
    this.minDuration = 2,
    this.maxDuration = 15,
  });

  /// 传给 /api/ai-video 的 model 值；'' = 不传，走服务端默认首帧模型。
  final String id;
  final String label;
  final String subtitle;
  final _VideoModelKind kind;

  /// 时长可用区间（秒）；[minDuration] == [maxDuration] 表示该模型时长固定。
  final int minDuration;
  final int maxDuration;

  bool get fixed => minDuration == maxDuration;
}

const List<_VideoModelOption> _kVideoModelOptions = <_VideoModelOption>[
  _VideoModelOption(
    id: 'wanx2.1-i2v-plus',
    label: 'wanx2.1-i2v-plus',
    subtitle: '首帧 · 标准档，720P 固定 5 秒。效果一般，测试用',
    kind: _VideoModelKind.i2v,
    minDuration: 5,
    maxDuration: 5,
  ),
  _VideoModelOption(
    id: 'wanx2.1-i2v-turbo',
    label: 'wanx2.1-i2v-turbo',
    subtitle: '首帧 · 快速档，时长可选 3-5 秒。效果一般，测试用',
    kind: _VideoModelKind.i2v,
    minDuration: 3,
    maxDuration: 5,
  ),
  _VideoModelOption(
    id: 'wan2.2-i2v-flash',
    label: 'wan2.2-i2v-flash',
    subtitle: '首帧 · 低成本档，固定 5 秒',
    kind: _VideoModelKind.i2v,
    minDuration: 5,
    maxDuration: 5,
  ),
  _VideoModelOption(
    id: 'wan2.2-i2v-plus',
    label: 'wan2.2-i2v-plus',
    subtitle: '首帧 · 高质量档，固定 5 秒（无 720P，走 480P/1080P）',
    kind: _VideoModelKind.i2v,
    minDuration: 5,
    maxDuration: 5,
  ),
  _VideoModelOption(
    id: 'wan2.6-r2v',
    label: 'wan2.6-r2v · 参考生视频',
    subtitle: '参考照片只提取毛孩形象特征，场景与动作由提示词决定',
    kind: _VideoModelKind.r2v,
    maxDuration: 10,
  ),
  _VideoModelOption(
    id: 'wan2.6-r2v-flash',
    label: 'wan2.6-r2v-flash · 参考生视频',
    subtitle: '同参考生视频，Flash 档更快更省（默认无声 · 720P）',
    kind: _VideoModelKind.r2v,
    maxDuration: 10,
  ),
];

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

  /// 源图可复用的公网 URL（毛孩相册里的种子图本身在 COS 上）。
  /// 图库导入/拍摄等本地素材为 null，保存封面时需上传副本。
  String? _sourceImageUrl;
  String? _imageError; // 图片未选时的原处提示

  // 提示词。
  final _promptCtrl = TextEditingController();
  final _negativeCtrl = TextEditingController(text: kAiVideoNegativePrompt);
  String? _promptError; // 提示词为空时的原处提示
  bool _optimizing = false; // AI 优化进行中（按钮 loading）

  // 生成参数。
  // 视频模型：'' = 服务端默认（首帧成片）；wan2.6-r2v / wan2.6-r2v-flash = 参考生视频。
  String _modelId = '';
  double _duration = 8;
  bool _watermark = true;

  /// 是否参考生视频玩法：素材语义为「参考照片」。
  bool get _isR2v => _selectedVideoModel.kind == _VideoModelKind.r2v;

  /// 当前选中的模型（含默认项），用于展示说明文案。
  _VideoModelOption get _selectedVideoModel => _kVideoModelOptions.firstWhere(
    (m) => m.id == _modelId,
    orElse: () => _kVideoModelOptions.first,
  );

  // 生成结果与错误。
  AiVideoResult? _result;
  String? _error;
  bool _downloading = false; // 下载中（/api/ai-video/video）
  bool _saving = false; // 保存中（/api/upload）

  @override
  void initState() {
    super.initState();
    // 调试回放入口：URL 带 ?debugTaskId=xxx 时登记该任务（零费用），
    // 既在本页直接回放，也会出现在顶部「当前任务」入口里。
    // 用法：http://<host>:8090/?debugTaskId=<taskId>
    final debugTaskId = Uri.base.queryParameters['debugTaskId']?.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (debugTaskId != null && debugTaskId.isNotEmpty) {
        ref.read(taskCenterProvider.notifier).debugSeed(debugTaskId);
        _debugReplay(debugTaskId);
        return;
      }
      _warnUnfinishedTask();
    });
  }

  /// 本地还有未闭环任务时提醒：继续生成会丢弃它，引导用户先处理。
  void _warnUnfinishedTask() {
    final task = ref.read(taskCenterProvider).task;
    if (task == null || task.stage.finished) return;
    final content = switch (task.stage) {
      TaskStage.generating => '有一个视频正在生成中。现在生成新视频会丢弃它，建议先等它生成完。',
      TaskStage.succeeded => '上次生成的视频还没查看和保存。现在生成新视频会丢弃它，建议先去处理。',
      _ => '上次生成的视频看过但还没保存。现在生成新视频会丢弃它，建议先保存或下载。',
    };
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('有视频任务正在进行'),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '仍要生成',
              style: TextStyle(color: context.tokens.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/ai-video-result');
            },
            style: FilledButton.styleFrom(
              backgroundColor: context.tokens.brand,
              foregroundColor: context.tokens.textPrimary,
            ),
            child: const Text('去处理'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _negativeCtrl.dispose();
    super.dispose();
  }

  // ============ 模型选择 ============

  /// 模型选择：底部弹层（移动端友好），每行展示名称+玩法/时长说明，当前项打勾。
  Future<void> _pickModel() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final s = sheetCtx.tokens;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  '选择模型',
                  style: TextStyle(
                    fontSize: AppUi.fontTitle,
                    fontWeight: FontWeight.w500,
                    color: s.textPrimary,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _kVideoModelOptions.length,
                  itemBuilder: (ctx, index) {
                    final m = _kVideoModelOptions[index];
                    final selected = m.id == _modelId;
                    return ListTile(
                      title: Text(
                        m.label,
                        style: TextStyle(
                          fontSize: AppUi.fontBody,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: s.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        m.subtitle,
                        style: TextStyle(
                          fontSize: AppUi.fontCaption,
                          height: AppUi.lineHeight(AppUi.fontCaption),
                          color: s.textSecondary,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 22,
                              color: Colors.black,
                            )
                          : null,
                      onTap: () => Navigator.pop(ctx, m.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (picked == null || picked == _modelId) return;
    setState(() {
      _modelId = picked;
      // 时长可用区间随模型变化（参考生视频上限 10s、旧档固定 5s 等），
      // 超出时收敛到区间内，避免提交后被服务端钳制。
      final m = _selectedVideoModel;
      _duration = _duration
          .clamp(m.minDuration.toDouble(), m.maxDuration.toDouble())
          .round()
          .toDouble();
    });
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
          _sourceImageUrl = null;
          _imageError = null;
        });
      } else if (picked.url != null) {
        final resp = await http.get(Uri.parse(picked.url!));
        if (resp.statusCode != 200) {
          throw Exception('读取图片失败（${resp.statusCode}）');
        }
        setState(() {
          _imageBytes = resp.bodyBytes;
          // 相册种子图是 COS 公网图，封面直接复用其 URL，避免重复上传占空间。
          _sourceImageUrl = picked.url;
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
        _sourceImageUrl = null;
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
        _sourceImageUrl = null;
        _imageError = null;
      });
    }
  }

  // ============ 生成 ============

  /// AI 优化：把输入框里的简短场景描述扩写为完整图生视频提示词，回填输入框。
  Future<void> _optimizePrompt() async {
    final input = _promptCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _promptError = '先输入一句话场景描述，再点 AI 优化');
      return;
    }
    setState(() {
      _optimizing = true;
      _promptError = null;
    });
    try {
      final optimized = await ref
          .read(aiVideoServiceProvider)
          .optimizePrompt(input);
      if (!mounted) return;
      setState(() {
        _promptCtrl.text = optimized;
        _optimizing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AI 已优化提示词，可点「开始生成」')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _optimizing = false;
        _promptError = e is AiVideoException ? e.message : '优化失败：$e';
      });
    }
  }

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
    final service = ref.read(aiVideoServiceProvider);
    final req = AiVideoRequest(
      imageBytes: bytes,
      prompt: prompt,
      negativePrompt: _negativeCtrl.text.trim(),
      duration: _duration.round(),
      watermark: _watermark,
      model: _modelId.isEmpty ? null : _modelId,
    );
    try {
      // 演示模式（未配置代理）：本地模拟，不产生 taskId，不进任务中心。
      final AiVideoResult result;
      if (AiVideoService.isDemo) {
        result = await service.generateDemo(req);
      } else {
        // 真实模式：提交给任务中心并等待；即便中途退出页面，
        // 轮询也在 App 级继续，结果可从顶部「当前任务」入口找回。
        // 若本地还有未闭环旧任务，中心会先丢弃它（进入页面时已弹窗提示）。
        result = await ref.read(taskCenterProvider.notifier).submitVideo(req);
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.compose;
        _error = e is AiVideoException ? e.message : '生成失败：$e';
      });
    }
  }

  /// 丢弃当前任务并回到表单（底部「丢弃这个视频」）。
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
    _resetForRegenerate();
  }

  /// 取得可用的视频字节：
  /// - 原生端 submitVideo 已预取字节，直接用 result.videoBytes；
  /// - Web 端为流式预览未下载，点「下载/保存」时按需经代理拉取。
  Future<Uint8List> _ensureVideoBytes(AiVideoResult result) async {
    if (result.videoBytes.isNotEmpty) return result.videoBytes;
    if (result.demo) {
      throw const AiVideoException('演示视频不支持保存');
    }
    return ref.read(aiVideoServiceProvider).fetchVideoBytes(result.taskId);
  }

  /// 下载视频到用户本地（Web 触发浏览器下载）。
  Future<void> _download() async {
    final result = _result;
    if (result == null || _downloading || _saving) return;
    setState(() => _downloading = true);
    try {
      final bytes = await _ensureVideoBytes(result);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await MediaPlatform.downloadBytes(bytes, 'yuanbao_video_$stamp.mp4');
      // 已下载 = 任务闭环，顶部「当前任务」入口不再提醒。
      ref.read(taskCenterProvider.notifier).markProcessed();
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
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// 保存到相册「我的创作」（整段视频）。
  /// 先上传到 COS 拿到公网 URL，再存入「我的创作」分类。
  Future<void> _saveToAlbum() async {
    final result = _result;
    if (result == null || _downloading || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Web 端可能尚未下载字节，先按需拉取再上传。
      final bytes = await _ensureVideoBytes(result);
      // 步骤 1+2：上传 COS 并登记 works.json（「我的创作」）。
      await ref
          .read(worksProvider.notifier)
          .add(
            bytes: bytes,
            type: LibraryType.createdVideo,
            ext: 'mp4',
            label: _promptCtrl.text.trim(),
            // 封面：相册种子图直接复用其 COS URL（不重复上传占空间）；
            // 本地/拍摄素材没有公网图，才上传一份源图副本作封面。
            coverUrl: _sourceImageUrl,
            coverBytes: _sourceImageUrl == null ? _imageBytes : null,
          );
      // 已保存到相册 = 任务闭环，顶部「当前任务」入口不再提醒。
      ref.read(taskCenterProvider.notifier).markProcessed();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已上传云端并保存到相册·我的创作')));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 调试回放：用已有 taskId 直接进结果页（零费用，验证播放链路）。
  /// 同时把该 taskId 登记进任务中心，方便验证顶部「当前任务」入口。
  Future<void> _debugReplay(String taskId) async {
    ref.read(taskCenterProvider.notifier).debugSeed(taskId);
    setState(() {
      _phase = _Phase.generating;
      _error = null;
    });
    try {
      final result = await ref.read(aiVideoServiceProvider).replayTask(taskId);
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.compose;
        _error = '回放失败：${e is AiVideoException ? e.message : e}';
      });
    }
  }

  /// 长按页面标题弹出 taskId 输入框（手机上比敲 URL 方便）。
  void _showDebugReplayDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('调试回放（零费用）'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入已成功任务的 taskId'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final id = ctrl.text.trim();
              Navigator.pop(ctx);
              if (id.isNotEmpty) _debugReplay(id);
            },
            child: const Text('回放'),
          ),
        ],
      ),
    );
  }

  void _resetForRegenerate() {
    setState(() {
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
        title: GestureDetector(
          onLongPress: _showDebugReplayDialog,
          child: Text(
            'AI 一键成片',
            style: TextStyle(
              fontSize: AppUi.fontTitle,
              height: AppUi.lineHeight(AppUi.fontTitle),
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
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
        _Phase.result => AiVideoResultActionsBar(
          onDownload: _download,
          onSave: _saveToAlbum,
          onDiscard: _confirmDiscard,
          downloading: _downloading,
          saving: _saving,
        ),
      },
      body: switch (_phase) {
        _Phase.compose => _buildCompose(t),
        _Phase.generating => _buildGenerating(t),
        _Phase.result => AiVideoResultView(
          result: _result!,
          prompt: _promptCtrl.text.trim(),
          onDownload: _download,
          onSave: _saveToAlbum,
          onDiscard: _confirmDiscard,
          onRegenerate: _resetForRegenerate,
          onViewed: () => ref.read(taskCenterProvider.notifier).markViewed(),
        ),
      },
    );
  }

  /// 「AI 优化」按钮：黑色胶囊 + sparkles 图标，优化中显示 loading。
  Widget _buildOptimizeButton(AppTokens t) {
    return GestureDetector(
      onTap: _optimizing ? null : _optimizePrompt,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _optimizing ? const Color(0xFFF6F8FA) : Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_optimizing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            else
              const MingCuteIcon(
                MingCuteIcons.sparkles,
                size: AppUi.iconSmall,
                color: Colors.white,
              ),
            const SizedBox(width: 6),
            Text(
              _optimizing ? '优化中…' : 'AI 优化',
              style: TextStyle(
                fontSize: AppUi.fontCaption,
                height: 20 / AppUi.fontCaption,
                fontWeight: FontWeight.w500,
                color: _optimizing ? t.textSecondary : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompose(AppTokens t) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      children: [
        Text(
          '模型',
          style: TextStyle(
            fontSize: AppUi.fontTitle,
            fontWeight: FontWeight.w400,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '点选切换模型，不同模型效果与计费不同',
          style: TextStyle(fontSize: AppUi.fontCaption, color: t.textSecondary),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickModel,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FA),
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              border: Border.all(color: _fieldBorderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedVideoModel.label,
                        style: TextStyle(
                          fontSize: AppUi.fontBody,
                          fontWeight: FontWeight.w500,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedVideoModel.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppUi.fontCaption,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_drop_down,
                  size: 24,
                  color: Colors.black,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _isR2v ? '素材 · 参考照片' : '素材 · 首帧图',
          style: TextStyle(
            fontSize: AppUi.fontTitle,
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
          _isR2v
              ? 'JPG/PNG ≤20MB · 相册 / 图库 / 拍照 —— 只提取毛孩形象特征'
              : 'JPG/PNG ≤20MB · 相册 / 图库 / 拍照',
          style: TextStyle(fontSize: AppUi.fontCaption, color: t.textSecondary),
        ),
        if (_imageError != null) ...[
          const SizedBox(height: 6),
          Text(
            _imageError!,
            style: TextStyle(fontSize: AppUi.fontCaption, color: t.error),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '选个场景，让毛孩动起来',
              style: TextStyle(
                fontSize: AppUi.fontTitle,
                height: 28 / AppUi.fontHeadline,
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            _buildOptimizeButton(t),
          ],
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
            hintText: '输入一句话场景，点「AI 优化」自动扩写',
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
            fontSize: AppUi.fontTitle,
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
                fontSize: AppUi.fontTitle,
                height: 28 / AppUi.fontHeadline,
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            Text(
              _selectedVideoModel.fixed
                  ? '固定 ${_selectedVideoModel.maxDuration} 秒'
                  : '${_duration.round()} 秒'
                        '（${_selectedVideoModel.minDuration}-'
                        '${_selectedVideoModel.maxDuration}）',
              style: TextStyle(fontSize: AppUi.fontBody, color: t.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selectedVideoModel.fixed)
          const SizedBox(height: 16)
        else
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.black,
              inactiveTrackColor: const Color(0xFFE6E6E6),
              thumbColor: Colors.black,
              overlayColor: Colors.transparent,
              trackHeight: 4,
            ),
            child: Slider(
              min: _selectedVideoModel.minDuration.toDouble(),
              max: _selectedVideoModel.maxDuration.toDouble(),
              value: _duration,
              divisions:
                  _selectedVideoModel.maxDuration -
                  _selectedVideoModel.minDuration,
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
                fontSize: AppUi.fontTitle,
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
                fontSize: AppUi.fontTitle,
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
