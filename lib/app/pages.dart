import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pet_camera/app/app_image.dart';
import 'package:pet_camera/app/app_generated_result_page.dart';
import 'package:pet_camera/app/app_primary_action_button.dart';
import 'package:pet_camera/app/app_photo_preview_panel.dart';
import 'package:pet_camera/app/app_back_button.dart';
import 'package:pet_camera/app/app_loading_view.dart';
import 'package:pet_camera/app/app_top_nav_bar.dart';
import 'package:pet_camera/app/beian_footer.dart';
import 'package:pet_camera/app/media_platform.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/ai_portrait_service.dart';
import 'package:pet_camera/data/captured_photos.dart';
import 'package:pet_camera/data/short_videos.dart';
import 'package:pet_camera/data/app_settings.dart';
import 'package:pet_camera/data/models.dart';
import 'package:pet_camera/data/seed_config.dart';
import 'package:pet_camera/data/seed_repository.dart';
import 'package:pet_camera/data/growth_records.dart';
import 'package:pet_camera/data/library_service.dart';

/// 统一页面外壳：二级页顶栏统一提供返回入口。
class _Shell extends StatelessWidget {
  const _Shell({
    required this.title,
    required this.body,
    this.backgroundColor,
    this.appBarBackgroundColor,
    this.bottomBar,
  });

  final String title;
  final Widget body;
  final Color? backgroundColor;
  final Color? appBarBackgroundColor;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
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
            ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
          },
        ),
        centerTitle: true,
        title: Text(
          title,
          style: TextStyle(
            fontSize: AppUi.fontTitle,
            height: AppUi.lineHeight(AppUi.fontTitle),
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: appBarBackgroundColor ?? t.surface,
        foregroundColor: t.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      backgroundColor: backgroundColor ?? t.bgBase,
      body: body,
      bottomNavigationBar: bottomBar,
    );
  }
}

/// 启动/首页——Facebook Snapshot 布局 + Tests App 马卡龙配色。
/// 布局参考：Facebook 顶栏(图标+粗体标题+操作按钮) + Snapshot 彩色横滑卡 + 内容卡片区。
/// 配色参考：Tests App 马卡龙色系（薰衣草紫/薄荷蓝/蜜桃粉/奶油黄）。
/// 关键修复：功能卡片改为 2 列 + 增加高度占比，确保功能介绍文字完整显示。
/// 禁 emoji、禁紫粉渐变，全 Lucide 图标。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _currentNav = 0;

  void _onNavTap(int index) {
    if (index == _currentNav) return;
    setState(() => _currentNav = index);
    switch (index) {
      case 1:
        Navigator.pushNamed(context, '/album');
        break;
      case 2:
        Navigator.pushNamed(context, '/camera');
        break;
      case 3:
        Navigator.pushNamed(context, '/pet-profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          // 主内容区
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== 顶部栏：Facebook 风格（图标 + 粗体标题 + 操作按钮） =====
                  _buildTopBar(),
                  const SizedBox(height: 8),

                  // ===== Snapshot 横滑区（彩色底卡片 + 宠物照 + 名字标签） =====
                  _buildSnapshotSection(),
                  const SizedBox(height: 16),

                  // ===== Hero 横幅卡（薰衣草紫底 + CTA） =====
                  _HeroBannerCard(),
                  const SizedBox(height: 12),

                  // ===== 功能卡片网格（2列 + 足够高度显示完整文字） =====
                  _SectionHeader(
                    iconName: MingCuteIcons.sparkles,
                    title: '更多惊喜',
                    colorBlue: false,
                  ),
                  const SizedBox(height: 12),
                  _FeatureGridSection(),
                  const SizedBox(height: 16),

                  // ===== 最近照片横滑 =====
                  _SectionHeader(
                    iconName: MingCuteIcons.photoAlbum,
                    title: '毛孩近照',
                    colorBlue: true,
                  ),
                  const SizedBox(height: 12),
                  _RecentPhotosRow(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // 底部导航栏（居中 FAB）
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _InsBottomNav(currentIndex: _currentNav, onTap: _onNavTap),
          ),
        ],
      ),
    );
  }

  /// Facebook 风格顶栏：左侧相机图标 + 粗体大标题 + 右侧操作按钮
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 左侧：相机图标
          // ★ 左侧：相机图标按钮（点击打开相机拍照）
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pushNamed(context, '/camera'),
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                ),
                child: const Center(
                  child: MingCuteIcon(
                    MingCuteIcons.camera,
                    size: AppUi.iconMedium,
                    color: Color(0xFF2B2622),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 中间：粗体标题（Facebook 风格左对齐）
          const Text(
            '元宝拍拍',
            style: TextStyle(
              fontSize: AppUi.fontHeadline,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2B2622),
              letterSpacing: -0.5,
            ),
          ),

          const Spacer(),

          // 右侧：添加/设置按钮
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/settings'),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
              ),
              child: const Center(
                // 这里实际跳转的是设置页，图标统一用 MingCute 设置图标。
                child: MingCuteIcon(
                  MingCuteIcons.settings2Line,
                  size: AppUi.iconMedium,
                  color: Color(0xFF2B2622),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Snapshot 横滑区（参考 Facebook Snapshot：彩色底卡片 + 照片 + 底部名字标签）
  Widget _buildSnapshotSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 横滑彩色卡片（每张不同马卡龙底色）
        SizedBox(
          height: 140,
          child: ScrollConfiguration(
            behavior: _DragScrollBehavior(),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: 4, // ★ 4只核心毛孩（删了全家福+最新照片）
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _SnapshotCard(index: i),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Facebook Snapshot 风格 + 马卡龙配色 子组件
// ═══════════════════════════════════════════════════════════════

/// Snapshot 彩色横滑卡片（参考 Facebook Snapshot：马卡龙底色 + 宠物照 + 底部名字标签）
class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.index});
  final int index;

  // 每张卡片不同马卡龙底色 + 对应宠物照片 + 图片对齐偏移（猫脸聚焦）
  // ★ 只保留4只核心毛孩，删掉"全家福""最新照片"（主次分明）
  static const _cardColors = [
    (
      bg: Color(0xFFF5E6FA),
      name: '金元宝',
      petId: 'yuanbao',
      photo: 'yuanbao_headshot.png',
      align: Alignment(0.0, -0.2),
    ), // 头像居中偏上
    (
      bg: Color(0xFFD6EEF5),
      name: '小棉花',
      petId: 'xiaomianhua',
      photo: 'xiaomianhua_005.jpg',
      align: Alignment(0.0, -0.45),
    ), // ★ 猫脸放大：强力上移聚焦脸部
    (
      bg: Color(0xFFFFE4DD),
      name: '小汤圆',
      petId: 'xiaotangyuan',
      photo: 'xiaotangyuan_008.jpg',
      align: Alignment(0.0, -0.65),
    ), // ★ 猫脸在照片上25%，需负值下移
    (
      bg: Color(0xFFE8F0E0),
      name: '猫友圈',
      petId: 'friends',
      photo: 'friend_007.jpg',
      align: Alignment(0.0, -0.2),
    ), // 跳转元宝的朋友们
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _cardColors[index % _cardColors.length];

    return GestureDetector(
      onTap: () {
        if (colors.petId.isNotEmpty) {
          Navigator.pushNamed(
            context,
            '/album',
            arguments: {'petId': colors.petId},
          );
        } else {
          Navigator.pushNamed(context, '/album');
        }
      },
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 宠物照片（每只毛孩用自己的！）
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              bottom: 28,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                child: AppImage(
                  url: SeedConfig.photoUrl(colors.photo),
                  fit: BoxFit.cover,
                  alignment: colors.align,
                ),
              ),
            ),
            // 底部名字标签（参考 Facebook 的 Vanetic / Bestiolos 标签）
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: Text(
                colors.name,
                style: const TextStyle(
                  fontSize: AppUi.fontBody,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4A4540),
                ),
              ),
            ),
            // ★ 右上角相机图标按钮（点击打开相机，照片存入对应毛孩相册）
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/camera',
                    arguments: {'petName': colors.name},
                  ),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    child: const Center(
                      child: MingCuteIcon(
                        MingCuteIcons.camera,
                        size: AppUi.iconSmall,
                        color: Colors.white,
                      ),
                    ),
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

/// 分区标题（图标 + 文字，马卡龙配色：柔蓝 / 柔紫交替）
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.iconName,
    required this.title,
    this.colorBlue = true,
  });
  final String iconName;
  final String title;

  /// true=柔蓝(参考 Explore), false=柔紫(参考 Discover/Collections)
  final bool colorBlue;

  @override
  Widget build(BuildContext context) {
    // 马卡龙双色：柔蓝 / 柔紫
    final iconBg = colorBlue
        ? const Color(0xFFDCE6F5) // 柔蓝
        : const Color(0xFFE8E0F0); // 柔紫
    final iconColor = colorBlue
        ? const Color(0xFF6B8FC4) // 柔蓝深
        : const Color(0xFF9B8AC4); // 薰衣草紫
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: MingCuteIcon(
                iconName,
                size: AppUi.iconMedium,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: AppUi.fontTitle,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2B2622),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero 横幅卡（马卡龙薰衣草紫底 + 插画 + 紫色CTA，参考 "Look inside yourself"）
class _HeroBannerCard extends StatelessWidget {
  // 马卡龙薰衣草紫渐变（参考 Tests App 的淡紫 Hero 卡）
  static const _heroGradient = LinearGradient(
    colors: [Color(0xFFF0EBFA), Color(0xFFE6DDF5), Color(0xFFDDD2EE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, '/camera'),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              gradient: _heroGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                // 左侧文字 + 按钮
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '为毛孩子记录每一刻',
                        style: const TextStyle(
                          fontSize: AppUi.fontTitle,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2B2622),
                        ).copyWith(height: AppUi.lineHeight(AppUi.fontTitle)),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '毛孩写真 · 毛孩相册 · 一键成片',
                        style: TextStyle(
                          fontSize: AppUi.fontCaption,
                          color: Color(0xFF8A7FA8), // 薰衣草灰紫
                        ),
                      ),
                      const SizedBox(height: 8),
                      // CTA 胶囊按钮（柔紫蓝，参考 Try it 按钮）
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA694C8), // 马卡龙柔紫
                          borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '开始拍照',
                          style: TextStyle(
                            fontSize: AppUi.fontCaption,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // 右侧宠物照片
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  child: AppImage(
                    url: SeedConfig.photoUrl('yuanbao_headshot.png'),
                    fit: BoxFit.cover,
                    width: 72,
                    height: 72,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 功能卡片数据（照片和功能语义匹配 + 各宠物混合展示）
/// 封面图走远程（SeedConfig），示例视频仍随包分发。
final _featureCards = [
  _FeatCardData(
    iconName: MingCuteIcons.magic2,
    title: '毛孩写真',
    desc: 'AI生成油画、插画等多种艺术风格肖像。',
    tag: 'AI 驱动',
    imageUrl: SeedConfig.photoUrl('feat_portrait.jpg'), // ★ 金元宝9宫格写真
    route: '/portrait',
    align: Alignment(0.0, -0.1), // 写真构图居中
  ),
  _FeatCardData(
    iconName: MingCuteIcons.photoAlbum,
    title: '毛孩相册',
    desc: '自动按宠物归类，瀑布流浏览所有照片。',
    tag: '201 张照片',
    imageUrl: SeedConfig.photoUrl('feat_album.jpg'), // ★ 春春江江4小奶猫
    route: '/album',
    align: Alignment(0.0, -0.3),
  ),
  _FeatCardData(
    iconName: MingCuteIcons.videoLine,
    title: '一键成片',
    desc: '一张照片让毛孩动起来，AI 生成短视频。',
    tag: 'AI 视频',
    imageUrl: SeedConfig.photoUrl('feat_video_thumb.jpg'), // ★ 视频缩略图
    videoAssetPath:
        'assets/seed/photos/feat_video_compressed.mp4', // ★ 压缩版(0.82MB,云端秒加载)
    route: '/ai-video',
    align: Alignment(0.5, 0.15), // ★ 焦点下移（避免顶部杯子/空白过多）
  ),
  _FeatCardData(
    iconName: MingCuteIcons.palette,
    title: '毛孩美颜',
    desc: '智能抠图换背景，叠加海量趣味贴纸。',
    tag: '已上线',
    imageUrl: SeedConfig.photoUrl('feat_retouch.jpg'), // ★ 布偶猫蓝眼睛(木头)
    route: '/retouch',
    align: Alignment(0.0, -0.25),
  ),
  _FeatCardData(
    iconName: MingCuteIcons.book,
    title: '成长手记',
    desc: '记录体重、疫苗、趣事与每个成长细节。',
    tag: '4 只宠物',
    imageUrl: SeedConfig.photoUrl('feat_profile.jpg'), // ★ 兽医体检
    route: '/pet-profile',
    align: Alignment(0.0, -0.2),
  ),
  _FeatCardData(
    iconName: MingCuteIcons.camera,
    title: '灵动快门',
    desc: '全屏取景+防抖算法，精准抓拍灵动瞬间。',
    tag: '已接入',
    imageUrl: SeedConfig.photoUrl('feat_camera.jpg'), // ★ 戴圈金毛(小凳子)
    route: '/camera',
    align: Alignment(0.0, -0.15),
  ),
];

/// 功能卡片数据模型
class _FeatCardData {
  const _FeatCardData({
    required this.iconName,
    required this.title,
    required this.desc,
    required this.tag,
    required this.imageUrl,
    required this.route,
    this.align = const Alignment(0.0, -0.2), // 默认偏上保猫脸
    this.videoAssetPath, // 视频资源路径（非空时显示播放按钮）
  });
  final String iconName;
  final String title;
  final String desc;
  final String tag;
  final String imageUrl;
  final String route;
  final Alignment align; // 每张卡片独立的 cover 焦点
  final String? videoAssetPath; // 视频资源路径
}

/// 功能卡片网格区（**纯 3列×2行** + 首卡视觉突出 = 主次分明）
class _FeatureGridSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, // ★ 3列
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.80, // 更高=更矮卡片，节省纵向空间
        ),
        itemCount: _featureCards.length, // 6张 = 2行
        itemBuilder: (context, i) =>
            _FeatCard(data: _featureCards[i], isFeatured: i == 0),
      ),
    );
  }
}

/// 单张功能卡片（统一结构 + 首卡 isFeatured 加粗视觉）
/// 视频卡用 StatefulWidget 驱动 auto-play loop；其余仍为轻量 StatelessWidget。
class _FeatCard extends StatelessWidget {
  const _FeatCard({required this.data, this.isFeatured = false});
  final _FeatCardData data;
  final bool isFeatured;

  @override
  Widget build(BuildContext context) {
    // ★ 视频卡片 → 用有状态组件实现自动播放
    if (data.videoAssetPath != null) {
      return _AutoPlayVideoCard(data: data, isFeatured: isFeatured);
    }
    return _ImageFeatCard(data: data, isFeatured: isFeatured);
  }
}

// ─── 纯图片卡片（无视频，保持轻量 StatelessWidget）───────────────
class _ImageFeatCard extends StatelessWidget {
  const _ImageFeatCard({required this.data, this.isFeatured = false});
  final _FeatCardData data;
  final bool isFeatured;

  static const _macaronColors = [
    (bg: Color(0xFFE8E0F6), icon: Color(0xFF9B8AC4)), // 薰衣草 ← 首卡用
    (bg: Color(0xFFD6EEF5), icon: Color(0xFF5BA8C8)), // 薄荷蓝
    (bg: Color(0xFFFFE4DD), icon: Color(0xFFD4826A)), // 蜜桃
    (bg: Color(0xFFE0F0E0), icon: Color(0xFF6AAA7A)), // 薄荷绿
    (bg: Color(0xFFF5E6FA), icon: Color(0xFFB08AC4)), // 淡粉紫
    (bg: Color(0xFFF5F0E0), icon: Color(0xFFC4A86A)), // 奶油黄
  ];

  @override
  Widget build(BuildContext context) {
    final colors =
        _macaronColors[_featureCards.indexOf(data) % _macaronColors.length];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, data.route),
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppUi.radiusCard),
            border: isFeatured
                ? Border.all(
                    color: const Color(0xFF9B8AC4).withValues(alpha: 0.45),
                    width: 1.8,
                  )
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 55,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AppImage(
                        url: data.imageUrl,
                        fit: BoxFit.cover,
                        alignment: data.align,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colors.bg,
                          shape: BoxShape.circle,
                          border: isFeatured
                              ? Border.all(
                                  color: colors.icon.withValues(alpha: 0.3),
                                  width: 1.5,
                                )
                              : null,
                        ),
                        child: MingCuteIcon(
                          data.iconName,
                          size: isFeatured ? 16 : 14,
                          color: colors.icon,
                        ),
                      ),
                    ),
                    if (isFeatured)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF9B8AC4,
                            ).withValues(alpha: 0.90),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '推荐',
                            style: TextStyle(
                              fontSize: AppUi.fontCaption,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          data.title,
                          style: TextStyle(
                            fontSize: isFeatured ? 14 : 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2D2D2D),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.bg.withValues(alpha: 0.60),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            data.tag,
                            style: TextStyle(
                              fontSize: AppUi.fontCaption,
                              fontWeight: FontWeight.w700,
                              color: colors.icon,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppUi.fontCaption,
                        height: AppUi.lineHeight(AppUi.fontCaption),
                        color: const Color(0xFF888888),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 视频自动播放卡片（video_player + 缩略图兜底）───────────────
// 核心策略：缩略图 Image.asset 始终渲染为底层（保证永不空白），
// VideoPlayer 初始化成功后叠加在上方。即使 video_player 失败，用户仍看到首帧图。
class _AutoPlayVideoCard extends StatefulWidget {
  const _AutoPlayVideoCard({required this.data, this.isFeatured = false});
  final _FeatCardData data;
  final bool isFeatured;

  @override
  State<_AutoPlayVideoCard> createState() => _AutoPlayVideoCardState();
}

class _AutoPlayVideoCardState extends State<_AutoPlayVideoCard> {
  VideoPlayerController? _controller;

  /// 视频是否已初始化成功并可播放
  bool _videoReady = false;

  /// 用户已点击播放，正在加载中（显示 loading 指示器）
  bool _isLoading = false;

  static const _macaronColors = [
    (bg: Color(0xFFD6EEF5), icon: Color(0xFF5BA8C8)),
  ];

  @override
  void initState() {
    super.initState();
    // ★ 恢复首页自动播放：视频已压缩到 0.82MB（原 15.5MB），云端可秒加载。
    //   延迟 300ms 让底层缩略图先稳定渲染，避免首帧闪烁；加载成功后自动覆盖播放。
    //   失败则回落到播放按钮（用户可点击重试），永不出现暗色/VIDEO/白屏。
    Future.delayed(const Duration(milliseconds: 300), _startVideo);
  }

  /// 用户点击播放按钮 → 开始加载视频
  Future<void> _startVideo() async {
    if (_videoReady || _isLoading) return;
    setState(() => _isLoading = true);

    try {
      _controller?.dispose();
    } catch (_) {}
    _controller = null;

    try {
      final assetKey = widget.data.videoAssetPath!;
      final webAssetPath = 'assets/$assetKey';
      final videoUrl = Uri.base.resolve(webAssetPath);

      final c = VideoPlayerController.networkUrl(videoUrl);
      _controller = c;
      await c.initialize(); // 这里会等待视频下载+解码，云端可能需要 5-20 秒
      if (!mounted) {
        c.dispose();
        return;
      }
      c.setLooping(true);
      c.setVolume(0);
      c.play();
      if (mounted)
        setState(() {
          _videoReady = true;
          _isLoading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      // 失败：回到缩略图+播放按钮状态，用户可再点重试
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _macaronColors[0];
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ★ 视频/图片区：底层缩略图 + 上层 VideoPlayer（就绪时）+ 播放按钮/loading（未就绪时）
            Expanded(
              flex: 55,
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                child: GestureDetector(
                  onTap: _videoReady
                      ? () => Navigator.pushNamed(context, widget.data.route)
                      : _startVideo,
                  behavior: HitTestBehavior.opaque,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // === 底层：静态缩略图（始终渲染，永不空白/暗/VIDEO）===
                      AppImage(
                        url: widget.data.imageUrl,
                        fit: BoxFit.cover,
                        alignment: widget.data.align,
                      ),
                      // === 上层：VideoPlayer（就绪后直接覆盖）===
                      if (_videoReady &&
                          _controller != null &&
                          _controller!.value.isInitialized)
                        FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          alignment: widget.data.align,
                          child: SizedBox(
                            width: _controller!.value.size.width > 0
                                ? _controller!.value.size.width
                                : 1280,
                            height: _controller!.value.size.height > 0
                                ? _controller!.value.size.height
                                : 720,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                      // === Loading 指示器：点击后加载中 ===
                      if (_isLoading && !_videoReady)
                        Center(
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.50),
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // === 播放按钮：未加载时显示（白边+半透明底）===
                      if (!_videoReady && !_isLoading)
                        Center(
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.40),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.80),
                                width: 2.5,
                              ),
                            ),
                            child: const MingCuteIcon(
                              MingCuteIcons.play,
                              size: AppUi.iconMedium,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      // 右上角图标标签
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colors.bg,
                            shape: BoxShape.circle,
                          ),
                          child: MingCuteIcon(
                            widget.data.iconName,
                            size: AppUi.iconSmall,
                            color: colors.icon,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 文字区（点击导航到详情页）
            InkWell(
              onTap: () => Navigator.pushNamed(context, widget.data.route),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.data.title,
                          style: const TextStyle(
                            fontSize: AppUi.fontBody,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2D2D2D),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.bg.withValues(alpha: 0.60),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.data.tag,
                            style: TextStyle(
                              fontSize: AppUi.fontCaption,
                              fontWeight: FontWeight.w700,
                              color: colors.icon,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.data.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppUi.fontCaption,
                        color: Color(0xFF888888),
                      ).copyWith(height: AppUi.lineHeight(AppUi.fontCaption)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 毛孩近照 —— Pinterest 双行瀑布流（**等高 + 宽度随照片真实比例 + 完整显示不裁切**）
class _RecentPhotosRow extends StatelessWidget {
  // 上排 15 张（前 5 张为本次新增照片，首页优先展示）
  static const _topRow = [
    'yuanbao_2157.jpg',
    'yuanbao_2158.jpg',
    'yuanbao_2161.jpg', // 2026-08-09 新增金元宝近照
    'yuanbao_141.jpg',
    'yuanbao_140.jpg',
    'xiaotangyuan_026.jpg',
    'xiaomianhua_021.jpg',
    'yuanbao_123.jpg',
    'yuanbao_098.jpg',
    'xiaomianhua_005.jpg',
    'xiaotangyuan_008.jpg',
    'friend_007.jpg',
    'yuanbao_090.jpg',
    'xiaomianhua_010.jpg',
    'friend_020.jpg',
    'yuanbao_050.jpg',
    'xiaotangyuan_014.jpg',
    'friend_030.jpg', 'xiaomianhua_015.jpg', 'yuanbao_085.jpg',
  ];
  // 下排 15 张
  static const _bottomRow = [
    'yuanbao_075.jpg',
    'yuanbao_100.jpg',
    'xiaomianhua_002.jpg',
    'yuanbao_065.jpg',
    'friend_015.jpg',
    'yuanbao_095.jpg',
    'xiaotangyuan_010.jpg',
    'friend_025.jpg',
    'yuanbao_088.jpg',
    'xiaomianhua_008.jpg',
    'xiaotangyuan_016.jpg',
    'friend_035.jpg',
    'xiaomianhua_012.jpg',
    'yuanbao_078.jpg',
    'xiaotangyuan_003.jpg',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PhotoStrip(photos: _topRow),
        const SizedBox(height: 8), // 两排间距
        _PhotoStrip(photos: _bottomRow),
      ],
    );
  }
}

/// 单行照片横滑（等高 175px，照片宽度随自身比例变化）
class _PhotoStrip extends StatelessWidget {
  final List<String> photos;
  const _PhotoStrip({required this.photos});
  static const double _rowH = 175;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowH,
      child: ScrollConfiguration(
        behavior: _DragScrollBehavior(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: photos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) =>
              _MasonryPhotoTile(url: SeedConfig.photoUrl(photos[i])),
        ),
      ),
    );
  }
}

/// Pinterest 风格照片卡片 —— **等高 + 宽度跟随照片真实比例 + fitHeight 不裁切**
class _MasonryPhotoTile extends StatelessWidget {
  const _MasonryPhotoTile({required this.url});
  final String url;
  static const double _h = 175;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/album'),
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        child: Container(
          height: _h, // ★ 等高：每行都是 175px
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppUi.radiusCard),
            color: const Color(0xFFF8F6F3),
          ),
          clipBehavior: Clip.antiAlias,
          // ★ width 不固定 → 由 fitHeight 按照片真实比例算出，宽窄自然错落
          child: AppImage(
            url: url,
            fit: BoxFit.fitHeight,
            height: _h,
            memCacheWidth: 400,
          ),
        ),
      ),
    );
  }
}

/// 底部导航栏（马卡龙风格：居中橙色 FAB + 四角导航，活跃项柔紫）
class _InsBottomNav extends StatelessWidget {
  const _InsBottomNav({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 左侧：首页
              _NavItem(
                iconName: MingCuteIcons.home1,
                label: '首页',
                active: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              // 相册
              _NavItem(
                iconName: MingCuteIcons.photoAlbum,
                label: '相册',
                active: currentIndex == 1,
                onTap: () => onTap(1),
              ),

              // 居中 FAB（橙色凸起——参考 Tests App 的橙色 + 号，唯一暖色点缀）
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => onTap(2),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA950), // 马卡龙橙（参考截图的 + 按钮）
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: MingCuteIcon(
                      MingCuteIcons.camera,
                      size: AppUi.iconMedium,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 右侧：我的
              _NavItem(
                iconName: MingCuteIcons.user1,
                label: '我的',
                active: currentIndex == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个导航项（马卡龙：活跃=薰衣草紫，非活跃=灰）
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.iconName,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String iconName;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 活跃色用薰衣草紫（参考 Tests 的粉色高亮 "Tests" tab）
    final color = active ? const Color(0xFFA694C8) : const Color(0xFFB0ABA6);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        child: SizedBox(
          width: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              MingCuteIcon(iconName, size: AppUi.iconMedium, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppUi.fontCaption,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DragScrollBehavior extends ScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  };
}

/// 宠物相机页——全屏沉浸式取景框 + 快门 + 闪光灯 + 模式切换。
/// Web 端用模拟预览（真实相机在 Android 端接入 camera 插件）。
class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key});
  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

/// 切片2：真实相机取景框 + 快门拍照 + 存入应用内相册。
/// Web 端使用 camera_web（getUserMedia，需 localhost/https 授权）；Android 端原生相机。
class _CameraPageState extends ConsumerState<CameraPage> {
  static const Duration _cameraInitTimeout = Duration(seconds: 10);
  // UI 按常见相机文案展示 4:3 / 16:9，内部仍按竖屏预览比例计算。
  static const List<String> _photoRatioLabels = ['原图', '1:1', '4:3', '16:9'];
  static const List<double?> _photoRatioValues = [null, 1.0, 3 / 4, 9 / 16];
  List<CameraDescription> _cameras = <CameraDescription>[];
  CameraController? _controller;
  bool _isInitialized = false;
  String? _error;
  bool _flashOn = false;
  int _cameraIndex = 0;
  int _modeIndex = 0; // 0=拍照 1=视频 2=宠物
  bool _showPetGuide = true; // 宠物模式下默认显示取景辅助框
  int _photoRatioIndex = 0; // 0=原图 1=1:1 2=3:4 3=9:16
  bool _showGridGuide = false; // 参考线使用经典 3x3 构图线
  static const _modes = ['拍照', '视频', '宠物'];
  bool _captured = false;
  Uint8List? _lastBytes;
  bool _recording = false; // 视频录制进行中
  bool _audioUnsupported = false; // 本设备/浏览器不支持录制音频，已降级无声

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras().timeout(_cameraInitTimeout);
      if (_cameras.isEmpty) {
        setState(() => _error = '未检测到可用摄像头');
        return;
      }
      _cameraIndex = _findCameraIndex(CameraLensDirection.back);
      await _setupController(_cameras[_cameraIndex]);
    } on TimeoutException {
      setState(() => _error = '相机加载超时，请检查浏览器相机权限后重试');
    } catch (e) {
      setState(() => _error = '相机启动失败：$e');
    }
  }

  Future<void> _setupController(
    CameraDescription desc, {
    bool enableAudio = false,
  }) async {
    final previousController = _controller;
    _recording = false;
    CameraController? c;
    try {
      c = CameraController(
        desc,
        ResolutionPreset.medium,
        enableAudio: enableAudio,
      );
      await c.initialize().timeout(_cameraInitTimeout);
      if (_flashOn) {
        try {
          await c.setFlashMode(FlashMode.torch);
        } catch (_) {}
      }
    } catch (e) {
      if (enableAudio) {
        // 部分浏览器/设备 getUserMedia 不支持音频轨，降级为无声视频录制
        try {
          c = CameraController(
            desc,
            ResolutionPreset.medium,
            enableAudio: false,
          );
          await c.initialize().timeout(_cameraInitTimeout);
          if (_flashOn) {
            try {
              await c.setFlashMode(FlashMode.torch);
            } catch (_) {}
          }
          _audioUnsupported = true;
        } catch (e2) {
          if (mounted) {
            setState(
              () => _error = e2 is TimeoutException
                  ? '相机加载超时，请检查浏览器相机权限后重试'
                  : '相机启动失败：$e2',
            );
          }
          return;
        }
      } else {
        if (mounted) {
          setState(
            () => _error = e is TimeoutException
                ? '相机加载超时，请检查浏览器相机权限后重试'
                : '相机启动失败：$e',
          );
        }
        return;
      }
    }
    _controller = c;
    previousController?.dispose();
    if (mounted) setState(() => _isInitialized = true);
  }

  /// 根据镜头方向找到最合适的摄像头。
  int _findCameraIndex(CameraLensDirection direction) {
    final preferredIndex = _cameras.indexWhere(
      (camera) => camera.lensDirection == direction,
    );
    if (preferredIndex >= 0) return preferredIndex;
    final backIndex = _cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    if (backIndex >= 0) return backIndex;
    return 0;
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isInitialized) return;
    _flashOn = !_flashOn;
    try {
      await _controller!.setFlashMode(
        _flashOn ? FlashMode.torch : FlashMode.off,
      );
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _switchLens() async {
    if (_cameras.length < 2 || _recording) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _setupController(
      _cameras[_cameraIndex],
      enableAudio: _modeIndex == 1,
    );
  }

  void _cyclePhotoRatio() {
    setState(() {
      _photoRatioIndex = (_photoRatioIndex + 1) % _photoRatioLabels.length;
    });
  }

  Future<void> _capture() async {
    if (_controller == null || !_isInitialized) return;
    if (_modeIndex == 1) {
      await _toggleRecording();
      return;
    }
    await _takePicture();
  }

  /// 拍照并在保存前按设置的比例生成最终成片。
  /// 比例外区域补纯黑，避免直接裁掉原图内容。
  Future<void> _takePicture() async {
    if (_controller == null || !_isInitialized) return;
    try {
      final x = await _controller!.takePicture();
      final rawBytes = await x.readAsBytes();
      final bytes = await _composePhotoToSelectedRatio(rawBytes);
      // 本地即时展示。
      ref.read(capturedPhotosProvider.notifier).add(bytes);
      // 异步上传 COS 并登记 works.json（失败不阻断拍摄流程）。
      unawaited(() async {
        try {
          await ref
              .read(worksProvider.notifier)
              .add(
                bytes: bytes,
                type: LibraryType.capturedPhoto,
                ext: 'jpg',
                label: '拍摄照片',
              );
        } catch (e) {
          debugPrint('[拍照] 上传 COS 失败：$e');
        }
      }());
      setState(() {
        _captured = true;
        _lastBytes = bytes;
      });
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) setState(() => _captured = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拍照失败：$e')));
      }
    }
  }

  /// 按当前照片比例输出带黑边的成片。
  /// 这里保留原图完整内容，只在比例外补纯黑区域。
  Future<Uint8List> _composePhotoToSelectedRatio(Uint8List bytes) async {
    final targetRatio = _photoRatioValues[_photoRatioIndex];
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final sourceWidth = image.width.toDouble();
      final sourceHeight = image.height.toDouble();
      if (targetRatio == null) return bytes;

      // 按用户要求：目标宽高由原图宽或高的最大值来定。
      final maxSide = math.max(sourceWidth, sourceHeight);
      late final int outputWidth;
      late final int outputHeight;
      if (targetRatio >= 1) {
        outputWidth = maxSide.round();
        outputHeight = (maxSide / targetRatio).round();
      } else {
        outputHeight = maxSide.round();
        outputWidth = (maxSide * targetRatio).round();
      }

      // 使用 contain 方式完整放下原图，剩余区域用纯黑补齐。
      final scale = math.min(
        outputWidth / sourceWidth,
        outputHeight / sourceHeight,
      );
      final drawWidth = sourceWidth * scale;
      final drawHeight = sourceHeight * scale;
      final offsetX = (outputWidth - drawWidth) / 2;
      final offsetY = (outputHeight - drawHeight) / 2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        Paint()..color = const Color(0xFF000000),
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
        Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight),
        Paint(),
      );
      final picture = recorder.endRecording();
      final outputImage = await picture.toImage(outputWidth, outputHeight);
      final byteData = await outputImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List() ?? bytes;
    } catch (_) {
      return bytes;
    }
  }

  /// 视频模式：开始/停止录制。停止后把视频字节存入短片库，可在「一键成片」加字幕配乐。
  Future<void> _toggleRecording() async {
    if (_controller == null || !_isInitialized) return;
    if (_recording) {
      // 停止录制
      try {
        final x = await _controller!.stopVideoRecording();
        final bytes = await x.readAsBytes();
        ref
            .read(shortVideosProvider.notifier)
            .add(
              ShortVideoEdit(
                videoBytes: bytes,
                // camera_web 录制为 webm（iPhone Safari 同为 Web 端）
                mimeType: 'video/webm',
                trimStartMs: 0,
                trimEndMs: 0,
                caption: '',
                captionStyle: 0,
              ),
            );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('视频已存入短片库')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('停止录制失败：$e')));
        }
      } finally {
        if (mounted) setState(() => _recording = false);
      }
      return;
    }
    // 开始录制
    try {
      await _controller!.startVideoRecording();
      if (mounted) setState(() => _recording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('开始录制失败：$e')));
      }
    }
  }

  /// 切换拍照/视频/宠物模式；进入视频模式时重建控制器以开启音频轨。
  Future<void> _switchMode(int i) async {
    if (i == _modeIndex || _recording || _cameras.isEmpty) return;
    setState(() {
      _modeIndex = i;
      _audioUnsupported = false;
    });
    await _setupController(_cameras[_cameraIndex], enableAudio: i == 1);
  }

  void _showCameraSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            void refreshSheet(void Function() action) {
              setState(action);
              sheetSetState(() {});
            }

            Future<void> refreshSheetAsync(
              Future<void> Function() action,
            ) async {
              await action();
              if (!mounted) return;
              sheetSetState(() {});
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  // 相机设置弹窗改成内容自适应高度，避免继续撑满整屏。
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E4E6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '相机设置',
                        style: TextStyle(
                          fontSize: 20,
                          height: 28 / 20,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF000000),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _CameraSettingSection(
                        title: '拍摄参数',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final itemWidth =
                                    (constraints.maxWidth - 8) / 2;
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: List.generate(
                                    _photoRatioLabels.length,
                                    (index) => _CameraChoiceChip(
                                      label: _photoRatioLabels[index],
                                      width: itemWidth,
                                      selected: index == _photoRatioIndex,
                                      onTap: () => refreshSheet(
                                        () => _photoRatioIndex = index,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            _CameraSwitchTile(
                              title: '闪光灯',
                              value: _flashOn ? '开启' : '关闭',
                              onTap: () => refreshSheetAsync(_toggleFlash),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _CameraSettingSection(
                        title: '辅助功能',
                        child: Column(
                          children: [
                            _CameraSwitchTile(
                              title: '参考线',
                              value: _showGridGuide ? '显示' : '隐藏',
                              onTap: () => refreshSheet(
                                () => _showGridGuide = !_showGridGuide,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _CameraSwitchTile(
                              title: '宠物取景框',
                              value: _showPetGuide ? '显示' : '隐藏',
                              onTap: () => refreshSheet(
                                () => _showPetGuide = !_showPetGuide,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPreview()),
          if (_isInitialized) Positioned.fill(child: _buildCameraGuides()),
          if (_captured) Positioned.fill(child: Container(color: Colors.white)),
          if (_recording)
            Positioned(
              top: 72,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF3B30),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _audioUnsupported ? '录制中（无声）' : '录制中',
                        style: TextStyle(
                          fontSize: AppUi.fontBody,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AppBackButton(
                    onTap: () => Navigator.pop(context),
                    color: Colors.white,
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _toggleFlash,
                    child: MingCuteIcon(
                      _flashOn
                          ? MingCuteIcons.flashFill
                          : MingCuteIcons.flashLine,
                      color: _flashOn ? t.brand : Colors.white,
                      size: AppUi.iconLarge,
                    ),
                  ),
                  const SizedBox(width: 20),
                  GestureDetector(
                    // 参考线直接放到外层，点击即可开关。
                    onTap: () =>
                        setState(() => _showGridGuide = !_showGridGuide),
                    child: MingCuteIcon(
                      MingCuteIcons.layoutGrid,
                      size: AppUi.iconLarge,
                      color: _showGridGuide ? t.brand : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 20),
                  GestureDetector(
                    onTap: _cyclePhotoRatio,
                    child: const MingCuteIcon(
                      MingCuteIcons.squareLine,
                      color: Colors.white,
                      size: AppUi.iconLarge,
                    ),
                  ),
                  const SizedBox(width: 20),
                  GestureDetector(
                    // 相机页设置应打开相机功能设置，而不是跳到全局设置页。
                    onTap: _showCameraSettingsSheet,
                    child: const MingCuteIcon(
                      MingCuteIcons.settings2Line,
                      color: Colors.white,
                      size: AppUi.iconLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 188,
                      height: 34,
                      child: DecoratedBox(
                        // 相机模式切换严格按用户给的 CSS：188x34、2px 内边距、黑色 20% 背景。
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Row(
                            children: List.generate(_modes.length, (i) {
                              final active = i == _modeIndex;
                              return Padding(
                                padding: EdgeInsets.only(
                                  right: i == _modes.length - 1 ? 0 : 2,
                                ),
                                child: GestureDetector(
                                  onTap: _recording
                                      ? null
                                      : () => _switchMode(i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 60,
                                    height: 30,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: active
                                          ? const Color(0xFFFFEE35)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Text(
                                      _modes[i],
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 22 / 14,
                                        fontWeight: FontWeight.w400,
                                        color: active
                                            ? const Color(0xFF000000)
                                            : const Color(0xFFFFFFFF),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/album'),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: _lastBytes != null
                                ? ClipOval(
                                    // 有最近照片时直接显示缩略图，不再显示相册图标。
                                    child: Image.memory(
                                      _lastBytes!,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Center(
                                    child: MingCuteIcon(
                                      MingCuteIcons.pic2Line,
                                      size: 24,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        GestureDetector(
                          onTapDown: (_) => _capture(),
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _recording
                                    ? const Color(0xFFFF3B30)
                                    : Colors.white,
                                width: 4,
                              ),
                            ),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: _recording ? 28 : 60,
                                height: _recording ? 28 : 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    _recording ? 8 : 30,
                                  ),
                                  color: _recording
                                      ? const Color(0xFFFF3B30)
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _switchLens,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: MingCuteIcon(
                                MingCuteIcons.refresh2Line,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final t = context.tokens;
    if (_error != null) {
      return Container(
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MingCuteIcon(
                  MingCuteIcons.camera,
                  size: AppUi.iconLarge,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 8),
                Text(
                  '演示环境无摄像头时，可前往「相册」查看金元宝种子照片',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppUi.fontCaption,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/album'),
                  style: FilledButton.styleFrom(
                    backgroundColor: t.brand,
                    foregroundColor: t.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('前往相册'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_isInitialized || _controller == null) {
      return Container(
        color: const Color(0xFF1A1A1A),
        child: Center(child: CircularProgressIndicator(color: t.brand)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = _controller!.value.previewSize;
        if (previewSize == null) {
          return CameraPreview(_controller!);
        }
        final isViewportPortrait =
            constraints.maxHeight >= constraints.maxWidth;
        final isPreviewPortrait = previewSize.height >= previewSize.width;
        // 只有当相机原始方向和屏幕方向不一致时才交换宽高，避免某些设备上把本来竖向的画面误当成横向处理。
        final displayWidth = isViewportPortrait == isPreviewPortrait
            ? previewSize.width
            : previewSize.height;
        final displayHeight = isViewportPortrait == isPreviewPortrait
            ? previewSize.height
            : previewSize.width;
        // 这里改成按视口比例做 cover 缩放，直接把多余区域裁掉，
        // 避免某些浏览器里 FittedBox 没有真正把 CameraPreview 铺满而露出黑边。
        final viewportAspect = constraints.maxWidth / constraints.maxHeight;
        final previewAspect = displayWidth / displayHeight;
        var scale = previewAspect / viewportAspect;
        if (scale < 1) {
          scale = 1 / scale;
        }
        return ClipRect(
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Center(
              child: SizedBox(
                width: displayWidth,
                height: displayHeight,
                child: CameraPreview(_controller!),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 统一在取景层叠加照片比例框、参考线和宠物取景框。
  Widget _buildCameraGuides() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final frame = _resolveGuideFrame(viewport);
        final hasRatioMask = _photoRatioValues[_photoRatioIndex] != null;
        return IgnorePointer(
          child: Stack(
            children: [
              if (hasRatioMask)
                Positioned.fill(
                  // 非原图比例时，用纯黑蒙版遮住比例外区域，中间比例区保持完全透明。
                  child: CustomPaint(
                    painter: _CameraRatioMaskPainter(frameRect: frame),
                  ),
                ),
              if (_showGridGuide)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CameraGridPainter(frameRect: frame),
                  ),
                ),
              if (_modeIndex == 2 && _showPetGuide)
                Positioned.fromRect(
                  rect: frame,
                  child: Center(
                    child: Container(
                      width: 220,
                      height: 280,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MingCuteIcon(
                            MingCuteIcons.paw,
                            size: AppUi.iconLarge,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '宠物取景框',
                            style: TextStyle(
                              fontSize: AppUi.fontBody,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 计算比例框在当前取景区域里的最大可用区域，避免压住上下操作区。
  Rect _resolveGuideFrame(Size viewport) {
    final targetRatio = _photoRatioValues[_photoRatioIndex];
    final padding = MediaQuery.paddingOf(context);
    final availableWidth = viewport.width;
    final availableHeight = math.max(
      0.0,
      viewport.height - padding.top - padding.bottom,
    );
    if (targetRatio == null) {
      return Rect.fromLTWH(0, padding.top, availableWidth, availableHeight);
    }

    final heightByWidth = availableWidth / targetRatio;
    final useWidth = heightByWidth <= availableHeight;
    final frameWidth = useWidth
        ? availableWidth
        : availableHeight * targetRatio;
    final frameHeight = useWidth ? heightByWidth : availableHeight;
    return Rect.fromLTWH(
      (viewport.width - frameWidth) / 2,
      padding.top + ((availableHeight - frameHeight) / 2),
      frameWidth,
      frameHeight,
    );
  }
}

class _CameraSettingSection extends StatelessWidget {
  const _CameraSettingSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            height: 22 / 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF000000),
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _CameraChoiceChip extends StatelessWidget {
  const _CameraChoiceChip({
    required this.label,
    this.width,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double? width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? t.brand : const Color(0xFFE2E4E6),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            height: 22 / 14,
            fontWeight: FontWeight.w400,
            color: selected ? const Color(0xFF000000) : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }
}

class _CameraSwitchTile extends StatelessWidget {
  const _CameraSwitchTile({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  height: 22 / 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF000000),
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                height: 22 / 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF999999),
              ),
            ),
            const SizedBox(width: 8),
            const MingCuteIcon(
              MingCuteIcons.rightLine,
              size: 20,
              color: Color(0xFF999999),
            ),
          ],
        ),
      ),
    );
  }
}

/// 参考线只画在可用取景区里，避免压到顶部导航和底部按钮。
class _CameraGridPainter extends CustomPainter {
  const _CameraGridPainter({required this.frameRect});

  final Rect frameRect;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1;

    final thirdWidth = frameRect.width / 3;
    final thirdHeight = frameRect.height / 3;

    for (var i = 1; i <= 2; i++) {
      final dx = frameRect.left + (thirdWidth * i);
      canvas.drawLine(
        Offset(dx, frameRect.top),
        Offset(dx, frameRect.bottom),
        paint,
      );
      final dy = frameRect.top + (thirdHeight * i);
      canvas.drawLine(
        Offset(frameRect.left, dy),
        Offset(frameRect.right, dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CameraGridPainter oldDelegate) {
    return oldDelegate.frameRect != frameRect;
  }
}

/// 比例外区域用纯黑遮罩，取景时就能看到最终成片范围。
class _CameraRatioMaskPainter extends CustomPainter {
  const _CameraRatioMaskPainter({required this.frameRect});

  final Rect frameRect;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(frameRect);
    canvas.drawPath(path, Paint()..color = const Color(0xFF000000));
  }

  @override
  bool shouldRepaint(covariant _CameraRatioMaskPainter oldDelegate) {
    return oldDelegate.frameRect != frameRect;
  }
}

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
    final mergedItemsAsync = photosAsync.when(
      loading: () => const AppLoadingView(),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (photos) => petsAsync.when(
        loading: () => const AppLoadingView(),
        error: (_, __) => _AlbumView(
          items: _mergePhotos(photos, captured, cloudPhotos),
          pets: [],
          createdWorks: createdItems,
        ),
        data: (pets) => _AlbumView(
          items: _mergePhotos(photos, captured, cloudPhotos),
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
  });
  final SourcePhoto source;
  final ImageProvider image;
  final String caption;
  final DateTime takenAt;
  final String petId; // 所属宠物ID，用于"按宠物"分组
  String get monthKey => '${takenAt.year}年${takenAt.month}月';
}

/// 合并「种子图 + 本地拍摄 + 云端拍摄作品」为相册照片分组。
/// [cloudPhotos] 来自 works.json 的 captured_photo（已上传 COS，刷新后仍可见）。
List<_AlbumItem> _mergePhotos(
  List<Photo> seed,
  List<CapturedPhoto> captured, [
  List<LibraryItem> cloudPhotos = const <LibraryItem>[],
]) =>
    <_AlbumItem>[
      for (final c in captured)
        _AlbumItem(
          source: SourcePhoto(bytes: c.bytes, caption: '拍摄照片'),
          image: MemoryImage(c.bytes),
          caption: _fmtDateTime(c.takenAt),
          takenAt: c.takenAt,
          // 拍摄的照片暂不归属特定宠物（用户后续可指定）
        ),
      for (final w in cloudPhotos)
        _AlbumItem(
          source: SourcePhoto(url: w.url, caption: '拍摄照片'),
          image: CachedNetworkImageProvider(w.url),
          caption: _fmtDateTime(w.takenAt),
          takenAt: w.takenAt,
          petId: w.petId,
        ),
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
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Image(
              image: item.image,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }

  void _showPreview(BuildContext context) {
    // 长按预览（后续可加分享/删除等操作）
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('拍摄于 ${item.caption}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

/// 全屏照片预览弹窗（圆角 + 底部信息）。
class _PhotoDialog extends StatelessWidget {
  const _PhotoDialog({required this.item});
  final _AlbumItem item;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: item.image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(color: context.tokens.surface),
              child: Text(
                item.caption,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.tokens.textSecondary,
                  fontSize: AppUi.fontCaption,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 宠物档案页：金元宝档案卡 + 统计。
/// 成长手记页：宠物切换 + 档案卡 + 录入（体重/疫苗/趣事）+ 时间线。
/// 记录本地持久化（Hive），按宠物隔离。
class PetProfilePage extends ConsumerStatefulWidget {
  const PetProfilePage({super.key});
  @override
  ConsumerState<PetProfilePage> createState() => _PetProfilePageState();
}

class _PetProfilePageState extends ConsumerState<PetProfilePage> {
  String? _selectedPetId;
  bool _isPetListExpanded = true;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final petsAsync = ref.watch(petsProvider);
    return _Shell(
      title: '成长手记',
      appBarBackgroundColor: const Color(0xFFF6F8FA),
      body: petsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (pets) {
          if (pets.isEmpty) return const Center(child: Text('暂无宠物档案'));
          _selectedPetId ??= pets.first.id;
          final pet = pets.firstWhere(
            (p) => p.id == _selectedPetId,
            orElse: () => pets.first,
          );
          final photosAsync = ref.watch(photosProvider);
          final recordsAsync = ref.watch(growthRecordsProvider(pet.id));
          return recordsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('记录加载失败')),
            data: (records) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              children: [
                _PetSwitch(
                  pets: pets,
                  selectedId: pet.id,
                  expanded: _isPetListExpanded,
                  onSelect: (id) => setState(() => _selectedPetId = id),
                  onToggleExpanded: () =>
                      setState(() => _isPetListExpanded = !_isPetListExpanded),
                ),
                const SizedBox(height: 16),
                _PetHeaderCard(
                  pet: pet,
                  recordCount: records.length,
                  photoCount: photosAsync.maybeWhen(
                    data: (p) => p.where((x) => x.petId == pet.id).length,
                    orElse: () => 0,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '成长时间线',
                    style: TextStyle(
                      fontSize: 20,
                      height: 28 / 20,
                      fontWeight: FontWeight.w400,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (records.isEmpty)
                  const _EmptyTimeline()
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const cardGap = 12.0;
                      final cardWidth = (constraints.maxWidth - cardGap) / 2;
                      final orderedRecords = [...records]
                        ..sort((a, b) {
                          const order = <GrowthType, int>{
                            GrowthType.weight: 0,
                            GrowthType.note: 1,
                            GrowthType.vaccine: 2,
                          };
                          final typeCompare = (order[a.type] ?? 99).compareTo(
                            order[b.type] ?? 99,
                          );
                          if (typeCompare != 0) {
                            return typeCompare;
                          }
                          return b.date.compareTo(a.date);
                        });
                      return Wrap(
                        spacing: cardGap,
                        runSpacing: cardGap,
                        children: orderedRecords
                            .map(
                              (r) => SizedBox(
                                width: cardWidth,
                                child: _TimelineItem(
                                  record: r,
                                  onAdd: () =>
                                      _showAddSheet(context, pet.id, r.type),
                                  onDelete: () => ref
                                      .read(growthRecordsMutationProvider)
                                      .remove(pet.id, r.id),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddSheet(BuildContext context, String petId, GrowthType type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddRecordSheet(
        type: type,
        onSubmit: (record) {
          ref.read(growthRecordsMutationProvider).add(petId, record);
          Navigator.pop(context);
        },
      ),
    );
  }
}

/// 成长手记顶部宠物切换卡片。
/// 按设计稿支持展开/收起两种状态：展开时显示头像列表，收起时只保留标题栏。
class _PetSwitch extends StatelessWidget {
  const _PetSwitch({
    required this.pets,
    required this.selectedId,
    required this.expanded,
    required this.onSelect,
    required this.onToggleExpanded,
  });
  final List<Pet> pets;
  final String selectedId;
  final bool expanded;
  final ValueChanged<String> onSelect;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '毛孩们',
                    style: TextStyle(
                      fontSize: AppUi.fontTitle,
                      height: 24 / AppUi.fontTitle,
                      fontWeight: FontWeight.w400,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggleExpanded,
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: expanded
                          ? const Color(0xFF000000)
                          : const Color(0xFF09244B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 88,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < pets.length; i++) ...[
                      _PetFilterAvatarTile(
                        name: pets[i].name,
                        avatarUrl: pets[i].avatarUrl,
                        selected: pets[i].id == selectedId,
                        onTap: () => onSelect(pets[i].id),
                      ),
                      if (i != pets.length - 1) const SizedBox(width: 16),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 宠物档案卡：头像 + 名字 + 品种年龄 + 统计。
class _PetHeaderCard extends StatelessWidget {
  const _PetHeaderCard({
    required this.pet,
    required this.recordCount,
    required this.photoCount,
  });
  final Pet pet;
  final int recordCount;
  final int photoCount;

  /// 统计区年龄使用更紧凑的数字展示，和设计稿里的数值样式保持一致。
  String get _ageMetricValue {
    final birthday = DateTime.tryParse(pet.birthday);
    if (birthday == null) return pet.ageLabel;
    final now = DateTime(2026, 7, 24);
    var years = now.year - birthday.year;
    var months = now.month - birthday.month;
    if (now.day < birthday.day) {
      months -= 1;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    if (years <= 0) {
      return '$months月';
    }
    if (months == 0) {
      return '$years';
    }
    return (years + months / 12).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = pet.breed.isNotEmpty
        ? (pet.ageLabel != '未知' ? '${pet.breed} · ${pet.ageLabel}' : pet.breed)
        : (pet.ageLabel != '未知' ? pet.ageLabel : '');

    return Container(
      constraints: const BoxConstraints(minHeight: 204),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部信息区：头像与基础资料横向排列，贴近设计稿结构。
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipOval(
                child: AppImage(
                  url: pet.avatarUrl,
                  width: 64,
                  height: 64,
                  memCacheWidth: 128,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        height: 28 / 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF000000),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 20 / 12,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF999999),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            pet.bio,
            style: const TextStyle(
              fontSize: 14,
              height: 22 / 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF000000),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PetMetricItem(label: '照片', value: '$photoCount'),
              const SizedBox(width: 12),
              _PetMetricItem(label: '记录', value: '$recordCount'),
              const SizedBox(width: 12),
              _PetMetricItem(label: '年龄', value: _ageMetricValue),
            ],
          ),
        ],
      ),
    );
  }
}

/// 时间线单条记录。
class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.record,
    required this.onAdd,
    required this.onDelete,
  });
  final GrowthRecord record;
  final VoidCallback onAdd;
  final VoidCallback onDelete;

  (Color, Widget, String, String) get _style {
    switch (record.type) {
      case GrowthType.weight:
        return (
          const Color(0xFF38D070),
          const MingCuteIcon(
            MingCuteIcons.instrumentFill,
            size: 18,
            color: Colors.white,
          ),
          '记体重',
          '体重',
        );
      case GrowthType.vaccine:
        return (
          const Color(0xFFFF5C5A),
          const MingCuteIcon(
            MingCuteIcons.injectionFill,
            size: 18,
            color: Colors.white,
          ),
          '记疫苗',
          '疫苗',
        );
      case GrowthType.note:
        return (
          const Color(0xFF9180FF),
          const MingCuteIcon(
            MingCuteIcons.tongueFill,
            size: 18,
            color: Colors.white,
          ),
          '记趣事',
          '趣事',
        );
    }
  }

  String get _valueText {
    switch (record.type) {
      case GrowthType.weight:
        return '${record.value}kg';
      case GrowthType.vaccine:
        return record.value;
      case GrowthType.note:
        return record.value;
    }
  }

  /// 时间样式改成“8月14日 23:05”，贴近设计稿展示。
  String get _dateText {
    final hh = record.date.hour.toString().padLeft(2, '0');
    final mm = record.date.minute.toString().padLeft(2, '0');
    final ss = record.date.second.toString().padLeft(2, '0');
    return '${record.date.month}月${record.date.day}日 $hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final (accentColor, iconWidget, actionLabel, typeName) = _style;
    return GestureDetector(
      onLongPress: () async {
        // 长按后先二次确认，避免误删成长记录。
        final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '删除记录',
                      style: TextStyle(
                        fontSize: AppUi.fontHeadline,
                        height: 28 / AppUi.fontHeadline,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF000000),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '确认删除这条$typeName记录吗？删除后将无法恢复。',
                      style: TextStyle(
                        fontSize: AppUi.fontBody,
                        height: AppUi.lineHeight(AppUi.fontBody),
                        fontWeight: FontWeight.w400,
                        color: context.tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _AppSecondaryActionButton(
                            label: '取消',
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppPrimaryActionButton(
                            label: '删除',
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
        if (shouldDelete == true) {
          onDelete();
        }
      },
      child: Container(
        height: 164,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: iconWidget,
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAdd,
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.5),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      actionLabel,
                      style: TextStyle(
                        fontSize: 12,
                        height: 20 / 12,
                        fontWeight: FontWeight.w400,
                        color: accentColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeName,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF000000),
                  ),
                ),
                Text(
                  _valueText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF000000),
                  ),
                ),
                Text(
                  _dateText,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 20 / 12,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              record.note.isNotEmpty ? record.note : '已记录$typeName信息',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 20 / 12,
                fontWeight: FontWeight.w400,
                color: Color(0xFF000000),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 统一浅色描边次按钮，给弹窗和底部弹层复用。
class _AppSecondaryActionButton extends StatelessWidget {
  const _AppSecondaryActionButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: context.tokens.textPrimary,
          side: const BorderSide(color: Color(0xFFE2E4E6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: AppUi.fontTitle,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 164,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MingCuteIcon(
            MingCuteIcons.clipboard,
            size: 24,
            color: Color(0xFF999999),
          ),
          SizedBox(height: 8),
          Text(
            '还没有记录，点上方按钮添加第一条',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 22 / 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}

/// 录入底部弹层表单。
class _AddRecordSheet extends StatefulWidget {
  const _AddRecordSheet({required this.type, required this.onSubmit});
  final GrowthType type;
  final ValueChanged<GrowthRecord> onSubmit;

  @override
  State<_AddRecordSheet> createState() => _AddRecordSheetState();
}

class _AddRecordSheetState extends State<_AddRecordSheet> {
  static const Color _fieldBorderColor = Color(0xFFE2E4E6);
  DateTime _date = DateTime.now();
  final _valueCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String get _title => switch (widget.type) {
    GrowthType.weight => '记体重',
    GrowthType.vaccine => '记疫苗',
    GrowthType.note => '记趣事',
  };

  String get _valueLabel => switch (widget.type) {
    GrowthType.weight => '体重 (kg)',
    GrowthType.vaccine => '疫苗名称',
    GrowthType.note => '趣事标题',
  };

  String get _noteLabel => switch (widget.type) {
    GrowthType.note => '趣事内容',
    GrowthType.vaccine => '备注（选填）',
    GrowthType.weight => '备注（选填）',
  };

  @override
  void dispose() {
    _valueCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final record = GrowthRecord(
      id: 'rec_${DateTime.now().microsecondsSinceEpoch}',
      type: widget.type,
      date: _date,
      value: _valueCtl.text.trim(),
      note: _noteCtl.text.trim(),
    );
    widget.onSubmit(record);
  }

  String _formatDateLabel(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    final ss = date.second.toString().padLeft(2, '0');
    return '${date.year}年${date.month.toString().padLeft(2, '0')}月${date.day.toString().padLeft(2, '0')}日 $hh:$mm:$ss';
  }

  InputDecoration _buildInputDecoration(
    BuildContext context, {
    required String hintText,
  }) {
    final t = context.tokens;
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        fontSize: AppUi.fontBody,
        height: AppUi.lineHeight(AppUi.fontBody),
        color: t.textSecondary,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        borderSide: const BorderSide(color: Color(0xFFFF5C5A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        borderSide: const BorderSide(color: Color(0xFFFF5C5A)),
      ),
      errorStyle: const TextStyle(fontSize: 12, height: 20 / 12),
    );
  }

  Future<void> _showCustomDateSheet() async {
    var tempDate = _date;
    var tempSecond = _date.second;
    final selectedDate = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E4E6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '记录时间',
                    style: TextStyle(
                      fontSize: AppUi.fontHeadline,
                      height: 28 / AppUi.fontHeadline,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 220,
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.dateAndTime,
                            use24hFormat: true,
                            initialDateTime: _date,
                            minimumDate: DateTime(2018),
                            maximumDate: DateTime.now(),
                            onDateTimeChanged: (value) {
                              tempDate = value;
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        height: 220,
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            const Text(
                              '秒',
                              style: TextStyle(
                                fontSize: 12,
                                height: 20 / 12,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF999999),
                              ),
                            ),
                            Expanded(
                              child: CupertinoPicker(
                                itemExtent: 36,
                                scrollController: FixedExtentScrollController(
                                  initialItem: _date.second,
                                ),
                                onSelectedItemChanged: (value) {
                                  tempSecond = value;
                                },
                                children: List.generate(
                                  60,
                                  (index) => Center(
                                    child: Text(
                                      index.toString().padLeft(2, '0'),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFF000000),
                                      ),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _AppSecondaryActionButton(
                          label: '取消',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppPrimaryActionButton(
                          label: '确定',
                          onPressed: () {
                            final picked = DateTime(
                              tempDate.year,
                              tempDate.month,
                              tempDate.day,
                              tempDate.hour,
                              tempDate.minute,
                              tempSecond,
                            );
                            final now = DateTime.now();
                            Navigator.of(
                              sheetContext,
                            ).pop(picked.isAfter(now) ? now : picked);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted || selectedDate == null) return;
    setState(() => _date = selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _title,
              style: TextStyle(
                fontSize: AppUi.fontHeadline,
                height: 28 / AppUi.fontHeadline,
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '日期',
              style: TextStyle(
                fontSize: AppUi.fontBody,
                height: AppUi.lineHeight(AppUi.fontBody),
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showCustomDateSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  border: Border.all(color: _fieldBorderColor),
                ),
                child: Row(
                  children: [
                    const MingCuteIcon(
                      MingCuteIcons.calendar,
                      size: 20,
                      color: Color(0xFF000000),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateLabel(_date),
                      style: TextStyle(
                        fontSize: AppUi.fontBody,
                        color: t.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    // 日期选择入口右箭头统一使用 MingCute 和灰色规范。
                    const MingCuteIcon(
                      MingCuteIcons.rightLine,
                      size: 20,
                      color: Color(0xFF999999),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _valueLabel,
              style: TextStyle(
                fontSize: AppUi.fontBody,
                height: AppUi.lineHeight(AppUi.fontBody),
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _valueCtl,
              keyboardType: widget.type == GrowthType.weight
                  ? TextInputType.number
                  : TextInputType.text,
              style: TextStyle(
                fontSize: AppUi.fontBody,
                height: AppUi.lineHeight(AppUi.fontBody),
                color: t.textPrimary,
              ),
              decoration: _buildInputDecoration(
                context,
                hintText: switch (widget.type) {
                  GrowthType.weight => '请输入体重，例如 4.8',
                  GrowthType.vaccine => '请输入疫苗名称',
                  GrowthType.note => '请输入趣事标题',
                },
              ),
              validator: (v) => v == null || v.trim().isEmpty ? '此项必填' : null,
            ),
            const SizedBox(height: 12),
            Text(
              _noteLabel,
              style: TextStyle(
                fontSize: AppUi.fontBody,
                height: AppUi.lineHeight(AppUi.fontBody),
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _noteCtl,
              maxLines: 3,
              style: TextStyle(
                fontSize: AppUi.fontBody,
                height: AppUi.lineHeight(AppUi.fontBody),
                color: t.textPrimary,
              ),
              decoration: _buildInputDecoration(
                context,
                hintText: widget.type == GrowthType.note
                    ? '请输入趣事内容'
                    : '补充一点备注信息',
              ),
            ),
            const SizedBox(height: 20),
            AppPrimaryActionButton(label: '保存', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

class _PetMetricItem extends StatelessWidget {
  const _PetMetricItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      // 统计项改为左对齐，和当前卡片信息区的阅读方向保持一致。
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              height: 28 / 20,
              fontWeight: FontWeight.w400,
              color: Color(0xFF000000),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              height: 20 / 12,
              fontWeight: FontWeight.w400,
              color: Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置页：外观（浅色/深色/系统）+ 数据清除 + 关于。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final mode = ref.watch(themeModeProvider);
    return _Shell(
      title: '设置',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        children: [
          const _SettingsSectionTitle(title: '外观'),
          const SizedBox(height: 12),
          _ThemeModeTabs(
            selectedMode: mode,
            onChanged: (value) =>
                ref.read(themeModeProvider.notifier).setMode(value),
          ),
          const SizedBox(height: 24),
          const _SettingsSectionTitle(title: '数据'),
          const SizedBox(height: 12),
          _ActionRow(
            // 设置页缓存清理图标统一切到 MingCute 版本。
            icon: MingCuteIcons.pic2Line,
            title: '清除相册缓存',
            subtitle: '删除应用内拍摄的照片（不可恢复）',
            onTap: () => _confirmClear(
              context,
              '相册',
              () => ref.read(capturedPhotosProvider.notifier).clear(),
            ),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            icon: MingCuteIcons.clapperboardLine,
            title: '清除短片缓存',
            subtitle: '删除已保存的萌宠短片（不可恢复）',
            onTap: () => _confirmClear(
              context,
              '短片',
              () => ref.read(shortVideosProvider.notifier).clear(),
            ),
          ),
          const SizedBox(height: 24),
          const _SettingsSectionTitle(title: '关于'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 28,
                      child: SvgPicture.asset(
                        'assets/brand/logo.svg',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '版本 1.0.0',
                  style: TextStyle(
                    fontSize: AppUi.fontBody,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '为毛孩子记录每一刻 · 毛孩写真 · 毛孩相册 · 一键成片',
                  style: TextStyle(
                    fontSize: AppUi.fontBody,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: t.textTertiary,
                ),
                const SizedBox(height: 12),
                _AboutBeianLink(
                  text: BeianFooter.beianNumber,
                  url: BeianFooter.beianUrl,
                ),
                const SizedBox(height: 4),
                _AboutBeianLink(
                  text: BeianFooter.gonganNumber,
                  url: BeianFooter.gonganUrl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「设置 → 关于」里的备案号链接行：点击跳转工信部 / 公安备案查询平台。
class _AboutBeianLink extends StatelessWidget {
  const _AboutBeianLink({required this.text, required this.url});

  final String text;
  final String url;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppUi.fontCaption,
          color: t.textSecondary,
          decoration: TextDecoration.underline,
          decorationColor: t.textTertiary,
        ),
      ),
    );
  }
}

/// 清除缓存二次确认。
Future<void> _confirmClear(
  BuildContext context,
  String label,
  VoidCallback clear,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '清除$label缓存',
                style: const TextStyle(
                  fontSize: AppUi.fontHeadline,
                  height: 28 / AppUi.fontHeadline,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF000000),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '确认删除所有$label吗？清除后将无法恢复。',
                style: TextStyle(
                  fontSize: AppUi.fontBody,
                  height: AppUi.lineHeight(AppUi.fontBody),
                  fontWeight: FontWeight.w400,
                  color: context.tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _AppSecondaryActionButton(
                      label: '取消',
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppPrimaryActionButton(
                      label: '清除',
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  if (ok == true) {
    clear();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已清除$label缓存')));
    }
  }
}

/// 设置分区标题。
class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w400,
        color: t.textPrimary,
      ),
    );
  }
}

/// 设置页主题切换改成统一胶囊分段按钮，避免继续使用默认平台控件外观。
class _ThemeModeTabs extends StatelessWidget {
  const _ThemeModeTabs({required this.selectedMode, required this.onChanged});

  final ThemeMode selectedMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ThemeModeTabItem(
              label: '浅色',
              selected: selectedMode == ThemeMode.light,
              onTap: () => onChanged(ThemeMode.light),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ThemeModeTabItem(
              label: '深色',
              selected: selectedMode == ThemeMode.dark,
              onTap: () => onChanged(ThemeMode.dark),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ThemeModeTabItem(
              label: '系统',
              selected: selectedMode == ThemeMode.system,
              onTap: () => onChanged(ThemeMode.system),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeTabItem extends StatelessWidget {
  const _ThemeModeTabItem({
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
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: selected ? context.tokens.brand : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? context.tokens.brand : const Color(0xFFE2E4E6),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            height: 22 / 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF000000),
          ),
        ),
      ),
    );
  }
}

/// 设置操作行（图标 + 标题 + 副标题 + 右箭头）。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppUi.radiusCard),
          ),
          child: Row(
            children: [
              MingCuteIcon(icon, size: 20, color: const Color(0xFF000000)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppUi.fontBody,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: AppUi.fontCaption,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const MingCuteIcon(
                MingCuteIcons.rightLine,
                size: 20,
                color: Color(0xFF999999),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「我的创作」视频回放弹窗：应用内生成的视频预览。
class _CreatedVideoDialog extends StatefulWidget {
  const _CreatedVideoDialog({required this.work});
  final LibraryItem work;

  @override
  State<_CreatedVideoDialog> createState() => _CreatedVideoDialogState();
}

class _CreatedVideoDialogState extends State<_CreatedVideoDialog> {
  /// 预览弹窗最大宽度（与 build 里 ConstrainedBox 保持一致）。
  static const double _dialogMaxWidth = 360;

  /// 弹窗内容内边距。
  static const double _dialogPadding = 12;

  VideoPlayerController? _c;

  /// 原生端把远程视频整包下载后的本地临时文件路径（dispose 时释放）。
  String? _localUrl;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = widget.work.url;
    try {
      VideoPlayerController c;
      if (kIsWeb) {
        // Web：直接播放远程地址（<video> 无需 CORS）。
        c = VideoPlayerController.networkUrl(Uri.parse(url));
      } else if (url.startsWith('http://') || url.startsWith('https://')) {
        // 原生端：video_player 的 file 源只接受本地路径，且万相成片 mp4 的
        // moov 在文件尾，直接 networkUrl 拉 COS 会长时间缓冲。这里先整包
        // 下载到临时文件再本地播放（稳定秒开）。
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 60));
        if (resp.statusCode != 200) {
          throw Exception('视频下载失败（HTTP ${resp.statusCode}）');
        }
        final path = await MediaPlatform.createMediaUrl(
          resp.bodyBytes,
          'video/mp4',
        );
        _localUrl = path;
        c = MediaPlatform.videoController(path);
      } else {
        c = MediaPlatform.videoController(url);
      }
      _c = c;
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _ready = true;
        _error = null;
      });
      await c.play();
    } catch (e) {
      // 给出可见错误 + 重试，而不是无限转圈。
      if (mounted) {
        setState(() => _error = '视频打开失败：$e');
      }
    }
  }

  Future<void> _retry() async {
    _c?.dispose();
    _c = null;
    if (_localUrl != null) {
      await MediaPlatform.releaseMediaUrl(_localUrl!);
      _localUrl = null;
    }
    if (!mounted) return;
    setState(() {
      _ready = false;
      _error = null;
    });
    _init();
  }

  @override
  void dispose() {
    _c?.dispose();
    if (_localUrl != null) {
      MediaPlatform.releaseMediaUrl(_localUrl!);
    }
    super.dispose();
  }

  Widget _buildPreview() {
    final err = _error;
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                onPressed: _retry,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white24,
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return _ready && _c != null && _c!.value.isInitialized
        ? Center(child: VideoPlayer(_c!))
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(color: Colors.white70),
                SizedBox(height: 12),
                Text(
                  '加载中…',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          );
  }

  /// 构建播放区：按视频真实宽高比自适应尺寸（contain），
  /// 横屏/竖屏视频都不会被固定 9:16 竖框拉伸。
  Widget _buildPlayerBox(BuildContext context) {
    final c = _c;
    final bool initialized = _ready && c != null && c.value.isInitialized;
    // 已初始化用真实比例；未就绪（加载中 / 出错）沿用竖屏占位比例。
    final double aspect = initialized && c.value.aspectRatio > 0
        ? c.value.aspectRatio
        : 9 / 16;

    final double screenHeight = MediaQuery.sizeOf(context).height;
    // 可用宽：弹窗上限宽度 - 两侧内边距。
    final double maxW = _dialogMaxWidth - _dialogPadding * 2;
    // 可用高：屏幕高度扣除弹窗上下 inset(24×2) 与弹窗内其它内容
    // （内边距 12×2 + 间距 12 + 底部按钮约 48），并限幅防止极端情况溢出。
    const double chromeHeight = 24 * 2 + _dialogPadding * 2 + 12 + 48;
    final double maxH = (screenHeight - chromeHeight)
        .clamp(160.0, _dialogMaxWidth * 16 / 9)
        .toDouble();

    // contain 语义：先铺满可用宽，过高则改为按高度折算，始终不变形。
    double w = maxW;
    double h = w / aspect;
    if (h > maxH) {
      h = maxH;
      w = h * aspect;
    }

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildPreview(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Dialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(_dialogPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPlayerBox(context),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: t.brand,
                    foregroundColor: t.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
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
