// 相册页。拆分自原 pages.dart（8631 行）。
//
// part of pages.dart —— 切分理由见 camera_page.dart 顶部说明。

part of 'pages.dart';

/// 相册页：宠物/时间双视图，种子照片 + 用户拍摄照片合并展示。
class AlbumPage extends ConsumerWidget {
  const AlbumPage({super.key, this.showBackButton = true});

  /// 一级 Tab 场景隐藏返回按钮；二级独立页保留返回按钮。
  final bool showBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(photosProvider);
    final petsAsync = ref.watch(petsProvider);
    final captured = ref.watch(capturedPhotosProvider);
    // 作品清单来自 COS（works.json）；loading/error 时降级为空，不影响种子图展示。
    final works = ref.watch(worksProvider).value ?? const <LibraryItem>[];
    // 已上传云端的拍摄照片并入「照片」分组。
    final cloudPhotos =
        works.where((w) => w.type == LibraryType.capturedPhoto).toList();
    // 编辑图 / AI 生成图 / 视频 归入「我的创作」。
    final createdItems = works.where((w) => w.isCreatedGroup).toList();
    // 用户删掉的云端照片（本地屏蔽），合并时过滤掉。
    final hiddenUrls = ref.watch(hiddenPhotoUrlsProvider);
    final mergedItemsAsync = photosAsync.when(
      loading: () => const AppLoadingView(),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (photos) => petsAsync.when(
        loading: () => const AppLoadingView(),
        error: (_, __) => _AlbumView(
          items: _mergePhotos(photos, captured, cloudPhotos, hiddenUrls),
          pets: [],
          createdWorks: createdItems,
        ),
        data: (pets) => _AlbumView(
          items: _mergePhotos(photos, captured, cloudPhotos, hiddenUrls),
          pets: pets,
          createdWorks: createdItems,
        ),
      ),
    );

    if (!showBackButton) {
      return Scaffold(
        backgroundColor: context.tokens.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: AppUi.pagePadding,
        toolbarHeight: 44,
        title: AppTopNavBar(
          onOpenMine: () => Navigator.pushNamed(context, '/mine'),
        ),
        actions: [
          IconButton(
            tooltip: '从手机相册导入',
            onPressed: () => importFromDeviceGallery(context, ref),
            icon: MingCuteIcon(
              MingCuteIcons.pic2Line,
              size: AppUi.iconMedium,
              color: context.tokens.textPrimary,
            ),
          ),
        ],
        backgroundColor: context.tokens.surface,
        foregroundColor: context.tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
        // 顶部 24 间距要放进滚动内容里，避免形成固定白色留白。
        body: mergedItemsAsync,
      );
    }

    return Scaffold(
      // 相册页按最新要求单独使用纯白背景，不影响其他页面底色。
      backgroundColor: context.tokens.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 44,
        leading: AppBackButton(
          onTap: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/album', (route) => false);
          },
        ),
        centerTitle: true,
        title: Text(
          '相册',
          style: TextStyle(
            fontSize: AppUi.fontTitle,
            height: AppUi.lineHeight(AppUi.fontTitle),
            fontWeight: FontWeight.w700,
            color: context.tokens.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '从手机相册导入',
            onPressed: () => importFromDeviceGallery(context, ref),
            icon: MingCuteIcon(
              MingCuteIcons.pic2Line,
              size: AppUi.iconMedium,
              color: context.tokens.textPrimary,
            ),
          ),
        ],
        backgroundColor: context.tokens.surface,
        foregroundColor: context.tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      // 顶部 24 间距要放进滚动内容里，避免形成固定白色留白。
      body: mergedItemsAsync,
    );
  }
}

/// 相册统一显示单元（种子图用 AssetImage，拍摄图用 MemoryImage）。
class _AlbumItem {
  const _AlbumItem({
    required this.source,
    required this.image,
    required this.caption,
    required this.takenAt,
    this.petId = '',
    this.deletable = false,
    this.cloudUrl,
    this.livePath,
  });
  final SourcePhoto source;
  final ImageProvider image;
  final String caption;
  final DateTime takenAt;
  final String petId; // 所属宠物ID，用于"按宠物"分组

  /// 动态照片短片的本地文件路径（原生端拍摄且开启动态照片时才有）。
  final String? livePath;

  bool get hasLive => livePath != null;

  /// 是否允许用户删除。种子图（内置内容）不可删，用户拍摄的照片可删。
  final bool deletable;

  /// 云端照片的 URL（COS）。删除时记入本地屏蔽表，而不是走服务端删除。
  final String? cloudUrl;

  String get monthKey => '${takenAt.year}年${takenAt.month}月';
}

/// 合并「种子图 + 本地拍摄 + 云端拍摄作品」为相册照片分组。
/// [cloudPhotos] 来自 works.json 的 captured_photo（已上传 COS，刷新后仍可见）。
List<_AlbumItem> _mergePhotos(
  List<Photo> seed,
  List<CapturedPhoto> captured, [
  List<LibraryItem> cloudPhotos = const <LibraryItem>[],
  Set<String> hiddenUrls = const <String>{},
]) =>
    <_AlbumItem>[
      for (final c in captured)
        _AlbumItem(
          source: SourcePhoto(bytes: c.bytes, caption: '拍摄照片'),
          image: MemoryImage(c.bytes),
          caption: _fmtDateTime(c.takenAt),
          takenAt: c.takenAt,
          deletable: true,
          // 动态照片的短片路径（原生端且开启时才有），带出即出现 LIVE 角标。
          livePath: c.livePath,
          // 拍摄的照片暂不归属特定宠物（用户后续可指定）
        ),
      // 用户在 App 内删掉的云端照片在这里被过滤（本地屏蔽，见 PhotoStorage）。
      for (final w in cloudPhotos)
        if (!hiddenUrls.contains(w.url))
          _AlbumItem(
            source: SourcePhoto(url: w.url, caption: '拍摄照片'),
            image: CachedNetworkImageProvider(w.url),
            caption: _fmtDateTime(w.takenAt),
            takenAt: w.takenAt,
            petId: w.petId,
            deletable: true,
            cloudUrl: w.url,
          ),
      // 种子图是内置内容，不允许删除。
      for (final p in seed)
        _AlbumItem(
          source: SourcePhoto(url: p.remoteUrl, caption: p.petId),
          image: CachedNetworkImageProvider(p.remoteUrl),
          caption: p.capturedAt.toString().replaceFirst('.000', ''),
          takenAt: p.capturedAt,
          petId: p.petId,
        ),
    ];

String _fmtDateTime(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _AlbumView extends StatefulWidget {
  const _AlbumView({
    required this.items,
    required this.pets,
    required this.createdWorks,
  });
  final List<_AlbumItem> items;
  final List<Pet> pets;
  final List<LibraryItem> createdWorks;

  @override
  State<_AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<_AlbumView> {
  bool _byTime = false;
  bool _showCreated = false; // 「我的创作」分类
  String? _selectedPetId; // null = 全部宠物
  bool _argsLoaded = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 从路由参数读取 petId，自动筛选到对应宠物相册。
    // 注意：ModalRoute.of 依赖 InheritedWidget，必须在 didChangeDependencies
    // 中调用（initState 阶段调用会抛 dependOnInheritedWidgetOfExactType 异常）。
    if (_argsLoaded) return;
    _argsLoaded = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      final petId = args['petId'] as String?;
      if (petId != null && petId.isNotEmpty) {
        _selectedPetId = petId;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // 相册顶部筛选区：标题 + 分类/时间胶囊 + 宠物筛选带。
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
              children: <Widget>[
                Row(
                  children: <Widget>[
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
                if (!_byTime) ...<Widget>[
                  const SizedBox(height: 12),
                  _petFilterBar(),
                ],
              ],
            ),
          ),
        ),
        // 我的创作 / 照片网格（按宠物分组） / 时间分组
        if (_showCreated)
          ..._buildCreatedSlivers()
        else if (_byTime)
          ..._buildTimeSlivers()
        else
          ..._buildPetSlivers(),
      ],
    );
  }

  /// 「我的创作」分类：应用内生成的图片 / 视频（3 列方形网格）。
  List<Widget> _buildCreatedSlivers() {
    final works = widget.createdWorks;
    final t = context.tokens;
    if (works.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppUi.pagePadding,
            4,
            AppUi.pagePadding,
            24,
          ),
          sliver: SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
              ),
              child: Column(
                children: [
                  MingCuteIcon(
                    MingCuteIcons.photoAlbum,
                    size: AppUi.iconLarge,
                    color: t.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI 创作的图片和视频会显示在这里',
                    style: TextStyle(
                      fontSize: AppUi.fontBody,
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppUi.pagePadding,
          12,
          AppUi.pagePadding,
          24,
        ),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          delegate: SliverChildBuilderDelegate((context, i) {
            final w = works[i];
            if (w.isVideo) {
              final cover = w.coverUrl;
              return GestureDetector(
                onTap: () => _playCreatedVideo(context, w),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 有封面（AI 成片用源照片生成）时显示图；旧数据回退黑底。
                      if (cover != null && cover.isNotEmpty)
                        Image(
                          image: CachedNetworkImageProvider(cover),
                          fit: BoxFit.cover,
                        )
                      else
                        Container(color: Colors.black),
                      const Center(
                        child: MingCuteIcon(
                          MingCuteIcons.playCircle,
                          size: 32,
                          color: Colors.white70,
                        ),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '视频',
                            style: TextStyle(
                              fontSize: AppUi.fontCaption,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            // 作品统一以 COS 公网地址加载（刷新后仍可展示）。
            // 点击放大预览（与其他相册分类一致）。
            return GestureDetector(
              onTap: () => _previewCreatedImage(context, w),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                child: Image(
                  image: CachedNetworkImageProvider(w.url),
                  fit: BoxFit.cover,
                ),
              ),
            );
          }, childCount: works.length),
        ),
      ),
    ];
  }

  void _playCreatedVideo(BuildContext context, LibraryItem work) {
    showDialog<void>(
      context: context,
      builder: (_) => _CreatedVideoDialog(work: work),
    );
  }

  /// 「我的创作」图片点击放大预览（与其他相册分类共用 [_PhotoDialog]）。
  void _previewCreatedImage(BuildContext context, LibraryItem work) {
    showDialog<void>(
      context: context,
      builder: (_) => _PhotoDialog(
        item: _AlbumItem(
          source: SourcePhoto(url: work.url, caption: work.label),
          image: CachedNetworkImageProvider(work.url),
          caption: work.label.isEmpty ? 'AI 创作' : work.label,
          takenAt: work.takenAt,
          petId: work.petId,
        ),
      ),
    );
  }

  /// 按宠物分组：每个宠物一个档案头 + 该宠物的照片瀑布流
  List<Widget> _buildPetSlivers() {
    final t = context.tokens;

    if (widget.pets.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppUi.pagePadding,
            4,
            AppUi.pagePadding,
            24,
          ),
          sliver: _MasonryGrid(items: widget.items),
        ),
      ];
    }

    // 按 petId 分组
    final groups = <String, List<_AlbumItem>>{};
    for (final item in widget.items) {
      if (item.petId.isNotEmpty) {
        groups.putIfAbsent(item.petId, () => []).add(item);
      } else {
        // 没有归属的照片归到"其他"
        groups.putIfAbsent('__other__', () => []).add(item);
      }
    }

    final slivers = <Widget>[];
    final petList = widget.pets
        .where((p) => (groups[p.id]?.isNotEmpty ?? false))
        .where((p) => _selectedPetId == null || _selectedPetId == p.id)
        .toList();
    for (int i = 0; i < petList.length; i++) {
      final pet = petList[i];
      final petItems = groups[pet.id]!;

      // 宠物分组
      slivers.add(
        SliverMainAxisGroup(
          slivers: [
            // 宠物档案头（紧凑版）
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
            // 该宠物的照片瀑布流
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppUi.pagePadding,
              ),
              sliver: _MasonryGrid(items: petItems),
            ),
          ],
        ),
      );
    }

    // "其他"分组（拍摄的无归属照片）——仅"全部"模式显示
    final otherItems = _selectedPetId == null ? groups['__other__'] : null;
    if (otherItems != null && otherItems.isNotEmpty) {
      slivers.add(
        SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: t.brand,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '最近拍摄',
                      style: TextStyle(
                        fontSize: AppUi.fontTitle,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${otherItems.length}张',
                      style: TextStyle(
                        fontSize: AppUi.fontBody,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppUi.pagePadding,
              ),
              sliver: _MasonryGrid(items: otherItems),
            ),
          ],
        ),
      );
    }

    // 如果没有任何照片
    if (slivers.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              '还没有照片哦～',
              style: TextStyle(
                fontSize: AppUi.fontTitle,
                color: t.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  /// 顶部筛选栏：「全部」+「我的创作」+ 宠物头像。
  Widget _petFilterBar() {
    final petsWithPhotos = widget.pets
        .where((p) => widget.items.any((it) => it.petId == p.id))
        .toList();

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: petsWithPhotos.length + 2,
        separatorBuilder: (_, __) => const SizedBox(width: AppUi.space16),
        itemBuilder: (_, index) {
          if (index == 0) {
            // 全部：不选任何宠物、也不选「我的创作」。
            return _PetFilterAllTile(
              selected: _selectedPetId == null && !_showCreated,
              onTap: () => setState(() {
                _selectedPetId = null;
                _showCreated = false;
              }),
            );
          }
          if (index == 1) {
            // 我的创作：应用内 AI 生成的图片 / 视频。
            return _PetFilterCreatedTile(
              selected: _showCreated,
              onTap: () => setState(() {
                _showCreated = !_showCreated;
                if (_showCreated) _selectedPetId = null;
              }),
            );
          }

          final pet = petsWithPhotos[index - 2];
          return _PetFilterAvatarTile(
            name: pet.name,
            avatarUrl: pet.avatarUrl,
            selected: _selectedPetId == pet.id,
            onTap: () => setState(() {
              _selectedPetId = _selectedPetId == pet.id ? null : pet.id;
              _showCreated = false;
            }),
          );
        },
      ),
    );
  }

  List<Widget> _buildTimeSlivers() {
    final groups = <String, List<_AlbumItem>>{};
    for (final p in widget.items) {
      groups.putIfAbsent(p.monthKey, () => []).add(p);
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
              sliver: _MasonryGrid(items: groups[key]!),
            ),
          ],
        ),
    ];
  }
}

/// 相册按时间分组头部卡片。
/// 左侧展示“8月 + 2026年”，右侧展示图片图标和数量，统一复用同一套样式。
class _AlbumTimeHeaderCard extends StatelessWidget {
  const _AlbumTimeHeaderCard({required this.date, required this.count});

  final DateTime date;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.month}月',
                style: const TextStyle(
                  fontSize: 16,
                  height: 24 / 16,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF000000),
                ),
              ),
              Text(
                '${date.year}年',
                style: const TextStyle(
                  fontSize: 12,
                  height: 20 / 12,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF999999),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const MingCuteIcon(
                MingCuteIcons.picFill,
                size: 24,
                color: Color(0xFF999999),
              ),
              Text(
                '$count 张',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12,
                  height: 20 / 12,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF999999),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 相册顶部模式切换容器。
/// 按设计稿改为 99x26 的浅灰胶囊，内部两项都是 48x24。
class _AlbumModeTabs extends StatelessWidget {
  const _AlbumModeTabs({
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
            child: _AlbumModeTab(
              label: '分类',
              selected: !byTime,
              onTap: onSelectCategory,
            ),
          ),
          const SizedBox(width: 1),
          Expanded(
            child: _AlbumModeTab(
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
/// 选中态为黄底黑字，未选中态为浅灰底辅助色文字。
class _AlbumModeTab extends StatelessWidget {
  const _AlbumModeTab({
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
          color: selected ? const Color(0xFFFFEE35) : const Color(0xFFF6F8FA),
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

/// 相册/成长页统一宠物筛选项：和首页顶部宠物展示保持同一套 64x88 结构。
class _PetFilterAvatarTile extends StatelessWidget {
  const _PetFilterAvatarTile({
    required this.name,
    required this.avatarUrl,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String avatarUrl;
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
          crossAxisAlignment: CrossAxisAlignment.center,
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
                child: AppImage(
                  url: avatarUrl,
                  width: 56,
                  height: 56,
                  memCacheWidth: 112,
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

/// “全部”筛选项没有宠物头像，使用同结构的圆形入口承接统一样式。
class _PetFilterAllTile extends StatelessWidget {
  const _PetFilterAllTile({required this.selected, required this.onTap});

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

/// 相册「分类」tab 下的子筛选：查看应用内创作（AI 成片等）。
/// 与 _PetFilterAllTile 同结构，区别在 label 和 icon 语义。
class _PetFilterCreatedTile extends StatelessWidget {
  const _PetFilterCreatedTile({required this.selected, required this.onTap});
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
                MingCuteIcons.photoAlbum,
                size: AppUi.iconLarge,
                color: Color(0xFF000000),
              ),
            ),
            const SizedBox(height: AppUi.space4),
            Text(
              '我的创作',
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

/// 宠物档案头（横排：左侧头像+名字+品种，右侧统计卡片）。
class _PetProfileHeader extends StatelessWidget {
  const _PetProfileHeader({
    required this.pet,
    required this.count,
    this.compact = false,
  });
  final Pet pet;
  final int count;
  final bool compact; // 紧凑模式：用于按宠物分组内的标题（小头像+紧凑间距）

  @override
  Widget build(BuildContext context) {
    final subtitle = pet.breed.isNotEmpty
        ? (pet.ageLabel != '未知' ? '${pet.breed} · ${pet.ageLabel}' : pet.breed)
        : (pet.ageLabel != '未知' ? pet.ageLabel : '');

    if (compact) {
      return Container(
        height: 72,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
        ),
        child: Row(
          children: [
            Row(
              children: [
                ClipOval(
                  child: AppImage(
                    url: pet.avatarUrl,
                    width: 48,
                    height: 48,
                    memCacheWidth: 96,
                  ),
                ),
                const SizedBox(width: AppUi.space12),
                SizedBox(
                  width: 142,
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
              ],
            ),
            const Spacer(),
            SizedBox(
              width: 36,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const MingCuteIcon(
                    MingCuteIcons.picFill,
                    size: AppUi.iconLarge,
                    color: Color(0xFF999999),
                  ),
                  const SizedBox(height: AppUi.space4),
                  Text(
                    '$count 张',
                    textAlign: TextAlign.right,
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
          ],
        ),
      );
    }

    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: AppImage(
              url: pet.avatarUrl,
              width: 56,
              height: 56,
              memCacheWidth: 112,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pet.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12.5, color: t.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MingCuteIcon(MingCuteIcons.picLine, size: 16, color: t.brand),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '张',
                  style: TextStyle(fontSize: 11, color: t.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 瀑布流网格（2 列，不等高，Pinterest 风格）。
/// 用两列 ListView 模拟瀑布流，避免引入第三方包。
class _MasonryGrid extends StatefulWidget {
  const _MasonryGrid({required this.items});
  final List<_AlbumItem> items;
  @override
  State<_MasonryGrid> createState() => _MasonryGridState();
}

class _MasonryGridState extends State<_MasonryGrid> {
  /// 根据索引决定高度比例（模拟自然分布），奇数略高偶数略矮。
  double _aspectRatio(int index) {
    switch (index % 5) {
      case 0:
        return 0.78; // 偏宽（横构图猫照）
      case 1:
        return 1.05; // 偏高（竖构图猫照）
      case 2:
        return 0.88; // 接近方
      case 3:
        return 1.15; // 高
      default:
        return 0.95; // 标准
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    // 分成左右两列
    final leftItems = <int>[];
    final rightItems = <int>[];
    for (var i = 0; i < items.length; i++) {
      if (i.isEven) {
        leftItems.add(i);
      } else {
        rightItems.add(i);
      }
    }

    return SliverToBoxAdapter(
      // 这里不能用 SliverFillRemaining，否则每个时间分组都会把剩余视口撑满，
      // 导致分组末尾出现大块空白。
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _MasonryColumn(
              items: items,
              indices: leftItems,
              getRatio: _aspectRatio,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MasonryColumn(
              items: items,
              indices: rightItems,
              getRatio: _aspectRatio,
            ),
          ),
        ],
      ),
    );
  }
}

class _MasonryColumn extends StatelessWidget {
  const _MasonryColumn({
    required this.items,
    required this.indices,
    required this.getRatio,
  });
  final List<_AlbumItem> items;
  final List<int> indices;
  final double Function(int) getRatio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in indices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PhotoTile(item: items[i], aspectRatio: getRatio(i)),
          ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.item, this.aspectRatio = 1.0});
  final _AlbumItem item;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (_) => _PhotoDialog(item: item),
        ),
        onLongPress: () => _showPreview(context),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F5F2), // 暖灰白底色，让浅色照片边缘可见
            borderRadius: BorderRadius.circular(AppUi.radiusCard),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: aspectRatio,
                child: Image(
                  image: item.image,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              // 动态照片角标（对齐 iOS 相册左上角的 LIVE 标签）。
              if (item.hasLive)
                const Positioned(top: 8, left: 8, child: _LiveBadge()),
            ],
          ),
        ),
      ),
    );
  }

  void _showPreview(BuildContext context) {
    // 长按 = 播放动态照片，对齐 iOS 相册里长按 Live Photo 就动起来的直觉。
    if (item.hasLive) {
      showDialog<void>(
        context: context,
        builder: (_) => _LivePhotoPlayerDialog(item: item),
      );
      return;
    }
    // 没有动态短片的照片，长按只提示拍摄时间（保留原有反馈）。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('拍摄于 ${item.caption}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

/// 动态照片角标（对齐 iOS 相册左上角的 LIVE 标签）。
///
/// 用同心圆小图标 + LIVE 字样：和相机页顶部的开关同一套视觉语言，
/// 用户一眼能把"这个能播"和"那个是开关"联系起来。
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.2),
            ),
            child: Center(
              child: Container(
                width: 3,
                height: 3,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// 动态照片播放弹窗：在相册里长按 LIVE 照片时打开，循环播放那 2 秒短片。
///
/// 做成"打开后循环播放、点击关闭"，而不是 iOS 的"按住才播、松手即停"：
/// Flutter 的长按回调拿不到可靠的松手时机（松手时弹窗已经打开了）。
/// 播放器本身由 [buildLivePlayer] 构造，Web 端自动回落为静态图。
class _LivePhotoPlayerDialog extends StatelessWidget {
  const _LivePhotoPlayerDialog({required this.item});

  final _AlbumItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: buildLivePlayer(
                // 只有 hasLive 才会打开本弹窗（见 _PhotoTile._showPreview）。
                item.livePath!,
                fallback: Image(image: item.image, fit: BoxFit.contain),
              ),
            ),
            const Positioned(top: 60, left: 20, child: _LiveBadge()),
            Positioned(
              bottom: 56,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '动态照片 · 点击关闭',
                  style: TextStyle(
                    fontSize: AppUi.fontCaption,
                    color: Colors.white.withValues(alpha: 0.7),
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

/// 全屏照片预览弹窗（可双指缩放 + 保存到相册）。
class _PhotoDialog extends ConsumerStatefulWidget {
  const _PhotoDialog({required this.item});
  final _AlbumItem item;

  @override
  ConsumerState<_PhotoDialog> createState() => _PhotoDialogState();
}

class _PhotoDialogState extends ConsumerState<_PhotoDialog> {
  bool _saving = false;
  bool _deleting = false;

  /// 取原图字节：本地拍摄的照片直接有 bytes；云端照片（COS）需要现拉一次。
  /// 保存必须是**原图**，不能用屏幕上那份已经被缩放显示过的位图。
  Future<Uint8List?> _loadBytes() async {
    final local = widget.item.source.bytes;
    if (local != null && local.isNotEmpty) return local;
    final url = widget.item.source.url;
    if (url == null || url.isEmpty) return null;
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return null;
      return resp.bodyBytes;
    } catch (e) {
      debugPrint('[保存照片] 下载原图失败：$e');
      return null;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    String? problem;
    try {
      final bytes = await _loadBytes();
      if (bytes == null) {
        problem = '照片还没准备好，请稍后再试';
      } else {
        problem = await savePhotoToGallery(bytes);
      }
    } catch (e) {
      problem = '保存失败：$e';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          problem ??
              (gallerySaveSupported ? '已保存到系统相册' : '已开始下载'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 播放动态照片（详情页里的显式入口，与网格长按共用同一个播放弹窗）。
  void _playLive() {
    showDialog<void>(
      context: context,
      builder: (_) => _LivePhotoPlayerDialog(item: widget.item),
    );
  }

  /// 删除这张照片（二次确认）。
  ///
  /// 两条路径：
  ///   - 本地拍摄：内存列表 + 磁盘文件一起删（[CapturedPhotosNotifier.remove]）。
  ///   - 已上传云端：服务端暂无删除接口，记入本地屏蔽表——在 App 内看不见
  ///     即等于删掉，避免出现"删了又回来"的错觉。
  Future<void> _delete() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这张照片？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final url = widget.item.cloudUrl;
    if (url != null && url.isNotEmpty) {
      await ref.read(hiddenPhotoUrlsProvider.notifier).hide(url);
    } else {
      CapturedPhoto? target;
      for (final p in ref.read(capturedPhotosProvider)) {
        if (p.takenAt == widget.item.takenAt) {
          target = p;
          break;
        }
      }
      if (target != null) {
        ref.read(capturedPhotosProvider.notifier).remove(target);
      }
    }
    if (!mounted) return;
    // pop 之后本 context 失效，先取出 messenger 再关闭弹窗。
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('已删除'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final media = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 双指缩放 / 拖动查看画质细节——宠物照片经常要放大看毛和眼睛。
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: media.height * 0.68,
                maxWidth: media.width,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  InteractiveViewer(
                    minScale: 1,
                    maxScale: 6,
                    clipBehavior: Clip.hardEdge,
                    child: Image(
                      image: widget.item.image,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  if (widget.item.hasLive) ...[
                    // 角标只作标识，用 IgnorePointer 让它不拦手势，
                    // 否则会挡住双指缩放。
                    const Positioned(
                      top: 10,
                      left: 10,
                      child: IgnorePointer(child: _LiveBadge()),
                    ),
                    // 中央播放按钮：网格里的"长按播放"是隐藏操作，
                    // 详情页必须给一个看得见的入口，否则用户根本不知道
                    // 这张照片还能动。
                    GestureDetector(
                      onTap: _playLive,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.42),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              decoration: BoxDecoration(color: t.surface),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item.caption,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: AppUi.fontCaption,
                      ),
                    ),
                  ),
                  if (widget.item.deletable)
                    TextButton.icon(
                      onPressed: (_saving || _deleting) ? null : _delete,
                      icon: _deleting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline, size: 18),
                      label: const Text('删除'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE5484D),
                        textStyle: const TextStyle(
                          fontSize: AppUi.fontBody,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: (_saving || _deleting) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt, size: 18),
                    label: Text(gallerySaveSupported ? '保存到相册' : '下载'),
                    style: TextButton.styleFrom(
                      foregroundColor: t.textPrimary,
                      textStyle: const TextStyle(
                        fontSize: AppUi.fontBody,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
