// AI 写真页。拆分自原 pages.dart（8631 行）。
//
// part of pages.dart —— 切分理由见 camera_page.dart 顶部说明。

part of 'pages.dart';

/// AI 写真页（占位）。
/// AI 写真页（切片3）：源照片选择 + 风格选择 + 云端生成 + 结果预览 + 存相册。
/// 接 AiPortraitService（通义万相 DashScope 骨架）；未配 Key 时演示模式回显源图。
class PortraitPage extends ConsumerStatefulWidget {
  const PortraitPage({super.key});
  @override
  ConsumerState<PortraitPage> createState() => _PortraitPageState();
}

class _PortraitPageState extends ConsumerState<PortraitPage> {
  SourcePhoto? _selected;
  String _styleId = kPortraitStyles.first.id;
  bool _generating = false;
  String? _error;

  // 提示词输入框：默认回填所选风格内置提示词，可编辑 / AI 优化。
  final _promptCtrl = TextEditingController(text: kPortraitStyles.first.prompt);
  String? _promptError; // 提示词为空时的原处提示
  bool _optimizing = false; // AI 优化进行中（按钮 loading）

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  /// 相册照片使用单独的新页面展示完整列表，避免在当前页塞过多内容。
  Future<void> _openAlbumPhotosPage(
    BuildContext context,
    List<_AlbumItem> items,
    List<Pet> pets,
  ) async {
    final selected = await Navigator.of(context).push<SourcePhoto>(
      MaterialPageRoute<SourcePhoto>(
        builder: (_) => _PortraitAlbumPickerPage(
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

  /// AI 优化：把输入框里的提示词润色扩写为完整写真提示词，回填输入框。
  Future<void> _optimizePrompt() async {
    final input = _promptCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _promptError = '先输入想拍的画面，或直接点下方风格让系统帮你补全');
      return;
    }
    setState(() {
      _optimizing = true;
      _promptError = null;
    });
    try {
      final optimized = await ref
          .read(aiPortraitServiceProvider)
          .optimizePrompt(input);
      if (!mounted) return;
      setState(() {
        _promptCtrl.text = optimized;
        _optimizing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AI 已润色提示词，可直接开始生成')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _optimizing = false;
        _promptError = e is AiPortraitException ? e.message : '优化失败：$e';
      });
    }
  }

  Future<void> _generate() async {
    if (_selected == null || _generating) return;
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) {
      setState(() => _promptError = '提示词不能为空，先选一个风格或自己写一句');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
      _promptError = null;
    });
    try {
      final bytes = await _selected!.resolveBytes();
      final result = await ref
          .read(aiPortraitServiceProvider)
          .generatePortrait(
            PortraitRequest(sourceBytes: bytes, styleId: _styleId, prompt: prompt),
          );
      if (!mounted) return;
      setState(() => _generating = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AppGeneratedResultPage(
            resultBytes: result.imageBytes,
            demo: result.demo,
            onSave: () async {
              // 上传 COS + 登记 works.json（「我的创作」）。
              await ref
                  .read(worksProvider.notifier)
                  .add(
                    bytes: result.imageBytes,
                    type: LibraryType.createdImage,
                    ext: 'jpg',
                    label: 'AI 写真',
                  );
            },
          ),
        ),
      );
    } on AiPortraitException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _generating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '生成失败：$e';
          _generating = false;
        });
      }
    }
  }

  /// 「AI 优化」胶囊按钮（黑色 + sparkles，加载中转圈）。
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

  /// 提示词编辑区：回填所选风格的内置提示词，支持 AI 优化润色。
  Widget _buildPromptSection(AppTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '提示词',
              style: TextStyle(
                fontSize: AppUi.fontHeadline,
                height: 28 / AppUi.fontHeadline,
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            _buildOptimizeButton(t),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '已自动带所选风格的描述，可自由修改；也可以点「AI 优化」帮你润色扩写',
          style: TextStyle(fontSize: AppUi.fontCaption, color: t.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _promptCtrl,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) {
            if (_promptError != null) setState(() => _promptError = null);
          },
          style: TextStyle(
            fontSize: AppUi.fontCaption,
            height: AppUi.lineHeight(AppUi.fontCaption),
            color: t.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: '想拍的画面或造型，如：戴上珍珠项链、穿汉服回眸、在樱花树下…',
            hintStyle: TextStyle(
              fontSize: AppUi.fontCaption,
              height: AppUi.lineHeight(AppUi.fontCaption),
              color: t.textSecondary,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              borderSide: BorderSide(
                color: _promptError != null ? t.error : const Color(0xFFE2E4E6),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              borderSide: BorderSide(
                color: _promptError != null ? t.error : const Color(0xFFE2E4E6),
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(photosProvider);
    final petsAsync = ref.watch(petsProvider);
    final captured = ref.watch(capturedPhotosProvider);
    return _Shell(
      title: '毛孩写真',
      backgroundColor: Colors.white,
      bottomBar: AppPrimaryActionBottomBar(
        label: '开始生成',
        onPressed: _selected == null ? null : _generate,
        isLoading: _generating,
      ),
      body: photosAsync.when(
        loading: () => const AppLoadingView(),
        error: (_, __) => const Center(child: Text('照片加载失败')),
        data: (photos) => petsAsync.when(
          loading: () => const AppLoadingView(),
          error: (_, __) => const Center(child: Text('宠物加载失败')),
          data: (pets) =>
              _buildContent(context, _mergePhotos(photos, captured), pets),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<_AlbumItem> albumItems,
    List<Pet> pets,
  ) {
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
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
                  _PortraitActionButton(
                    label: '清空照片',
                    onTap: () => setState(() => _selected = null),
                  ),
                  const SizedBox(width: AppUi.space8),
                  _PortraitActionButton(
                    label: '重新选择',
                    filled: true,
                    onTap: () =>
                        _openAlbumPhotosPage(context, albumItems, pets),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        AppPhotoPreviewPanel(
          source: _selected,
          onTap: () => _openAlbumPhotosPage(context, albumItems, pets),
          emptyIconName: MingCuteIcons.picLine,
          emptyText: '请先选择照片',
        ),
        const SizedBox(height: 24),
        Text(
          '选择风格',
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
          itemCount: kPortraitStyles.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.08,
          ),
          itemBuilder: (context, index) {
            final style = kPortraitStyles[index];
            final active = style.id == _styleId;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _styleId = style.id;
                // 选中风格后把其内置提示词显示到输入框（可继续编辑 / AI 优化）。
                _promptCtrl.text = style.prompt;
                _promptError = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  border: Border.all(
                    color: active ? t.brand : const Color(0xFFE2E4E6),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PortraitStyleIcon(styleId: style.id, active: active),
                    const SizedBox(height: AppUi.space8),
                    Text(
                      style.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppUi.fontBody,
                        height: AppUi.lineHeight(AppUi.fontBody),
                        fontWeight: FontWeight.w400,
                        color: active ? t.textPrimary : t.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        _buildPromptSection(t),
        const SizedBox(height: 20),
        if (_generating)
          _ResultPlaceholder(
            iconName: MingCuteIcons.loading,
            text: 'AI 正在创作中…',
            spinning: true,
            t: t,
          )
        else if (_error != null)
          _ResultPlaceholder(
            iconName: MingCuteIcons.warning,
            text: _error!,
            t: t,
          ),
      ],
    );
  }
}

/// AI 写真风格图标映射。
/// 这里把风格 id 统一映射到指定的 MingCute fill 图标和对应颜色，避免页面里散落多套判断。
class _PortraitStyleIconData {
  const _PortraitStyleIconData({required this.iconName, required this.color});

  final String iconName;
  final Color color;
}

_PortraitStyleIconData _portraitStyleIconDataFor(String styleId) {
  switch (styleId) {
    case 'oil':
      return const _PortraitStyleIconData(
        iconName: MingCuteIcons.paletteFill,
        color: Color(0xFFE67E22),
      );
    case 'watercolor':
      return const _PortraitStyleIconData(
        iconName: MingCuteIcons.paintBrushFill,
        color: Color(0xFF4DA6FF),
      );
    case 'anime':
      return const _PortraitStyleIconData(
        iconName: MingCuteIcons.magic1Fill,
        color: Color(0xFF9B6BFF),
      );
    case 'vintage':
      return const _PortraitStyleIconData(
        iconName: MingCuteIcons.bowknotFill,
        color: Color(0xFFD97A8C),
      );
    case 'royal':
      return const _PortraitStyleIconData(
        iconName: MingCuteIcons.foldingFanFill,
        color: Color(0xFF2FA57C),
      );
    case 'festive':
      return const _PortraitStyleIconData(
        iconName: MingCuteIcons.celebrateFill,
        color: Color(0xFFFF6B4A),
      );
    default:
      return const _PortraitStyleIconData(
        iconName: MingCuteIcons.magic1Fill,
        color: Color(0xFF9B6BFF),
      );
  }
}

/// AI 写真单个风格图标。
/// 使用本地 MingCute fill SVG，并给每种风格一个固定彩色填充。
class _PortraitStyleIcon extends StatelessWidget {
  const _PortraitStyleIcon({required this.styleId, required this.active});

  final String styleId;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final data = _portraitStyleIconDataFor(styleId);
    return Opacity(
      opacity: active ? 1 : 0.92,
      child: MingCuteIcon(
        data.iconName,
        size: AppUi.iconLarge,
        color: data.color,
      ),
    );
  }
}

/// 标题行右侧的操作按钮。
/// 复用同一套样式给“清空照片”和“重新选择”。
class _PortraitActionButton extends StatelessWidget {
  const _PortraitActionButton({
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
          style: TextStyle(
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

/// 相册照片页。
/// 复用相册页同款筛选结构，只是照片列表改成正方形可选样式。
class _PortraitAlbumPickerPage extends StatefulWidget {
  const _PortraitAlbumPickerPage({
    required this.title,
    required this.items,
    required this.pets,
    required this.selected,
  });

  final String title;
  final List<_AlbumItem> items;
  final List<Pet> pets;
  final SourcePhoto? selected;

  @override
  State<_PortraitAlbumPickerPage> createState() =>
      _PortraitAlbumPickerPageState();
}

class _PortraitAlbumPickerPageState extends State<_PortraitAlbumPickerPage> {
  bool _byTime = false;
  String? _selectedPetId;

  @override
  Widget build(BuildContext context) {
    return _Shell(
      title: widget.title,
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppUi.pagePadding,
                24,
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
                      _AlbumModeTabs(
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
            return _PetFilterAllTile(
              selected: _selectedPetId == null,
              onTap: () => setState(() => _selectedPetId = null),
            );
          }
          final pet = petsWithPhotos[index - 1];
          return _PetFilterAvatarTile(
            name: pet.name,
            avatarUrl: pet.avatarUrl,
            selected: _selectedPetId == pet.id,
            onTap: () => setState(() => _selectedPetId = pet.id),
          );
        },
      ),
    );
  }

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
          sliver: _PortraitSquareGridSliver(
            items: widget.items,
            selected: widget.selected,
          ),
        ),
      ];
    }

    final groups = <String, List<_AlbumItem>>{};
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
                child: _PetProfileHeader(
                  pet: pet,
                  count: petItems.length,
                  compact: true,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppUi.pagePadding,
              ),
              sliver: _PortraitSquareGridSliver(
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
          sliver: _PortraitSquareGridSliver(
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

  List<Widget> _buildTimeSlivers() {
    final groups = <String, List<_AlbumItem>>{};
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
                child: _AlbumTimeHeaderCard(
                  date: groups[key]!.first.takenAt,
                  count: groups[key]!.length,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppUi.pagePadding,
              ),
              sliver: _PortraitSquareGridSliver(
                items: groups[key]!,
                selected: widget.selected,
              ),
            ),
          ],
        ),
    ];
  }
}

class _PortraitSquareGridSliver extends StatelessWidget {
  const _PortraitSquareGridSliver({
    required this.items,
    required this.selected,
  });

  final List<_AlbumItem> items;
  final SourcePhoto? selected;

  bool _isSame(SourcePhoto a, SourcePhoto b) =>
      a.url == b.url && a.bytes == b.bytes;

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
                // 选中时缩小图片内容，保持外层主色描边清晰可见。
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

/// AI 写真结果区占位（加载/错误/空态）。
class _ResultPlaceholder extends StatelessWidget {
  const _ResultPlaceholder({
    required this.iconName,
    required this.text,
    required this.t,
    this.spinning = false,
  });
  final String iconName;
  final String text;
  final AppTokens t;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          spinning
              ? SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: t.brand,
                  ),
                )
              : MingCuteIcon(
                  iconName,
                  size: AppUi.iconLarge,
                  color: t.textSecondary,
                ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppUi.fontBody, color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}
