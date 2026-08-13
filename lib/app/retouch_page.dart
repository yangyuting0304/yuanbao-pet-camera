import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:pet_camera/app/app_back_button.dart';
import 'package:pet_camera/app/app_generated_result_page.dart';
import 'package:pet_camera/app/app_horizontal_edge_inset.dart';
import 'package:pet_camera/app/app_loading_view.dart';
import 'package:pet_camera/app/app_photo_preview_panel.dart';
import 'package:pet_camera/app/app_primary_action_button.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/retouch_data.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/ai_portrait_service.dart';
import 'package:pet_camera/data/captured_photos.dart';
import 'package:pet_camera/data/firered_service.dart';
import 'package:pet_camera/data/models.dart';
import 'package:pet_camera/data/seed_repository.dart';

/// 宠物 P 图相册项。
/// 这里把相册页里需要的图片、时间、宠物归属收口成一条数据，便于复用 AI 写真同款选图流程。
class _RetouchAlbumItem {
  const _RetouchAlbumItem({
    required this.source,
    required this.image,
    required this.takenAt,
    required this.petId,
  });

  final SourcePhoto source;
  final ImageProvider image;
  final DateTime takenAt;
  final String petId;

  /// 时间视图分组键：YYYY年M月。
  String get monthKey => '${takenAt.year}年${takenAt.month}月';
}

/// 宠物 P 图编辑器：选图 + 滤镜 + 贴纸 + 背景 + 形状，一键存相册。
/// Web 端用 RepaintBoundary.toImage 导出 PNG（含滤镜与贴纸），无需原生依赖。
class RetouchPage extends ConsumerStatefulWidget {
  const RetouchPage({super.key});
  @override
  ConsumerState<RetouchPage> createState() => _RetouchPageState();
}

class _RetouchPageState extends ConsumerState<RetouchPage> {
  static const Color _secondaryOptionBorderColor = Color(0xFFE2E4E6);

  SourcePhoto? _selected;
  int _filterIndex = 0;
  int _bgIndex = 0;
  int _shapeIndex = 0; // 0 圆角 1 圆形 2 方形
  int? _stickerPresetIndex; // 记录最近选择的贴纸预设，方便显示选中态。
  int _activeTab = 0; // 0 滤镜 1 贴纸 2 背景 3 形状 4 AI 编辑
  final List<Sticker> _stickers = [];
  final _boundaryKey = GlobalKey();
  bool _saving = false;

  // AI 创意编辑（FireRed）状态
  String _aiPrompt = kFireRedPresets.first.$2;
  bool _aiLoading = false;
  String? _aiError;

  /// 构建和 AI 写真一致的可选照片列表。
  List<_RetouchAlbumItem> _buildAlbumItems(
    List<Photo> seed,
    List<CapturedPhoto> captured,
  ) {
    final list = <_RetouchAlbumItem>[];
    for (final c in captured) {
      list.add(
        _RetouchAlbumItem(
          source: SourcePhoto(bytes: c.bytes, caption: '拍摄照片'),
          image: MemoryImage(c.bytes),
          takenAt: c.takenAt,
          petId: '',
        ),
      );
    }
    for (final p in seed) {
      list.add(
        _RetouchAlbumItem(
          source: SourcePhoto(assetPath: p.assetPath, caption: p.petId),
          image: AssetImage(p.assetPath),
          takenAt: p.capturedAt,
          petId: p.petId,
        ),
      );
    }
    return list;
  }

  /// 把 SourcePhoto 转回页面可直接使用的 ImageProvider。
  ImageProvider? _imageProviderFromSource(SourcePhoto? source) {
    if (source == null) return null;
    if (source.bytes != null) {
      return MemoryImage(source.bytes!);
    }
    if (source.assetPath != null) {
      return AssetImage(source.assetPath!);
    }
    return null;
  }

  /// 未选择照片时，统一用 toast 提示用户先上传图片。
  void _showUploadPhotoToast() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('请先上传照片')));
  }

  /// 编辑区顶部 Tab 点击。
  /// 顶部 Tab 只负责切换，不在这一层提示上传照片。
  void _handleEditorTabTap(int index) {
    setState(() => _activeTab = index);
  }

  /// 二级页返回：有历史就返回，没有历史就回首页，避免刷新后二级页返回白屏。
  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
  }

  /// 打开和 AI 写真同款的相册选择页。
  Future<void> _openAlbumPhotosPage(
    BuildContext context,
    List<_RetouchAlbumItem> items,
    List<Pet> pets,
  ) async {
    final selected = await Navigator.of(context).push<SourcePhoto>(
      MaterialPageRoute<SourcePhoto>(
        builder: (_) => _RetouchAlbumPickerPage(
          title: '选择照片',
          items: items,
          pets: pets,
          selected: _selected,
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selected = selected);
    }
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

  Future<void> _save() async {
    if (_saving || _selected == null) return;
    setState(() => _saving = true);
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2);
      final bd = await img.toByteData(format: ImageByteFormat.png);
      if (bd != null) {
        ref.read(capturedPhotosProvider.notifier).add(bd.buffer.asUint8List());
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已存入相册')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final photosAsync = ref.watch(photosProvider);
    final petsAsync = ref.watch(petsProvider);
    final captured = ref.watch(capturedPhotosProvider);
    final canvas = (MediaQuery.of(context).size.width - 40).clamp(240.0, 360.0);

    return Scaffold(
      // 宠物 P 图页面按最新要求改成纯白底。
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 44,
        leading: AppBackButton(onTap: _handleBack),
        centerTitle: true,
        title: Text(
          '毛孩美颜',
          style: TextStyle(
            fontSize: AppUi.fontTitle,
            height: AppUi.lineHeight(AppUi.fontTitle),
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: t.surface,
        foregroundColor: t.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      bottomNavigationBar: _activeTab == 4
          ? AppPrimaryActionIconBottomBar(
              icon: LucideIcons.sparkles,
              label: '生成照片',
              onPressed: _selected == null
                  ? null
                  : () => _generateAi(_aiPrompt),
              isLoading: _aiLoading,
            )
          : AppPrimaryActionIconBottomBar(
              icon: LucideIcons.download,
              label: '保存到相册',
              onPressed: _selected == null ? null : _save,
              isLoading: _saving,
            ),
      body: photosAsync.when(
        loading: () => const AppLoadingView(),
        error: (_, __) => const Center(child: Text('照片加载失败')),
        data: (photos) => petsAsync.when(
          loading: () => const AppLoadingView(),
          error: (_, __) => const Center(child: Text('宠物加载失败')),
          data: (pets) {
            final items = _buildAlbumItems(photos, captured);
            final selectedImage = _imageProviderFromSource(_selected);
            final helperText = switch (_activeTab) {
              1 => '贴纸可拖动，长按删除',
              4 => '描述想改的效果，AI帮你换装/风格化',
              _ => null,
            };
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '选择照片',
                        style: TextStyle(
                          fontSize: AppUi.fontHeadline,
                          height: 28 / AppUi.fontHeadline,
                          fontWeight: FontWeight.w400,
                          color: t.textPrimary,
                        ),
                      ),
                      if (_selected != null)
                        Row(
                          children: [
                            _RetouchActionButton(
                              label: '清空照片',
                              onTap: () => setState(() {
                                _selected = null;
                                _stickerPresetIndex = null;
                                _aiError = null;
                              }),
                            ),
                            const SizedBox(width: AppUi.space8),
                            _RetouchActionButton(
                              label: '重新选择',
                              filled: true,
                              onTap: () =>
                                  _openAlbumPhotosPage(context, items, pets),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: AppPhotoPreviewPanel(
                        source: _selected,
                        onTap: () => _openAlbumPhotosPage(context, items, pets),
                        width: canvas,
                        height: canvas,
                        clickableWhenFilled: false,
                        emptyIconName: MingCuteIcons.picLine,
                        emptyText: '请先选择照片',
                        emptyBackgroundColor: const Color(0xFFF6F8FA),
                        filledBackgroundColor: _bgIndex == 0
                            ? const Color(0xFFF6F8FA)
                            : kBgs[_bgIndex].color ?? const Color(0xFFF6F8FA),
                        filledChild: selectedImage == null
                            ? null
                            : Stack(
                                children: [
                                  Center(
                                    child: _shapeClip(
                                      child: ColorFiltered(
                                        colorFilter: ColorFilter.matrix(
                                          kFilters[_filterIndex].matrix,
                                        ),
                                        child: Image(
                                          image: selectedImage,
                                          fit: BoxFit.cover,
                                          width: canvas,
                                          height: canvas,
                                        ),
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
                                        onLongPress: () =>
                                            setState(() => _stickers.remove(s)),
                                        child: Icon(
                                          s.icon,
                                          size: s.size,
                                          color: s.color,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '编辑照片',
                        style: TextStyle(
                          fontSize: AppUi.fontHeadline,
                          height: 28 / AppUi.fontHeadline,
                          fontWeight: FontWeight.w400,
                          color: t.textPrimary,
                        ),
                      ),
                      Opacity(
                        // 说明文案固定占位，避免切换 tab 时标题行抖动。
                        opacity: helperText != null ? 1 : 0,
                        child: Text(
                          helperText ?? '',
                          style: const TextStyle(
                            fontSize: AppUi.fontCaption,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ToolTabs(active: _activeTab, onTap: _handleEditorTabTap),
                  const SizedBox(height: 8),
                  _panel(t, canvas, _selected, selectedImage),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _panel(
    AppTokens t,
    double canvas,
    SourcePhoto? selectedSource,
    ImageProvider? selectedImage,
  ) {
    switch (_activeTab) {
      case 0:
        return _FilterPanel(
          active: _filterIndex,
          onSelect: (i) {
            if (selectedSource == null) {
              _showUploadPhotoToast();
              return;
            }
            setState(() => _filterIndex = i);
          },
        );
      case 1:
        return _StickerPanel(
          active: _stickerPresetIndex,
          onAdd: (index, icon, color) {
            if (selectedSource == null) {
              _showUploadPhotoToast();
              return;
            }
            setState(() {
              _stickerPresetIndex = index;
              _stickers.add(
                Sticker(icon, canvas / 2 - 24, canvas / 2 - 24, 48, color),
              );
            });
          },
          onClear: () {
            if (selectedSource == null) {
              _showUploadPhotoToast();
              return;
            }
            setState(() {
              _stickers.clear();
              _stickerPresetIndex = null;
            });
          },
        );
      case 2:
        return _BgPanel(
          active: _bgIndex,
          onSelect: (i) {
            if (selectedSource == null) {
              _showUploadPhotoToast();
              return;
            }
            setState(() => _bgIndex = i);
          },
        );
      case 3:
        return _ShapePanel(
          active: _shapeIndex,
          onSelect: (i) {
            if (selectedSource == null) {
              _showUploadPhotoToast();
              return;
            }
            setState(() => _shapeIndex = i);
          },
        );
      default:
        return _AiEditPanel(
          prompt: _aiPrompt,
          onPromptChanged: (v) => setState(() => _aiPrompt = v),
          loading: _aiLoading,
          error: _aiError,
        );
    }
  }

  /// 调 FireRed 代理做图像编辑（图生图）。
  Future<void> _generateAi(String prompt) async {
    if (_aiLoading || _selected == null) return;
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });
    try {
      final bytes = await _selected!.resolveBytes();
      final res = await ref
          .read(fireRedServiceProvider)
          .edit(sourceBytes: bytes, prompt: prompt);
      if (!mounted) return;
      setState(() => _aiLoading = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AppGeneratedResultPage(
            resultBytes: res.imageBytes,
            demo: res.demo,
            demoText: '演示模式：未接入 AI 服务，已回显源图。',
            onSave: () async {
              ref.read(capturedPhotosProvider.notifier).add(res.imageBytes);
            },
          ),
        ),
      );
      return;
    } on FireRedException catch (e) {
      if (mounted) setState(() => _aiError = e.message);
    } catch (e) {
      if (mounted) setState(() => _aiError = '生成出错：$e');
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
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
    return AppHorizontalEdgeScroll(
      height: 40,
      parentHorizontalPadding: 20,
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final (icon, label) = _tabs[i];
          final on = i == active;
          return Padding(
            padding: EdgeInsets.only(right: i == _tabs.length - 1 ? 0 : 8),
            child: GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: on ? t.brand : const Color(0xFFF6F8FA),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: AppUi.iconSmall,
                      color: on ? t.textPrimary : t.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppUi.fontBody,
                        fontWeight: FontWeight.w400,
                        color: on ? t.textPrimary : t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: kFilters.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, i) {
        final f = kFilters[i];
        final on = i == active;
        return _RetouchSecondaryOptionTile(
          onTap: () => onSelect(i),
          selected: on,
          child: Center(
            child: Text(
              f.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppUi.fontBody,
                fontWeight: FontWeight.w400,
                color: context.tokens.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 贴纸面板（添加 + 清空）
class _StickerPanel extends StatelessWidget {
  const _StickerPanel({
    required this.active,
    required this.onAdd,
    required this.onClear,
  });
  final int? active;
  final void Function(int, IconData, Color) onAdd;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: kStickerIcons.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _RetouchSecondaryOptionTile(
            onTap: onClear,
            selected: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.undo2, size: 32, color: context.tokens.error),
                const SizedBox(height: 8),
                Text(
                  '清空',
                  style: TextStyle(
                    fontSize: AppUi.fontCaption,
                    color: context.tokens.error,
                  ),
                ),
              ],
            ),
          );
        }
        final (icon, color) = kStickerIcons[index - 1];
        return _RetouchSecondaryOptionTile(
          onTap: () => onAdd(index - 1, icon, color),
          selected: active == index - 1,
          child: Center(child: Icon(icon, size: 32, color: color)),
        );
      },
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: kBgs.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (context, i) {
        final b = kBgs[i];
        final on = i == active;
        return _RetouchSecondaryOptionTile(
          onTap: () => onSelect(i),
          selected: on,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: b.color ?? Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: b.color == null
                        ? const Color(0xFFE2E4E6)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: b.color == null
                    ? Icon(
                        LucideIcons.ban,
                        size: AppUi.iconSmall,
                        color: context.tokens.textSecondary,
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                b.name,
                style: TextStyle(
                  fontSize: AppUi.fontCaption,
                  color: context.tokens.textPrimary,
                ),
              ),
            ],
          ),
        );
      },
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _shapes.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (context, i) {
        final (icon, label) = _shapes[i];
        final on = i == active;
        return _RetouchSecondaryOptionTile(
          onTap: () => onSelect(i),
          selected: on,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: Colors.black),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppUi.fontCaption,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                  color: context.tokens.textPrimary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 次级选项统一卡片。
/// 统一为白底卡片，选中时主色描边，未选中时浅色描边。
class _RetouchSecondaryOptionTile extends StatelessWidget {
  const _RetouchSecondaryOptionTile({
    required this.child,
    required this.onTap,
    required this.selected,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          border: Border.all(
            color: selected
                ? context.tokens.brand
                : _RetouchPageState._secondaryOptionBorderColor,
            width: 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// AI 创意编辑面板（FireRed-Image-Edit）：选图 + 快捷 prompt + 自定义 + 生成 + 结果九宫格。
class _AiEditPanel extends StatelessWidget {
  const _AiEditPanel({
    required this.prompt,
    required this.onPromptChanged,
    required this.loading,
    required this.error,
  });
  final String prompt;
  final ValueChanged<String> onPromptChanged;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: kFireRedPresets.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.2,
          ),
          itemBuilder: (context, index) {
            final (label, p) = kFireRedPresets[index];
            final selected = prompt == p;
            return _RetouchSecondaryOptionTile(
              onTap: loading ? () {} : () => onPromptChanged(p),
              selected: selected,
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppUi.fontBody,
                    fontWeight: FontWeight.w400,
                    color: t.textPrimary,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        // 自定义 prompt
        TextField(
          onChanged: onPromptChanged,
          minLines: 3,
          maxLines: 3,
          style: TextStyle(fontSize: AppUi.fontBody, color: t.textPrimary),
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
            // 输入框默认展示中文说明，内部仍然保留当前英文 prompt 用于生成。
            hintText: '描述想改的效果，例如：给毛孩加一个粉色蝴蝶结，保持原来的姿势和构图',
            hintStyle: TextStyle(
              fontSize: AppUi.fontBody,
              color: t.textSecondary,
            ),
            filled: true,
            fillColor: t.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              borderSide: const BorderSide(
                color: _RetouchPageState._secondaryOptionBorderColor,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              borderSide: const BorderSide(
                color: _RetouchPageState._secondaryOptionBorderColor,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              borderSide: const BorderSide(
                color: _RetouchPageState._secondaryOptionBorderColor,
              ),
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
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
            ),
            child: Text(
              error!,
              style: const TextStyle(
                fontSize: AppUi.fontCaption,
                color: Colors.red,
              ),
            ),
          ),
      ],
    );
  }
}

/// 标题行右侧的操作按钮。
/// 这里直接和 AI 写真使用同一套尺寸与颜色规则。
class _RetouchActionButton extends StatelessWidget {
  const _RetouchActionButton({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: filled ? context.tokens.brand : const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: AppUi.fontCaption,
            height: 20 / AppUi.fontCaption,
            fontWeight: FontWeight.w400,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

/// 宠物 P 图相册选择页。
/// 这里直接复用 AI 写真的单张选图流程和筛选结构，只是回填目标换成宠物 P 图。
class _RetouchAlbumPickerPage extends StatefulWidget {
  const _RetouchAlbumPickerPage({
    required this.title,
    required this.items,
    required this.pets,
    required this.selected,
  });

  final String title;
  final List<_RetouchAlbumItem> items;
  final List<Pet> pets;
  final SourcePhoto? selected;

  @override
  State<_RetouchAlbumPickerPage> createState() =>
      _RetouchAlbumPickerPageState();
}

class _RetouchAlbumPickerPageState extends State<_RetouchAlbumPickerPage> {
  bool _byTime = false;
  String? _selectedPetId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 44,
        leading: AppBackButton(onTap: () => Navigator.pop(context)),
        centerTitle: true,
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: AppUi.fontTitle,
            height: AppUi.lineHeight(AppUi.fontTitle),
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: context.tokens.surface,
        foregroundColor: context.tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppUi.pagePadding,
                AppUi.space24,
                AppUi.pagePadding,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '筛选',
                          style: TextStyle(
                            fontSize: AppUi.fontHeadline,
                            height: 28 / AppUi.fontHeadline,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF000000),
                          ),
                        ),
                      ),
                      _RetouchAlbumModeTabs(
                        byTime: _byTime,
                        onSelectCategory: () => setState(() => _byTime = false),
                        onSelectTime: () => setState(() => _byTime = true),
                      ),
                    ],
                  ),
                  if (!_byTime) ...[
                    const SizedBox(height: 12),
                    _buildPetFilterBar(),
                  ],
                ],
              ),
            ),
          ),
          if (_byTime) ..._buildTimeSlivers() else ..._buildPetSlivers(),
        ],
      ),
    );
  }

  /// 构建顶部宠物筛选条。
  Widget _buildPetFilterBar() {
    final petsWithPhotos = widget.pets
        .where((p) => widget.items.any((it) => it.petId == p.id))
        .toList();

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: petsWithPhotos.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: AppUi.space16),
        itemBuilder: (_, index) {
          if (index == 0) {
            return _RetouchPetFilterAllTile(
              selected: _selectedPetId == null,
              onTap: () => setState(() => _selectedPetId = null),
            );
          }
          final pet = petsWithPhotos[index - 1];
          return _RetouchPetFilterAvatarTile(
            name: pet.name,
            avatarPath: pet.avatarPath,
            selected: _selectedPetId == pet.id,
            onTap: () => setState(() => _selectedPetId = pet.id),
          );
        },
      ),
    );
  }

  /// 按宠物分组展示照片。
  List<Widget> _buildPetSlivers() {
    if (widget.pets.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppUi.pagePadding,
            AppUi.space32,
            AppUi.pagePadding,
            24,
          ),
          sliver: _RetouchSquareGridSliver(
            items: widget.items,
            selected: widget.selected,
          ),
        ),
      ];
    }

    final groups = <String, List<_RetouchAlbumItem>>{};
    for (final item in widget.items) {
      if (item.petId.isNotEmpty) {
        groups.putIfAbsent(item.petId, () => []).add(item);
      } else {
        groups.putIfAbsent('__other__', () => []).add(item);
      }
    }

    final slivers = <Widget>[];
    final petList = widget.pets
        .where((p) => (groups[p.id]?.isNotEmpty ?? false))
        .where((p) => _selectedPetId == null || _selectedPetId == p.id)
        .toList();

    for (final pet in petList) {
      final petItems = groups[pet.id]!;
      slivers.add(
        SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppUi.pagePadding,
                  AppUi.space32,
                  AppUi.pagePadding,
                  AppUi.space12,
                ),
                child: _RetouchPetProfileHeader(
                  pet: pet,
                  count: petItems.length,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppUi.pagePadding,
              ),
              sliver: _RetouchSquareGridSliver(
                items: petItems,
                selected: widget.selected,
              ),
            ),
          ],
        ),
      );
    }

    final otherItems = _selectedPetId == null ? groups['__other__'] : null;
    if (otherItems != null && otherItems.isNotEmpty) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppUi.pagePadding,
            AppUi.space32,
            AppUi.pagePadding,
            24,
          ),
          sliver: _RetouchSquareGridSliver(
            items: otherItems,
            selected: widget.selected,
          ),
        ),
      );
    }

    if (slivers.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              '还没有照片哦～',
              style: TextStyle(
                fontSize: AppUi.fontTitle,
                color: context.tokens.textSecondary,
              ),
            ),
          ),
        ),
      );
    }
    return slivers;
  }

  /// 按时间分组展示照片。
  List<Widget> _buildTimeSlivers() {
    final groups = <String, List<_RetouchAlbumItem>>{};
    for (final item in widget.items) {
      groups.putIfAbsent(item.monthKey, () => []).add(item);
    }
    final keys = groups.keys.toList();
    return [
      for (final key in keys)
        SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppUi.pagePadding,
                  AppUi.space32,
                  AppUi.pagePadding,
                  AppUi.space12,
                ),
                child: Text(
                  key,
                  style: TextStyle(
                    fontSize: AppUi.fontTitle,
                    fontWeight: FontWeight.w700,
                    color: context.tokens.textPrimary,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppUi.pagePadding,
              ),
              sliver: _RetouchSquareGridSliver(
                items: groups[key]!,
                selected: widget.selected,
              ),
            ),
          ],
        ),
    ];
  }
}

/// 相册顶部模式切换容器。
class _RetouchAlbumModeTabs extends StatelessWidget {
  const _RetouchAlbumModeTabs({
    required this.byTime,
    required this.onSelectCategory,
    required this.onSelectTime,
  });

  final bool byTime;
  final VoidCallback onSelectCategory;
  final VoidCallback onSelectTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 99,
      height: 26,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _RetouchAlbumModeTab(
              label: '分类',
              selected: !byTime,
              onTap: onSelectCategory,
            ),
          ),
          const SizedBox(width: 1),
          Expanded(
            child: _RetouchAlbumModeTab(
              label: '时间',
              selected: byTime,
              onTap: onSelectTime,
            ),
          ),
        ],
      ),
    );
  }
}

/// 相册顶部单个模式切换标签。
class _RetouchAlbumModeTab extends StatelessWidget {
  const _RetouchAlbumModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: selected ? context.tokens.brand : const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppUi.fontCaption,
            height: 18 / AppUi.fontCaption,
            fontWeight: FontWeight.w600,
            color: selected ? const Color(0xFF000000) : const Color(0xFFB4B4B4),
          ),
        ),
      ),
    );
  }
}

/// 宠物头像筛选项。
class _RetouchPetFilterAvatarTile extends StatelessWidget {
  const _RetouchPetFilterAvatarTile({
    required this.name,
    required this.avatarPath,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String avatarPath;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF000000)
                      : const Color(0xFFE2E4E6),
                  width: 1,
                ),
              ),
              child: ClipOval(
                child: Image.asset(
                  avatarPath,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: AppUi.space4),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppUi.fontCaption,
                height: 20 / AppUi.fontCaption,
                fontWeight: FontWeight.w400,
                color: selected
                    ? const Color(0xFF000000)
                    : const Color(0xFF999999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// “全部”筛选项。
class _RetouchPetFilterAllTile extends StatelessWidget {
  const _RetouchPetFilterAllTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF000000)
                      : const Color(0xFFE2E4E6),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: const MingCuteIcon(
                MingCuteIcons.classify3AiFill,
                size: AppUi.iconLarge,
                color: Color(0xFF000000),
              ),
            ),
            const SizedBox(height: AppUi.space4),
            Text(
              '全部',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppUi.fontCaption,
                height: 20 / AppUi.fontCaption,
                fontWeight: FontWeight.w400,
                color: selected
                    ? const Color(0xFF000000)
                    : const Color(0xFF999999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 宠物信息卡。
class _RetouchPetProfileHeader extends StatelessWidget {
  const _RetouchPetProfileHeader({required this.pet, required this.count});

  final Pet pet;
  final int count;

  @override
  Widget build(BuildContext context) {
    final subtitle = pet.breed.isNotEmpty
        ? (pet.ageLabel != '未知' ? '${pet.breed} · ${pet.ageLabel}' : pet.breed)
        : (pet.ageLabel != '未知' ? pet.ageLabel : '');
    return Container(
      height: 72,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
      ),
      child: Row(
        children: [
          ClipOval(
            child: Image.asset(
              pet.avatarPath,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppUi.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  pet.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppUi.fontTitle,
                    height: 24 / AppUi.fontTitle,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF000000),
                  ),
                ),
                const SizedBox(height: AppUi.space4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppUi.fontCaption,
                    height: 20 / AppUi.fontCaption,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppUi.space12),
          Text(
            '$count张',
            style: TextStyle(
              fontSize: AppUi.fontBody,
              height: AppUi.lineHeight(AppUi.fontBody),
              fontWeight: FontWeight.w400,
              color: context.tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 正方形照片选择网格。
/// 选中态和 AI 写真保持一致：图片缩小 90%，外层主色 2px 描边。
class _RetouchSquareGridSliver extends StatelessWidget {
  const _RetouchSquareGridSliver({required this.items, required this.selected});

  final List<_RetouchAlbumItem> items;
  final SourcePhoto? selected;

  bool _isSame(SourcePhoto a, SourcePhoto b) =>
      a.assetPath == b.assetPath && a.bytes == b.bytes;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate((context, index) {
        final item = items[index];
        final isSelected = selected != null && _isSame(selected!, item.source);
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(item.source),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              border: Border.all(
                color: isSelected ? context.tokens.brand : Colors.transparent,
                width: 1,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(isSelected ? 8 : 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  isSelected ? AppUi.radiusCard - 4 : AppUi.radiusCard,
                ),
                child: Image(image: item.image, fit: BoxFit.cover),
              ),
            ),
          ),
        );
      }, childCount: items.length),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
    );
  }
}
