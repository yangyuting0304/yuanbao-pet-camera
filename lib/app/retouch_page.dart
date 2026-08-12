import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:pet_camera/app/retouch_data.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/captured_photos.dart';
import 'package:pet_camera/data/firered_service.dart';
import 'package:pet_camera/data/models.dart';
import 'package:pet_camera/data/seed_repository.dart';

/// 选图源（拍摄图用 MemoryImage，种子图用 AssetImage）。
class _Source {
  const _Source(this.image, this.caption, {this.assetPath, this.bytes});
  final ImageProvider image;
  final String caption;
  final String? assetPath;
  final Uint8List? bytes;

  /// 解析为字节流（拍摄图直接用 bytes，种子图经 rootBundle 加载）。
  Future<Uint8List> resolveBytes() async {
    if (bytes != null) return bytes!;
    final data = await rootBundle.load(assetPath!);
    return data.buffer.asUint8List();
  }
}

/// 宠物 P 图编辑器：选图 + 滤镜 + 贴纸 + 背景 + 形状，一键存相册。
/// Web 端用 RepaintBoundary.toImage 导出 PNG（含滤镜与贴纸），无需原生依赖。
class RetouchPage extends ConsumerStatefulWidget {
  const RetouchPage({super.key});
  @override
  ConsumerState<RetouchPage> createState() => _RetouchPageState();
}

class _RetouchPageState extends ConsumerState<RetouchPage> {
  ImageProvider? _selected;
  int _filterIndex = 0;
  int _bgIndex = 0;
  int _shapeIndex = 0; // 0 圆角 1 圆形 2 方形
  int _activeTab = 0; // 0 滤镜 1 贴纸 2 背景 3 形状 4 AI 编辑
  final List<Sticker> _stickers = [];
  final _boundaryKey = GlobalKey();
  bool _saving = false;

  // AI 创意编辑（FireRed）状态
  String _aiPrompt = kFireRedPresets.first.$2;
  Uint8List? _aiResultBytes;
  bool _aiLoading = false;
  bool _aiDemo = false;
  String? _aiError;

  List<_Source> _buildSources(List<Photo> seed, List<CapturedPhoto> captured) {
    final list = <_Source>[];
    for (final c in captured) list.add(_Source(MemoryImage(c.bytes), '拍摄', bytes: c.bytes));
    for (final p in seed) list.add(_Source(AssetImage(p.assetPath), p.petId, assetPath: p.assetPath));
    return list;
  }

  Widget _shapeClip({required Widget child}) {
    switch (_shapeIndex) {
      case 1:
        return ClipOval(child: child);
      case 2:
        return ClipRRect(borderRadius: BorderRadius.circular(4), child: child);
      default:
        return ClipRRect(borderRadius: BorderRadius.circular(24), child: child);
    }
  }

  Future<void> _save(ImageProvider selected) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2);
      final bd = await img.toByteData(format: ImageByteFormat.png);
      if (bd != null) {
        ref.read(capturedPhotosProvider.notifier).add(bd.buffer.asUint8List());
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已存入相册')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final photosAsync = ref.watch(photosProvider);
    final captured = ref.watch(capturedPhotosProvider);
    final canvas = (MediaQuery.of(context).size.width - 40).clamp(240.0, 360.0);

    return Scaffold(
      backgroundColor: t.bgBase,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(LucideIcons.chevronLeft), onPressed: () => Navigator.pop(context)),
        title: const Text('宠物 P 图', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: t.surface,
        foregroundColor: t.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _saving ? null : () => _save(_selected ?? const AssetImage('assets/seed/photos/yuanbao_headshot.png')),
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(LucideIcons.download),
            tooltip: '保存到相册',
          ),
        ],
      ),
      body: photosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('照片加载失败')),
        data: (photos) {
          final sources = _buildSources(photos, captured);
          final selected = _selected ?? sources.first.image;
          final selectedSource = sources.firstWhere((s) => s.image == selected, orElse: () => sources.first);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _SourceBar(sources: sources, selected: selected, onSelect: (img) => setState(() => _selected = img)),
                const SizedBox(height: 18),
                RepaintBoundary(
                  key: _boundaryKey,
                  child: Container(
                    width: canvas,
                    height: canvas,
                    color: _bgIndex == 0 ? Colors.white : kBgs[_bgIndex].color,
                    child: Stack(
                      children: [
                        Center(
                          child: _shapeClip(
                            child: ColorFiltered(
                              colorFilter: ColorFilter.matrix(kFilters[_filterIndex].matrix),
                              child: Image(image: selected, fit: BoxFit.cover, width: canvas, height: canvas),
                            ),
                          ),
                        ),
                        for (final s in _stickers)
                          Positioned(
                            left: s.x,
                            top: s.y,
                            child: GestureDetector(
                              onPanUpdate: (d) => setState(() {
                                s.x += d.delta.dx;
                                s.y += d.delta.dy;
                              }),
                              onLongPress: () => setState(() => _stickers.remove(s)),
                              child: Icon(s.icon, size: s.size, color: s.color),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text('贴纸可拖动，长按删除', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 16),
                _ToolTabs(active: _activeTab, onTap: (i) => setState(() => _activeTab = i)),
                const SizedBox(height: 14),
                _panel(t, canvas, selectedSource),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _panel(AppTokens t, double canvas, _Source selectedSource) {
    switch (_activeTab) {
      case 0:
        return _FilterPanel(active: _filterIndex, onSelect: (i) => setState(() => _filterIndex = i));
      case 1:
        return _StickerPanel(
          onAdd: (icon, color) => setState(() => _stickers.add(Sticker(icon, canvas / 2 - 24, canvas / 2 - 24, 48, color))),
          onClear: () => setState(() => _stickers.clear()),
        );
      case 2:
        return _BgPanel(active: _bgIndex, onSelect: (i) => setState(() => _bgIndex = i));
      case 3:
        return _ShapePanel(active: _shapeIndex, onSelect: (i) => setState(() => _shapeIndex = i));
      default:
        return _AiEditPanel(
          source: selectedSource,
          prompt: _aiPrompt,
          onPromptChanged: (v) => setState(() => _aiPrompt = v),
          onGenerate: _generateAi,
          loading: _aiLoading,
          resultBytes: _aiResultBytes,
          demo: _aiDemo,
          error: _aiError,
          onSave: _saveAiResult,
        );
    }
  }

  /// 调 FireRed 代理做图像编辑（图生图）。
  Future<void> _generateAi(String prompt) async {
    if (_aiLoading) return;
    final sources = _buildSources(
      ref.read(photosProvider).value ?? <Photo>[],
      ref.read(capturedPhotosProvider),
    );
    final sel = _selected ?? sources.first.image;
    final src = sources.firstWhere((s) => s.image == sel, orElse: () => sources.first);
    setState(() {
      _aiLoading = true;
      _aiError = null;
      _aiResultBytes = null;
      _aiDemo = false;
    });
    try {
      final bytes = await src.resolveBytes();
      final res = await ref.read(fireRedServiceProvider).edit(sourceBytes: bytes, prompt: prompt);
      if (mounted) setState(() {
        _aiResultBytes = res.imageBytes;
        _aiDemo = res.demo;
      });
    } on FireRedException catch (e) {
      if (mounted) setState(() => _aiError = e.message);
    } catch (e) {
      if (mounted) setState(() => _aiError = '生成出错：$e');
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  /// 把 AI 编辑结果存入相册。
  Future<void> _saveAiResult() async {
    if (_aiResultBytes == null || _saving) return;
    setState(() => _saving = true);
    try {
      ref.read(capturedPhotosProvider.notifier).add(_aiResultBytes!);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已存入相册')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// 选图缩略图栏
class _SourceBar extends StatelessWidget {
  const _SourceBar({required this.sources, required this.selected, required this.onSelect});
  final List<_Source> sources;
  final ImageProvider selected;
  final ValueChanged<ImageProvider> onSelect;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sources.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (c, i) {
          final s = sources[i];
          final isSel = s.image == selected;
          return GestureDetector(
            onTap: () => onSelect(s.image),
            child: Container(
              width: 72,
              decoration: BoxDecoration(
                border: Border.all(color: isSel ? t.brand : Colors.transparent, width: 3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image(image: s.image, fit: BoxFit.cover),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 底部工具 Tab
class _ToolTabs extends StatelessWidget {
  const _ToolTabs({required this.active, required this.onTap});
  final int active;
  final ValueChanged<int> onTap;
  static const _tabs = [
    (LucideIcons.wand2, '滤镜'),
    (LucideIcons.sticker, '贴纸'),
    (LucideIcons.palette, '背景'),
    (LucideIcons.square, '形状'),
    (LucideIcons.sparkles, 'AI 编辑'),
  ];
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(_tabs.length, (i) {
        final (icon, label) = _tabs[i];
        final on = i == active;
        return GestureDetector(
          onTap: () => onTap(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: on ? t.brand : t.surface, borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: on ? Colors.white : t.textSecondary),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : t.textSecondary)),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// 滤镜面板
class _FilterPanel extends StatelessWidget {
  const _FilterPanel({required this.active, required this.onSelect});
  final int active;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(kFilters.length, (i) {
        final f = kFilters[i];
        final on = i == active;
        return GestureDetector(
          onTap: () => onSelect(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: on ? t.brand : t.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: on ? t.brand : t.brandSoft, width: 1),
            ),
            child: Text(f.name, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : t.textPrimary)),
          ),
        );
      }),
    );
  }
}

/// 贴纸面板（添加 + 清空）
class _StickerPanel extends StatelessWidget {
  const _StickerPanel({required this.onAdd, required this.onClear});
  final void Function(IconData, Color) onAdd;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (icon, color) in kStickerIcons)
          GestureDetector(
            onTap: () => onAdd(icon, color),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Icon(icon, size: 24, color: color),
            ),
          ),
        GestureDetector(
          onTap: onClear,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Icon(LucideIcons.undo2, size: 20, color: context.tokens.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// 背景面板
class _BgPanel extends StatelessWidget {
  const _BgPanel({required this.active, required this.onSelect});
  final int active;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(kBgs.length, (i) {
        final b = kBgs[i];
        final on = i == active;
        return GestureDetector(
          onTap: () => onSelect(i),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: b.color ?? Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? t.brand : Colors.black.withValues(alpha: 0.1), width: on ? 3 : 1),
            ),
            child: b.color == null ? Icon(LucideIcons.ban, size: 18, color: t.textSecondary) : null,
          ),
        );
      }),
    );
  }
}

/// 形状面板
class _ShapePanel extends StatelessWidget {
  const _ShapePanel({required this.active, required this.onSelect});
  final int active;
  final ValueChanged<int> onSelect;
  static const _shapes = [
    (LucideIcons.squareRoundCorner, '圆角'),
    (LucideIcons.circle, '圆形'),
    (LucideIcons.square, '方形'),
  ];
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_shapes.length, (i) {
        final (icon, label) = _shapes[i];
        final on = i == active;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: on ? t.brand : t.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: on ? t.brand : t.brandSoft, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: on ? Colors.white : t.textSecondary),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : t.textPrimary)),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// AI 创意编辑面板（FireRed-Image-Edit）：选图 + 快捷 prompt + 自定义 + 生成 + 结果九宫格。
class _AiEditPanel extends StatelessWidget {
  const _AiEditPanel({
    required this.source,
    required this.prompt,
    required this.onPromptChanged,
    required this.onGenerate,
    required this.loading,
    required this.resultBytes,
    required this.demo,
    required this.error,
    required this.onSave,
  });
  final _Source source;
  final String prompt;
  final ValueChanged<String> onPromptChanged;
  final ValueChanged<String> onGenerate;
  final bool loading;
  final Uint8List? resultBytes;
  final bool demo;
  final String? error;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI 创意编辑', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2D2D2D))),
        const SizedBox(height: 4),
        const Text('选一张毛孩照片，描述想改的效果，AI 帮你换装 / 风格化（图生图生成，结果含多个变体）',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 12),
        // 当前源图预览
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.brandSoft, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image(image: source.image, fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 快捷 prompt
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, p) in kFireRedPresets)
              GestureDetector(
                onTap: loading ? null : () => onPromptChanged(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: prompt == p ? t.brand : t.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.brandSoft, width: 1),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: prompt == p ? FontWeight.w700 : FontWeight.w500,
                          color: prompt == p ? Colors.white : t.textPrimary)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // 自定义 prompt
        TextField(
          onChanged: onPromptChanged,
          controller: TextEditingController(text: prompt),
          maxLines: 2,
          decoration: InputDecoration(
            hintText: '用英文描述效果，如：Add a birthday hat on the cat',
            hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
            filled: true,
            fillColor: t.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: t.brandSoft),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: t.brandSoft),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 生成按钮
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: loading ? null : () => onGenerate(prompt),
            icon: loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(LucideIcons.sparkles, size: 16),
            label: Text(loading ? '生成中…' : '生成', style: const TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 错误
        if (error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(error!, style: const TextStyle(fontSize: 12, color: Colors.red)),
          ),
        // 结果
        if (resultBytes != null) ...[
          if (demo)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('演示模式：未接入 AI 服务，已回显源图。部署代理后注入 FIERED_PROXY_URL 即可生效。',
                  style: TextStyle(fontSize: 11, color: Colors.orange)),
            ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.brandSoft, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.memory(resultBytes!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSave,
              icon: const Icon(LucideIcons.download, size: 16),
              label: const Text('存入相册', style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.brand,
                side: BorderSide(color: t.brand),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
