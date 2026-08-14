import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_camera/app/app_back_button.dart';
import 'package:pet_camera/app/app_horizontal_edge_inset.dart';
import 'package:pet_camera/app/app_loading_view.dart';
import 'package:pet_camera/app/app_top_nav_bar.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/pages.dart';
import 'package:pet_camera/app/short_video_page.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/captured_photos.dart';
import 'package:pet_camera/data/models.dart';
import 'package:pet_camera/data/seed_repository.dart';
import 'package:pet_camera/data/short_videos.dart';
import 'package:video_player/video_player.dart';

/// 一级页面容器。
/// 统一管理首页、相册页和中间拍照操作，避免一级页面切换时底部栏消失。
class PrimaryTabPage extends StatefulWidget {
  const PrimaryTabPage({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<PrimaryTabPage> createState() => _PrimaryTabPageState();
}

class _PrimaryTabPageState extends State<PrimaryTabPage> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 1);
  }

  void _onTabTap(int index) {
    if (index == 2) {
      Navigator.pushNamed(context, '/camera');
      return;
    }
    if (_currentIndex == index) return;
    _switchPrimaryTab(index);
  }

  /// 一级 Tab 切换时同步浏览器地址，保证 Web 刷新仍能回到当前页面。
  /// 如果地址异常或无法恢复，统一兜底回首页。
  void _switchPrimaryTab(int index) {
    final targetRoute = index == 1 ? '/album' : '/onboarding';
    final currentRoute = ModalRoute.of(context)?.settings.name;

    if (currentRoute == targetRoute) {
      setState(() => _currentIndex = index);
      return;
    }

    Navigator.of(context).pushReplacementNamed(targetRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomePage(onOpenAlbumTab: () => _switchPrimaryTab(1)),
          const AlbumPage(showBackButton: false),
        ],
      ),
      bottomNavigationBar: _PrimaryBottomBar(
        currentIndex: _currentIndex,
        onTap: _onTabTap,
      ),
    );
  }
}

/// 首页。
/// 这里单独抽成一级页，避免继续依赖旧的入口页和旧导航逻辑。
class HomePage extends ConsumerWidget {
  const HomePage({super.key, required this.onOpenAlbumTab});

  final VoidCallback onOpenAlbumTab;

  static const List<String> _recentPhotos = <String>[
    'yuanbao_2157.jpg',
    'yuanbao_2158.jpg',
    'yuanbao_2161.jpg',
    'xiaomianhua_021.jpg',
    'xiaotangyuan_026.jpg',
    'friend_020.jpg',
    'yuanbao_141.jpg',
    'yuanbao_140.jpg',
  ];

  static const List<_HomeFeature> _features = <_HomeFeature>[
    _HomeFeature(
      title: '毛孩写真',
      subtitle: 'AI 一键生成不同风格',
      tag: 'AI',
      icon: MingCuteIcons.magic2,
      imagePath: 'assets/seed/photos/feat_portrait.jpg',
      route: '/portrait',
    ),
    _HomeFeature(
      title: '一键成片',
      subtitle: '选几张图就能做短片',
      tag: '视频',
      icon: MingCuteIcons.videoLine,
      imagePath: 'assets/seed/photos/feat_video_thumb.jpg',
      videoAssetPath: 'assets/seed/photos/feat_video_compressed.mp4',
      route: '/short-video',
    ),
    _HomeFeature(
      title: '毛孩美颜',
      subtitle: '换背景、加贴纸更轻松',
      tag: '修图',
      icon: MingCuteIcons.palette,
      imagePath: 'assets/seed/photos/feat_retouch.jpg',
      route: '/retouch',
    ),
    _HomeFeature(
      title: '成长手记',
      subtitle: '记录体重、疫苗和趣事',
      tag: '记录',
      icon: MingCuteIcons.book,
      imagePath: 'assets/seed/photos/feat_profile.jpg',
      route: '/pet-profile',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final petsAsync = ref.watch(petsProvider);
    final photosAsync = ref.watch(photosProvider);
    final recentPhotoPaths = photosAsync.maybeWhen(
      // 首页“毛孩近照”只展示最近 20 张，避免首屏列表过长。
      data: (photos) => photos
          .take(20)
          .map((photo) => photo.assetPath)
          .toList(growable: false),
      orElse: () => _recentPhotos
          .map((fileName) => 'assets/seed/photos/$fileName')
          .toList(growable: false),
    );
    final heroPreviewPaths = photosAsync.maybeWhen(
      // 首屏缩略图直接复用现有相册数据，数量在卡片内部按可用宽度动态计算。
      data: (photos) =>
          photos.map((photo) => photo.assetPath).toList(growable: false),
      orElse: () => _recentPhotos
          .map((fileName) => 'assets/seed/photos/$fileName')
          .toList(growable: false),
    );
    final heroAlbumCount = photosAsync.maybeWhen(
      data: (photos) => photos.length,
      orElse: () => _recentPhotos.length,
    );
    return Scaffold(
      // 首页背景按最新要求单独使用纯白色，不影响其他一级页面。
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: AppUi.pagePadding,
        toolbarHeight: 44,
        title: AppTopNavBar(
          onOpenMine: () => Navigator.pushNamed(context, '/mine'),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppUi.space24),
              child: petsAsync.when(
                loading: () => const AppLoadingView(compact: true, height: 88),
                error: (_, __) => const SizedBox.shrink(),
                data: (pets) => _PetSnapshotStrip(pets: pets),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppUi.pagePadding,
                AppUi.space32,
                AppUi.pagePadding,
                0,
              ),
              child: _HomeHeroSection(
                albumCount: heroAlbumCount,
                previewPaths: heroPreviewPaths,
                onOpenAlbum: onOpenAlbumTab,
                onOpenCamera: () => Navigator.pushNamed(context, '/camera'),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppUi.pagePadding,
                AppUi.space32,
                AppUi.pagePadding,
                0,
              ),
              child: _SectionTitle(
                title: '喵喵惊喜',
                titleSize: AppUi.fontHeadline,
                titleWeight: FontWeight.w400,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppUi.pagePadding,
              AppUi.space12,
              AppUi.pagePadding,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 12.0;
                  final itemWidth = (constraints.maxWidth - spacing) / 2;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final feature in _features)
                        SizedBox(
                          width: itemWidth,
                          child: _FeatureCard(
                            feature: feature,
                            onTap: () =>
                                Navigator.pushNamed(context, feature.route),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppUi.pagePadding,
                AppUi.space32,
                AppUi.pagePadding,
                0,
              ),
              child: _SectionTitle(
                title: '毛孩近照',
                titleSize: AppUi.fontHeadline,
                titleWeight: FontWeight.w400,
                trailingLabel: '查看全部',
                onTrailingTap: onOpenAlbumTab,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppUi.pagePadding,
                AppUi.space12,
                AppUi.pagePadding,
                100,
              ),
              child: _RecentPhotoStrip(
                photos: recentPhotoPaths,
                onTapPhoto: (assetPath) => showDialog<void>(
                  context: context,
                  builder: (_) => _HomeRecentPhotoDialog(assetPath: assetPath),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 我的页。
/// 保持二级页面形态，并补上 Web 刷新后的返回兜底。
class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final petsAsync = ref.watch(petsProvider);
    final photosAsync = ref.watch(photosProvider);
    final captured = ref.watch(capturedPhotosProvider);
    final videos = ref.watch(shortVideosProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppUi.pagePadding,
            AppUi.space12,
            AppUi.pagePadding,
            AppUi.space24,
          ),
          children: [
            _SecondaryTopBar(
              title: '我的',
              onBack: () => _popWithFallback(context),
            ),
            const SizedBox(height: 20),
            petsAsync.when(
              loading: () => const AppLoadingView(),
              error: (_, __) => const SizedBox.shrink(),
              data: (pets) => _MineProfileCard(
                pets: pets,
                photoCount: photosAsync.maybeWhen(
                  data: (photos) => photos.length + captured.length,
                  orElse: () => captured.length,
                ),
                videoCount: videos.length,
              ),
            ),
            const SizedBox(height: 20),
            const _SectionTitle(
              title: '常用入口',
              titleSize: 20,
              titleWeight: FontWeight.w400,
            ),
            const SizedBox(height: 12),
            _MineActionTile(
              title: '我的短片',
              subtitle: '',
              icon: MingCuteIcons.videoLine,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ShortVideoLibraryPage(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _MineActionTile(
              title: '成长手记',
              subtitle: '',
              icon: MingCuteIcons.leaf2Line,
              onTap: () => Navigator.pushNamed(context, '/pet-profile'),
            ),
            const SizedBox(height: 12),
            _MineActionTile(
              title: '设置',
              subtitle: '',
              icon: MingCuteIcons.settings3Line,
              onTap: () => Navigator.pushNamed(context, '/settings'),
            ),
          ],
        ),
      ),
    );
  }

  void _popWithFallback(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
  }
}

class _HomeHeroSection extends StatelessWidget {
  const _HomeHeroSection({
    required this.albumCount,
    required this.previewPaths,
    required this.onOpenAlbum,
    required this.onOpenCamera,
  });

  final int albumCount;
  final List<String> previewPaths;
  final VoidCallback onOpenAlbum;
  final VoidCallback onOpenCamera;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '为毛孩子记录每一刻',
          style: TextStyle(
            fontSize: 24,
            height: 32 / 24,
            fontWeight: FontWeight.w400,
            color: context.tokens.textPrimary,
          ),
        ),
        const SizedBox(height: AppUi.space12),
        SizedBox(
          height: 160,
          child: Row(
            children: [
              Expanded(
                flex: 278,
                child: _HeroCaptureCard(
                  albumCount: albumCount,
                  previewPaths: previewPaths,
                  onOpenAlbum: onOpenAlbum,
                  onOpenCamera: onOpenCamera,
                ),
              ),
              const SizedBox(width: AppUi.space8),
              const SizedBox(width: 72, child: _HeroQuickActionColumn()),
            ],
          ),
        ),
      ],
    );
  }
}

/// 首页首屏左侧大卡。
/// 主入口保持拍照功能，同时把相册数量和最近缩略图放进同一卡片里。
class _HeroCaptureCard extends StatelessWidget {
  const _HeroCaptureCard({
    required this.albumCount,
    required this.previewPaths,
    required this.onOpenAlbum,
    required this.onOpenCamera,
  });

  final int albumCount;
  final List<String> previewPaths;
  final VoidCallback onOpenAlbum;
  final VoidCallback onOpenCamera;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpenCamera,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFFFEDE2C),
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 80,
              height: 80,
              child: CustomPaint(
                // 描边按设计稿改成从上到下 50% -> 0% 的白色渐变边。
                painter: _VerticalGradientBorderPainter(
                  radius: AppUi.radiusCard,
                  strokeWidth: 1,
                  colors: const <Color>[Color(0x80FFFFFF), Color(0x00FFFFFF)],
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0x33FFFFFF), Color(0x00FFFFFF)],
                    ),
                    borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  ),
                ),
              ),
            ),
            // 顶部拍照入口区按设计稿固定在 20 / 20 位置。
            Positioned(
              left: 20,
              top: 20,
              child: SizedBox(
                width: 232,
                height: 40,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: MingCuteIcon(
                        MingCuteIcons.cameraFill,
                        size: AppUi.iconLarge,
                        color: context.tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppUi.space12),
                    SizedBox(
                      width: 180,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '开始拍照',
                            style: TextStyle(
                              fontSize: AppUi.fontTitle,
                              height: 22 / AppUi.fontTitle,
                              fontWeight: FontWeight.w700,
                              color: context.tokens.textPrimary,
                            ),
                          ),
                          // 说明文案保持单行，超出时按比例缩小，避免最后一个字被裁掉。
                          SizedBox(
                            width: 180,
                            height: 18,
                            child: FittedBox(
                              alignment: Alignment.centerLeft,
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '拍照、相册、写真、短片都在这里',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: AppUi.fontCaption,
                                  height: 18 / AppUi.fontCaption,
                                  fontWeight: FontWeight.w400,
                                  color: context.tokens.textPrimary.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 底部相册区改成左右撑开的弹性布局，宽度跟随黄卡变化。
            Positioned(
              left: 12,
              right: 12,
              top: 92,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpenAlbum,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const thumbSize = 30.0;
                    const thumbGap = AppUi.space8;
                    const arrowWidth = 26.0;

                    // 预留一个箭头位，剩余空间再按缩略图尺寸动态决定显示数量。
                    final availableWidth = constraints.maxWidth;
                    final previewWidth = availableWidth - arrowWidth - thumbGap;
                    final maxPreviewCount = previewPaths.length;
                    final calculatedCount = previewWidth <= 0
                        ? 0
                        : ((previewWidth + thumbGap) / (thumbSize + thumbGap))
                              .floor();
                    final previewCount = calculatedCount < 0
                        ? 0
                        : (calculatedCount > maxPreviewCount
                              ? maxPreviewCount
                              : calculatedCount);
                    final previewItems = previewPaths
                        .take(previewCount)
                        .toList(growable: false);

                    return SizedBox(
                      height: 56,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '相册',
                                style: TextStyle(
                                  fontSize: AppUi.fontCaption,
                                  height: 18 / AppUi.fontCaption,
                                  fontWeight: FontWeight.w400,
                                  color: context.tokens.textPrimary,
                                ),
                              ),
                              const SizedBox(width: AppUi.space8),
                              Text(
                                '$albumCount',
                                style: TextStyle(
                                  fontSize: AppUi.fontCaption,
                                  height: 18 / AppUi.fontCaption,
                                  fontWeight: FontWeight.w400,
                                  color: context.tokens.textPrimary.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppUi.space8),
                          Row(
                            children: [
                              for (final item in previewItems) ...[
                                _HeroPreviewThumb(assetPath: item),
                                const SizedBox(width: thumbGap),
                              ],
                              _HeroAlbumEntry(onTap: onOpenAlbum),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页首屏右侧快捷入口列。
/// 把“毛孩相册”和“快速拍照”移动到右侧竖排位置。
class _HeroQuickActionColumn extends StatelessWidget {
  const _HeroQuickActionColumn();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _HeroQuickActionCard(
            title: '毛孩相册',
            icon: MingCuteIcons.picFill,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFF386FFF), Color(0xFF5EC1FF)],
            ),
            onTap: () => Navigator.pushReplacementNamed(context, '/album'),
          ),
        ),
        const SizedBox(height: AppUi.space8),
        Expanded(
          child: _HeroQuickActionCard(
            title: '快速拍照',
            icon: MingCuteIcons.cameraFill,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFFF383B), Color(0xFFFF7EA9)],
            ),
            onTap: () => Navigator.pushNamed(context, '/camera'),
          ),
        ),
      ],
    );
  }
}

/// 首页黄卡下半层的渐变描边。
/// 这里单独用 Painter 画边，是因为 BoxDecoration 的 border 不支持渐变色。
class _VerticalGradientBorderPainter extends CustomPainter {
  const _VerticalGradientBorderPainter({
    required this.radius,
    required this.strokeWidth,
    required this.colors,
  });

  final double radius;
  final double strokeWidth;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _VerticalGradientBorderPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.colors.first != colors.first ||
        oldDelegate.colors.last != colors.last;
  }
}

/// 首页首屏右侧快捷卡片。
/// 尺寸和文案按设计稿收口，避免页面层重复写渐变和文字样式。
class _HeroQuickActionCard extends StatelessWidget {
  const _HeroQuickActionCard({
    required this.title,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  final String title;
  final String icon;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppUi.radiusCard),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
        ),
        child: Column(
          // 右侧小卡按设计稿改为内容整体居中，不再把标题压到底部。
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: MingCuteIcon(icon, size: 24, color: Colors.white),
            ),
            const SizedBox(height: 0),
            // 右侧小卡标题保持单行并按可用宽度微缩，避免换行和裁剪。
            SizedBox(
              width: 48,
              height: 20,
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: AppUi.fontCaption,
                    height: 20 / AppUi.fontCaption,
                    fontWeight: FontWeight.w400,
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
}

/// 首页首屏相册缩略图。
/// 固定为 30x30 圆角 8，保持和设计稿中的缩略图尺寸一致。
class _HeroPreviewThumb extends StatelessWidget {
  const _HeroPreviewThumb({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(assetPath, width: 30, height: 30, fit: BoxFit.cover),
    );
  }
}

/// 首页首屏相册入口尾项。
/// 使用半透明白底和右箭头，承接查看更多相册的动作。
class _HeroAlbumEntry extends StatelessWidget {
  const _HeroAlbumEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 26,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: MingCuteIcon(
          MingCuteIcons.rightLine,
          size: 20,
          color: const Color(0xFF999999),
        ),
      ),
    );
  }
}

class _PetSnapshotStrip extends StatelessWidget {
  const _PetSnapshotStrip({required this.pets});

  final List<Pet> pets;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      // 顶部宠物展示区改为复用全局首尾留白组件，避免每个横向列表重复手写。
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: AppHorizontalEdgeInset(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PetAddEntry(
                onTap: () => Navigator.pushNamed(context, '/camera'),
              ),
              for (final pet in pets) ...[
                const SizedBox(width: AppUi.space16),
                _PetSnapshotAvatar(pet: pet),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 首页顶部宠物入口，固定使用 64x64 圆形头像和 16 的横向间距。
class _PetAddEntry extends StatelessWidget {
  const _PetAddEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: const Border.fromBorderSide(
                  BorderSide(color: Color(0xFFE2E4E6)),
                ),
              ),
              alignment: Alignment.center,
              child: MingCuteIcon(
                MingCuteIcons.addLine,
                size: AppUi.iconLarge,
                color: context.tokens.textPrimary,
              ),
            ),
            const SizedBox(height: AppUi.space8),
            Text(
              '拍照添加',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppUi.fontCaption,
                height: 16 / AppUi.fontCaption,
                fontWeight: FontWeight.w400,
                color: context.tokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页顶部已存在宠物入口，保持和新增入口一致的尺寸结构。
class _PetSnapshotAvatar extends StatelessWidget {
  const _PetSnapshotAvatar({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        '/album-detail',
        arguments: <String, String>{'petId': pet.id},
      ),
      borderRadius: BorderRadius.circular(32),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0xFFE2E4E6)),
                ),
              ),
              child: ClipOval(
                child: Image.asset(
                  pet.avatarPath,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: AppUi.space4),
            Text(
              pet.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppUi.fontCaption,
                height: 20 / AppUi.fontCaption,
                fontWeight: FontWeight.w400,
                color: context.tokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.titleSize = AppUi.fontTitle,
    this.titleWeight = FontWeight.w400,
    this.trailingLabel,
    this.onTrailingTap,
  });

  final String title;
  final double titleSize;
  final FontWeight titleWeight;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: titleSize,
              height: AppUi.lineHeight(titleSize),
              fontWeight: titleWeight,
              color: context.tokens.textPrimary,
            ),
          ),
        ),
        if (trailingLabel != null && onTrailingTap != null)
          GestureDetector(
            onTap: onTrailingTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trailingLabel!,
                  style: TextStyle(
                    fontSize: AppUi.fontCaption,
                    height: AppUi.lineHeight(AppUi.fontCaption),
                    fontWeight: FontWeight.w400,
                    color: context.tokens.textTertiary,
                  ),
                ),
                const SizedBox(width: 0),
                MingCuteIcon(
                  MingCuteIcons.rightLine,
                  size: AppUi.iconSmall,
                  color: const Color(0xFF999999),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature, required this.onTap});

  final _HomeFeature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppUi.radiusCard),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.pageBackground,
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 上次只改了外层布局，但卡片内部仍被较高的封面比例和单行文本锁住，
            // 看起来还是像固定高度。这里把封面高度收紧一些，并让副标题允许两行，
            // 让灰色背景真正跟着内容变化。
            final coverHeight = (constraints.maxWidth * 116 / 173).clamp(
              96.0,
              116.0,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  // 封面高度跟随卡片宽度按比例变化，这样宽高都能一起弹性变化。
                  height: coverHeight,
                  width: double.infinity,
                  child: _FeatureCover(
                    imagePath: feature.imagePath,
                    videoAssetPath: feature.videoAssetPath,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              feature.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                height: 24 / 16,
                                fontWeight: FontWeight.w400,
                                color: context.tokens.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppUi.space8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 40),
                            height: 20,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEE35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              feature.tag,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 12,
                                height: 18 / 12,
                                fontWeight: FontWeight.w400,
                                color: context.tokens.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppUi.space4),
                      Text(
                        feature.subtitle,
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          fontSize: AppUi.fontCaption,
                          height: 20 / AppUi.fontCaption,
                          color: context.tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 惊喜卡片封面：默认显示静态图；如果有视频资源，就自动静音循环播放。
/// 视频失败时自动回退到封面图，避免首页出现黑屏或空白块。
class _FeatureCover extends StatefulWidget {
  const _FeatureCover({required this.imagePath, this.videoAssetPath});

  final String imagePath;
  final String? videoAssetPath;

  @override
  State<_FeatureCover> createState() => _FeatureCoverState();
}

class _FeatureCoverState extends State<_FeatureCover> {
  VideoPlayerController? _controller;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoAssetPath != null) {
      Future<void>.delayed(const Duration(milliseconds: 200), _startVideo);
    }
  }

  Future<void> _startVideo() async {
    final videoAssetPath = widget.videoAssetPath;
    if (videoAssetPath == null || _videoReady) {
      return;
    }

    try {
      final controller = VideoPlayerController.asset(videoAssetPath);
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoReady = true;
      });
    } catch (_) {
      // 保持静态封面即可，这里不额外抛错打断首页渲染。
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppUi.radiusCard),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            widget.imagePath,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xFFF1F3F5)),
          ),
          if (_videoReady &&
              _controller != null &&
              _controller!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentPhotoStrip extends StatelessWidget {
  const _RecentPhotoStrip({required this.photos, required this.onTapPhoto});

  final List<String> photos;
  final ValueChanged<String> onTapPhoto;

  double _aspectRatio(int index) {
    switch (index % 5) {
      case 0:
        return 0.78;
      case 1:
        return 1.05;
      case 2:
        return 0.88;
      case 3:
        return 1.15;
      default:
        return 0.95;
    }
  }

  @override
  Widget build(BuildContext context) {
    final leftPhotos = <int>[];
    final rightPhotos = <int>[];
    for (var i = 0; i < photos.length; i++) {
      if (i.isEven) {
        leftPhotos.add(i);
      } else {
        rightPhotos.add(i);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _RecentPhotoColumn(
            photos: photos,
            indices: leftPhotos,
            getRatio: _aspectRatio,
            onTapPhoto: onTapPhoto,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RecentPhotoColumn(
            photos: photos,
            indices: rightPhotos,
            getRatio: _aspectRatio,
            onTapPhoto: onTapPhoto,
          ),
        ),
      ],
    );
  }
}

class _RecentPhotoColumn extends StatelessWidget {
  const _RecentPhotoColumn({
    required this.photos,
    required this.indices,
    required this.getRatio,
    required this.onTapPhoto,
  });

  final List<String> photos;
  final List<int> indices;
  final double Function(int) getRatio;
  final ValueChanged<String> onTapPhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final index in indices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RecentPhotoTile(
              assetPath: photos[index],
              aspectRatio: getRatio(index),
              onTap: () => onTapPhoto(photos[index]),
            ),
          ),
      ],
    );
  }
}

class _RecentPhotoTile extends StatelessWidget {
  const _RecentPhotoTile({
    required this.assetPath,
    required this.aspectRatio,
    required this.onTap,
  });

  final String assetPath;
  final double aspectRatio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Image.asset(assetPath, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

/// 首页“毛孩近照”点击后直接在当前页预览，不再跳转到相册页。
class _HomeRecentPhotoDialog extends StatelessWidget {
  const _HomeRecentPhotoDialog({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(assetPath, fit: BoxFit.contain),
      ),
    );
  }
}

class _PrimaryBottomBar extends StatelessWidget {
  const _PrimaryBottomBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 72,
        // 底部导航按 APP / WAP 的固定导航处理，不跟随页面内容区左右留白收窄。
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: _BottomBarItem(
                label: '首页',
                icon: MingCuteIcons.home4Fill,
                active: currentIndex == 0,
                onTap: () => onTap(0),
              ),
            ),
            Expanded(
              child: _BottomBarItem(
                label: null,
                icon: MingCuteIcons.addLine,
                active: false,
                isCenterAction: true,
                onTap: () => onTap(2),
              ),
            ),
            Expanded(
              child: _BottomBarItem(
                label: '相册',
                icon: MingCuteIcons.instagramFill,
                active: currentIndex == 1,
                onTap: () => onTap(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  const _BottomBarItem({
    this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.isCenterAction = false,
  });

  final String? label;
  final String icon;
  final bool active;
  final bool isCenterAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final navColor = active
        ? context.tokens.textPrimary
        : context.tokens.textTertiary;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isCenterAction)
            CirclePlateIcon(
              name: icon,
              plateSize: 44,
              iconSize: 24,
              backgroundColor: context.tokens.brand,
              // 中间主操作只保留黄色圆底和黑色加号，不显示文字。
              iconColor: context.tokens.textPrimary,
            )
          else
            MingCuteIcon(icon, size: AppUi.iconLarge, color: navColor),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              style: TextStyle(
                fontSize: AppUi.fontCaption,
                height: AppUi.lineHeight(AppUi.fontCaption),
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: navColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SecondaryTopBar extends StatelessWidget {
  const _SecondaryTopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppBackButton(onTap: onBack),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppUi.fontTitle,
              height: AppUi.lineHeight(AppUi.fontTitle),
              fontWeight: FontWeight.w700,
              color: context.tokens.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 40, height: 40),
      ],
    );
  }
}

class _MineProfileCard extends StatelessWidget {
  const _MineProfileCard({
    required this.pets,
    required this.photoCount,
    required this.videoCount,
  });

  final List<Pet> pets;
  final int photoCount;
  final int videoCount;

  @override
  Widget build(BuildContext context) {
    final firstPet = pets.isEmpty ? null : pets.first;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
      ),
      constraints: const BoxConstraints(minHeight: 246),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Image.asset(
                    firstPet?.avatarPath ??
                        'assets/seed/photos/yuanbao_headshot.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '元宝家庭',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 28 / 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF000000),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '把每一只毛孩的日常都好好留下来',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 22 / 14,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MineStatItem(
                  label: '宠物',
                  value: '${pets.length}',
                  // 统计图标改成填充款，并使用更贴近 App 调性的柔和配色。
                  icon: MingCuteIcons.pawFill,
                  iconColor: const Color(0xFF5BA8C8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MineStatItem(
                  label: '照片',
                  value: '$photoCount',
                  icon: MingCuteIcons.pic2Fill,
                  iconColor: const Color(0xFFD4826A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MineStatItem(
                  label: '短片',
                  value: '$videoCount',
                  icon: MingCuteIcons.videoFill,
                  iconColor: const Color(0xFF9B8AC4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MineStatItem extends StatelessWidget {
  const _MineStatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final String value;
  final String icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              height: 28 / 20,
              fontWeight: FontWeight.w400,
              color: Color(0xFF000000),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MingCuteIcon(icon, size: 16, color: iconColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  height: 20 / 12,
                  fontWeight: FontWeight.w600,
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

class _MineActionTile extends StatelessWidget {
  const _MineActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppUi.radiusCard),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
        ),
        child: Row(
          children: [
            // 我的页面入口图标统一收口为 20，并保持纯黑。
            MingCuteIcon(icon, size: 20, color: const Color(0xFF000000)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  height: 24 / 16,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF000000),
                ),
              ),
            ),
            MingCuteIcon(
              MingCuteIcons.rightLine,
              size: 20,
              color: const Color(0xFF999999),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeFeature {
  const _HomeFeature({
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.icon,
    required this.imagePath,
    required this.route,
    this.videoAssetPath,
  });

  final String title;
  final String subtitle;
  final String tag;
  final String icon;
  final String imagePath;
  final String route;
  final String? videoAssetPath;
}
