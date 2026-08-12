import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/ai_portrait_service.dart';
import 'package:pet_camera/data/captured_photos.dart';
import 'package:pet_camera/data/short_videos.dart';
import 'package:pet_camera/data/app_settings.dart';
import 'package:pet_camera/data/models.dart';
import 'package:pet_camera/data/seed_repository.dart';
import 'package:pet_camera/data/growth_records.dart';

/// 统一页面外壳：顶栏用 Lucide 图标（禁 emoji），配色全部走 Token。
class _Shell extends StatelessWidget {
  const _Shell({
    required this.title,
    required this.icon,
    required this.body,
    this.floatingAction,
  });

  final String title;
  final IconData icon;
  final Widget body;
  final Widget? floatingAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(
        leading: Icon(icon, color: t.ink),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: t.surface,
        foregroundColor: t.textPrimary,
        elevation: 0,
      ),
      backgroundColor: t.bgBase,
      body: body,
      floatingActionButton: floatingAction,
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
      case 1: Navigator.pushNamed(context, '/album'); break;
      case 2: Navigator.pushNamed(context, '/camera'); break;
      case 3: Navigator.pushNamed(context, '/pet-profile'); break;
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
                  const SizedBox(height: 18),

                  // ===== Hero 横幅卡（薰衣草紫底 + CTA） =====
                  _HeroBannerCard(),
                  const SizedBox(height: 12),

                  // ===== 功能卡片网格（2列 + 足够高度显示完整文字） =====
                  _SectionHeader(icon: LucideIcons.sparkles, title: '更多惊喜', colorBlue: false),
                  const SizedBox(height: 10),
                  _FeatureGridSection(),
                  const SizedBox(height: 16),

                  // ===== 最近照片横滑 =====
                  _SectionHeader(icon: LucideIcons.images, title: '毛孩近照', colorBlue: true),
                  const SizedBox(height: 14),
                  _RecentPhotosRow(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // 底部导航栏（居中 FAB）
          Positioned(left: 0, right: 0, bottom: 0, child: _InsBottomNav(currentIndex: _currentNav, onTap: _onNavTap)),
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
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Icon(LucideIcons.camera, size: 20, color: const Color(0xFF2B2622)),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // 中间：粗体标题（Facebook 风格左对齐）
          const Text('元宝拍拍',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2B2622),
                letterSpacing: -0.5,
              )),

          const Spacer(),

          // 右侧：添加/设置按钮
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/settings'),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Icon(LucideIcons.plus, size: 20, color: const Color(0xFF2B2622)),
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
              itemCount: 4,  // ★ 4只核心毛孩（删了全家福+最新照片）
              separatorBuilder: (_, __) => const SizedBox(width: 14),
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
    (bg: Color(0xFFF5E6FA), name: '金元宝',   petId: 'yuanbao',     photo: 'yuanbao_headshot.png', align: Alignment(0.0, -0.2)),  // 头像居中偏上
    (bg: Color(0xFFD6EEF5), name: '小棉花',   petId: 'xiaomianhua', photo: 'xiaomianhua_005.jpg', align: Alignment(0.0, -0.45)), // ★ 猫脸放大：强力上移聚焦脸部
    (bg: Color(0xFFFFE4DD), name: '小汤圆',   petId: 'xiaotangyuan', photo: 'xiaotangyuan_008.jpg', align: Alignment(0.0, -0.65)), // ★ 猫脸在照片上25%，需负值下移
    (bg: Color(0xFFE8F0E0), name: '猫友圈',   petId: 'friends',     photo: 'friend_007.jpg', align: Alignment(0.0, -0.2)),      // 跳转元宝的朋友们
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _cardColors[index % _cardColors.length];

    return GestureDetector(
      onTap: () {
        if (colors.petId.isNotEmpty) {
          Navigator.pushNamed(context, '/album', arguments: {'petId': colors.petId});
        } else {
          Navigator.pushNamed(context, '/album');
        }
      },
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
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
                borderRadius: BorderRadius.circular(14),
                child: Image.asset('assets/seed/photos/${colors.photo}', fit: BoxFit.cover, alignment: colors.align),
              ),
            ),
            // 底部名字标签（参考 Facebook 的 Vanetic / Bestiolos 标签）
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Text(colors.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A4540))),
            ),
            // ★ 右上角相机图标按钮（点击打开相机，照片存入对应毛孩相册）
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pushNamed(context, '/camera', arguments: {'petName': colors.name}),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
                    ),
                    child: const Icon(LucideIcons.camera, size: 15, color: Colors.white),
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
  const _SectionHeader({required this.icon, required this.title, this.colorBlue = true});
  final IconData icon;
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
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Text(title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2B2622),
              )),
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
                      const Text('为毛孩子记录每一刻',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2B2622),
                            height: 1.2,
                          )),
                      const SizedBox(height: 4),
                      const Text('毛孩写真 · 毛孩相册 · 一键成片',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF8A7FA8), // 薰衣草灰紫
                          )),
                      const SizedBox(height: 8),
                      // CTA 胶囊按钮（柔紫蓝，参考 Try it 按钮）
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA694C8), // 马卡龙柔紫
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: const Text('开始拍照',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            )),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // 右侧宠物照片
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/seed/photos/yuanbao_headshot.png',
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
const _featureCards = [
  _FeatCardData(
    icon: LucideIcons.wand2,
    title: '毛孩写真',
    desc: 'AI生成油画、插画等多种艺术风格肖像。',
    tag: 'AI 驱动',
    assetPath: 'assets/seed/photos/feat_portrait.jpg',   // ★ 金元宝9宫格写真
    route: '/portrait',
    align: const Alignment(0.0, -0.1),                     // 写真构图居中
  ),
  _FeatCardData(
    icon: LucideIcons.image,
    title: '毛孩相册',
    desc: '自动按宠物归类，瀑布流浏览所有照片。',
    tag: '201 张照片',
    assetPath: 'assets/seed/photos/feat_album.jpg',      // ★ 春春江江4小奶猫
    route: '/album',
    align: const Alignment(0.0, -0.3),
  ),
  _FeatCardData(
    icon: LucideIcons.clapperboard,
    title: '一键成片',
    desc: '选几张照片，AI自动配乐剪辑成短视频。',
    tag: '视频',
    assetPath: 'assets/seed/photos/feat_video_thumb.jpg', // ★ 视频缩略图
    videoAssetPath: 'assets/seed/photos/feat_video_compressed.mp4',  // ★ 压缩版(0.82MB,云端秒加载)
    route: '/short-video',
    align: const Alignment(0.5, 0.15),                      // ★ 焦点下移（避免顶部杯子/空白过多）
  ),
  _FeatCardData(
    icon: LucideIcons.sparkles,
    title: '毛孩美颜',
    desc: '智能抠图换背景，叠加海量趣味贴纸。',
    tag: '已上线',
    assetPath: 'assets/seed/photos/feat_retouch.jpg',     // ★ 布偶猫蓝眼睛(木头)
    route: '/retouch',
    align: const Alignment(0.0, -0.25),
  ),
  _FeatCardData(
    icon: LucideIcons.heart,
    title: '成长手记',
    desc: '记录体重、疫苗、趣事与每个成长细节。',
    tag: '4 只宠物',
    assetPath: 'assets/seed/photos/feat_profile.jpg',     // ★ 兽医体检
    route: '/pet-profile',
    align: const Alignment(0.0, -0.2),
  ),
  _FeatCardData(
    icon: LucideIcons.camera,
    title: '灵动快门',
    desc: '全屏取景+防抖算法，精准抓拍灵动瞬间。',
    tag: '已接入',
    assetPath: 'assets/seed/photos/feat_camera.jpg',      // ★ 戴圈金毛(小凳子)
    route: '/camera',
    align: const Alignment(0.0, -0.15),
  ),
];

/// 功能卡片数据模型
class _FeatCardData {
  const _FeatCardData({
    required this.icon,
    required this.title,
    required this.desc,
    required this.tag,
    required this.assetPath,
    required this.route,
    this.align = const Alignment(0.0, -0.2),  // 默认偏上保猫脸
    this.videoAssetPath,                     // 视频资源路径（非空时显示播放按钮）
  });
  final IconData icon;
  final String title;
  final String desc;
  final String tag;
  final String assetPath;
  final String route;
  final Alignment align;  // 每张卡片独立的 cover 焦点
  final String? videoAssetPath;  // 视频资源路径
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
          crossAxisCount: 3,                  // ★ 3列
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.80,            // 更高=更矮卡片，节省纵向空间
        ),
        itemCount: _featureCards.length,       // 6张 = 2行
        itemBuilder: (context, i) => _FeatCard(data: _featureCards[i], isFeatured: i == 0),
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
    final colors = _macaronColors[_featureCards.indexOf(data) % _macaronColors.length];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, data.route),
        borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            border: isFeatured
                ? Border.all(color: const Color(0xFF9B8AC4).withValues(alpha: 0.45), width: 1.8)
                : null,
            boxShadow: isFeatured
                ? [
                    BoxShadow(color: const Color(0xFF9B8AC4).withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6)),
                    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3)),
                  ]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 55, child: Stack(children: [
                Positioned.fill(child: Image.asset(data.assetPath, fit: BoxFit.cover, alignment: data.align)),
                Positioned(top: 7, right: 7, child: Container(width: 28, height: 28,
                  decoration: BoxDecoration(color: colors.bg, shape: BoxShape.circle,
                    border: isFeatured ? Border.all(color: colors.icon.withValues(alpha: 0.3), width: 1.5) : null),
                  child: Icon(data.icon, size: isFeatured ? 15 : 13, color: colors.icon))),
                if (isFeatured) Positioned(top: 7, left: 7, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFF9B8AC4).withValues(alpha: 0.90), borderRadius: BorderRadius.circular(8)),
                  child: const Text('推荐', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)))),
              ])),
              Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(data.title, style: TextStyle(fontSize: isFeatured ? 14 : 13, fontWeight: FontWeight.w700, color: const Color(0xFF2D2D2D))),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: colors.bg.withValues(alpha: 0.60), borderRadius: BorderRadius.circular(6)),
                    child: Text(data.tag, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: colors.icon))),
                ]),
                const SizedBox(height: 3),
                Text(data.desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, height: 1.35, color: const Color(0xFF888888))),
              ])),
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

    try { _controller?.dispose(); } catch (_) {}
    _controller = null;

    try {
      final assetKey = widget.data.videoAssetPath!;
      final webAssetPath = 'assets/$assetKey';
      final videoUrl = Uri.base.resolve(webAssetPath);

      final c = VideoPlayerController.networkUrl(videoUrl);
      _controller = c;
      await c.initialize(); // 这里会等待视频下载+解码，云端可能需要 5-20 秒
      if (!mounted) { c.dispose(); return; }
      c.setLooping(true);
      c.setVolume(0);
      c.play();
      if (mounted) setState(() { _videoReady = true; _isLoading = false; });
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
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
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
                  onTap: _videoReady ? () => Navigator.pushNamed(context, widget.data.route) : _startVideo,
                  behavior: HitTestBehavior.opaque,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // === 底层：静态缩略图（始终渲染，永不空白/暗/VIDEO）===
                      Image.asset(widget.data.assetPath, fit: BoxFit.cover, alignment: widget.data.align),
                      // === 上层：VideoPlayer（就绪后直接覆盖）===
                      if (_videoReady && _controller != null && _controller!.value.isInitialized)
                        FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          alignment: widget.data.align,
                          child: SizedBox(
                            width: _controller!.value.size.width > 0 ? _controller!.value.size.width : 1280,
                            height: _controller!.value.size.height > 0 ? _controller!.value.size.height : 720,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                      // === Loading 指示器：点击后加载中 ===
                      if (_isLoading && !_videoReady)
                        Center(
                          child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.50),
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                        ),
                      // === 播放按钮：未加载时显示（白边+半透明底）===
                      if (!_videoReady && !_isLoading)
                        Center(
                          child: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.40),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.80), width: 2.5),
                            ),
                            child: Icon(LucideIcons.play, size: 22, color: Colors.white),
                          ),
                        ),
                      // 右上角图标标签
                      Positioned(
                        top: 7, right: 7,
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(color: colors.bg, shape: BoxShape.circle),
                          child: Icon(widget.data.icon, size: 13, color: colors.icon),
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
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(widget.data.title,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2D2D2D))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.bg.withValues(alpha: 0.60),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(widget.data.tag,
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: colors.icon)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(widget.data.desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, height: 1.35, color: Color(0xFF888888))),
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
    'yuanbao_2157.jpg', 'yuanbao_2158.jpg', 'yuanbao_2161.jpg', // 2026-08-09 新增金元宝近照
    'yuanbao_141.jpg', 'yuanbao_140.jpg', 'xiaotangyuan_026.jpg', 'xiaomianhua_021.jpg', 'yuanbao_123.jpg',
    'yuanbao_098.jpg', 'xiaomianhua_005.jpg', 'xiaotangyuan_008.jpg', 'friend_007.jpg', 'yuanbao_090.jpg',
    'xiaomianhua_010.jpg', 'friend_020.jpg', 'yuanbao_050.jpg', 'xiaotangyuan_014.jpg',
    'friend_030.jpg', 'xiaomianhua_015.jpg', 'yuanbao_085.jpg',
  ];
  // 下排 15 张
  static const _bottomRow = [
    'yuanbao_075.jpg', 'yuanbao_100.jpg', 'xiaomianhua_002.jpg', 'yuanbao_065.jpg',
    'friend_015.jpg', 'yuanbao_095.jpg', 'xiaotangyuan_010.jpg', 'friend_025.jpg',
    'yuanbao_088.jpg', 'xiaomianhua_008.jpg', 'xiaotangyuan_016.jpg', 'friend_035.jpg',
    'xiaomianhua_012.jpg', 'yuanbao_078.jpg', 'xiaotangyuan_003.jpg',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PhotoStrip(photos: _topRow),
        const SizedBox(height: 10), // 两排间距
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
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) =>
              _MasonryPhotoTile(assetPath: 'assets/seed/photos/${photos[i]}'),
        ),
      ),
    );
  }
}

/// Pinterest 风格照片卡片 —— **等高 + 宽度跟随照片真实比例 + fitHeight 不裁切**
class _MasonryPhotoTile extends StatelessWidget {
  const _MasonryPhotoTile({required this.assetPath});
  final String assetPath;
  static const double _h = 175;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/album'),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: _h, // ★ 等高：每行都是 175px
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFFF8F6F3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          // ★ width 不固定 → 由 fitHeight 按照片真实比例算出，宽窄自然错落
          child: Image.asset(assetPath, fit: BoxFit.fitHeight, height: _h),
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

  static const _navItems = [
    (icon: LucideIcons.home, label: '首页'),
    (icon: LucideIcons.image, label: '相册'),
    // index 2 = FAB center
    (icon: LucideIcons.user, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, -3)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 左侧：首页
              _NavItem(icon: LucideIcons.home, label: '首页', active: currentIndex == 0, onTap: () => onTap(0)),
              // 相册
              _NavItem(icon: LucideIcons.image, label: '相册', active: currentIndex == 1, onTap: () => onTap(1)),

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
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFFFA950).withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: const Icon(LucideIcons.camera, size: 22, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),

              // 右侧：我的
              _NavItem(icon: LucideIcons.user, label: '我的', active: currentIndex == 3, onTap: () => onTap(3)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个导航项（马卡龙：活跃=薰衣草紫，非活跃=灰）
class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
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
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  )),
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
  List<CameraDescription> _cameras = <CameraDescription>[];
  CameraController? _controller;
  bool _isInitialized = false;
  String? _error;
  bool _flashOn = false;
  int _cameraIndex = 0;
  int _modeIndex = 0; // 0=拍照 1=视频 2=宠物
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
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = '未检测到可用摄像头');
        return;
      }
      _cameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _setupController(_cameras[_cameraIndex]);
    } catch (e) {
      setState(() => _error = '相机启动失败：$e');
    }
  }

  Future<void> _setupController(CameraDescription desc, {bool enableAudio = false}) async {
    _controller?.dispose();
    _recording = false;
    CameraController? c;
    try {
      c = CameraController(desc, ResolutionPreset.medium, enableAudio: enableAudio);
      await c.initialize();
    } catch (e) {
      if (enableAudio) {
        // 部分浏览器/设备 getUserMedia 不支持音频轨，降级为无声视频录制
        try {
          c = CameraController(desc, ResolutionPreset.medium, enableAudio: false);
          await c.initialize();
          _audioUnsupported = true;
        } catch (e2) {
          if (mounted) setState(() => _error = '相机启动失败：$e2');
          return;
        }
      } else {
        if (mounted) setState(() => _error = '相机启动失败：$e');
        return;
      }
    }
    _controller = c!;
    if (mounted) setState(() => _isInitialized = true);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isInitialized) return;
    _flashOn = !_flashOn;
    try {
      await _controller!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _switchLens() async {
    if (_cameras.length < 2 || _recording) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _isInitialized = false);
    await _setupController(_cameras[_cameraIndex], enableAudio: _modeIndex == 1);
  }

  Future<void> _capture() async {
    if (_controller == null || !_isInitialized) return;
    if (_modeIndex == 1) {
      await _toggleRecording();
      return;
    }
    try {
      final x = await _controller!.takePicture();
      final bytes = await x.readAsBytes();
      ref.read(capturedPhotosProvider.notifier).add(bytes);
      setState(() {
        _captured = true;
        _lastBytes = bytes;
      });
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) setState(() => _captured = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失败：$e')),
        );
      }
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
        ref.read(shortVideosProvider.notifier).add(
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已存入短片库，去「一键成片」加字幕配乐')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('停止录制失败：$e')),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('开始录制失败：$e')),
        );
      }
    }
  }

  /// 切换拍照/视频/宠物模式；进入视频模式时重建控制器以开启音频轨。
  Future<void> _switchMode(int i) async {
    if (i == _modeIndex || _recording || _cameras.isEmpty) return;
    setState(() {
      _modeIndex = i;
      _isInitialized = false;
      _audioUnsupported = false;
    });
    await _setupController(_cameras[_cameraIndex], enableAudio: i == 1);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPreview()),
          if (_modeIndex == 2 && _isInitialized)
            Center(
              child: Container(
                width: 220,
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.pawPrint, size: 32, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    Text('宠物取景框', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
                  ],
                ),
              ),
            ),
          if (_captured) Positioned.fill(child: Container(color: Colors.white)),
          if (_recording)
            Positioned(
              top: 72,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(
                        _audioUnsupported ? '录制中（无声）' : '录制中',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.9)),
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
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, color: Colors.white, size: 24),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _toggleFlash,
                    child: Icon(
                      _flashOn ? LucideIcons.flashlight : LucideIcons.flashlightOff,
                      color: _flashOn ? const Color(0xFFF2864B) : Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(LucideIcons.settings2, color: Colors.white, size: 24),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24, left: 20, right: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(_modes.length, (i) {
                          final active = i == _modeIndex;
                          return GestureDetector(
                            onTap: _recording ? null : () => _switchMode(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: active ? const Color(0xFFF2864B) : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(_modes[i],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                                    color: active ? Colors.white : Colors.white.withValues(alpha: 0.7),
                                  )),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/album'),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: _lastBytes != null
                                ? Image.memory(_lastBytes!, width: 48, height: 48, fit: BoxFit.cover)
                                : Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                    ),
                                    child: Icon(LucideIcons.image, size: 20, color: Colors.white.withValues(alpha: 0.4)),
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
                                color: _recording ? const Color(0xFFFF3B30) : const Color(0xFFF2864B),
                                width: 4,
                              ),
                            ),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: _recording ? 28 : 60,
                                height: _recording ? 28 : 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(_recording ? 8 : 30),
                                  color: _recording ? const Color(0xFFFF3B30) : const Color(0xFFF2864B),
                                ),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _switchLens,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            child: Icon(LucideIcons.repeat, size: 20, color: Colors.white.withValues(alpha: 0.8)),
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
    if (_error != null) {
      return Container(
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.cameraOff, size: 48, color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                const SizedBox(height: 8),
                Text('演示环境无摄像头时，可前往「相册」查看金元宝种子照片', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/album'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF2864B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
        child: const Center(child: CircularProgressIndicator(color: Color(0xFFF2864B))),
      );
    }
    return CameraPreview(_controller!);
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
  Uint8List? _resultBytes;
  String? _error;
  bool _demo = false;

  List<SourcePhoto> _buildSources(
    List<Photo> seed,
    List<CapturedPhoto> captured,
  ) {
    final list = <SourcePhoto>[];
    for (final c in captured) {
      list.add(SourcePhoto(bytes: c.bytes, caption: '拍摄照片'));
    }
    for (final p in seed) {
      list.add(SourcePhoto(assetPath: p.assetPath, caption: p.petId));
    }
    return list;
  }

  bool _isSame(SourcePhoto a, SourcePhoto b) =>
      a.assetPath == b.assetPath && a.bytes == b.bytes;

  Future<void> _generate() async {
    if (_selected == null || _generating) return;
    setState(() {
      _generating = true;
      _error = null;
      _resultBytes = null;
    });
    try {
      final bytes = await _selected!.resolveBytes();
      final result = await ref
          .read(aiPortraitServiceProvider)
          .generatePortrait(PortraitRequest(sourceBytes: bytes, styleId: _styleId));
      if (mounted) {
        setState(() {
          _resultBytes = result.imageBytes;
          _demo = result.demo;
          _generating = false;
        });
      }
    } on AiPortraitException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '生成失败：$e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _saveToAlbum() {
    if (_resultBytes == null) return;
    ref.read(capturedPhotosProvider.notifier).add(_resultBytes!);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已存入相册')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(photosProvider);
    final captured = ref.watch(capturedPhotosProvider);
    return _Shell(
      title: 'AI 写真',
      icon: LucideIcons.wand2,
      body: photosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('照片加载失败')),
        data: (photos) => _buildContent(
          context,
          _buildSources(photos, captured),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<SourcePhoto> sources) {
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('选择照片',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 12),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sources.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (c, i) {
              final s = sources[i];
              final selected = _selected != null && _isSame(_selected!, s);
              final img = s.bytes != null
                  ? Image.memory(s.bytes!, fit: BoxFit.cover)
                  : Image.asset(s.assetPath!, fit: BoxFit.cover);
              return GestureDetector(
                onTap: () => setState(() => _selected = s),
                child: Container(
                  width: 92,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected ? t.brand : Colors.transparent,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: img,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        Text('选择风格',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: kPortraitStyles.map((style) {
            final active = style.id == _styleId;
            return GestureDetector(
              onTap: () => setState(() => _styleId = style.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: active ? t.brand : t.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? t.brand : t.brandSoft,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(style.icon, size: 16, color: active ? Colors.white : t.brand),
                    const SizedBox(width: 6),
                    Text(style.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? Colors.white : t.textPrimary,
                        )),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: (_selected == null || _generating) ? null : _generate,
            style: FilledButton.styleFrom(
              backgroundColor: t.brand,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              elevation: 0,
            ),
            child: _generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('开始生成',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 20),
        if (_generating)
          _ResultPlaceholder(icon: LucideIcons.loader, text: 'AI 正在创作中…', spinning: true, t: t)
        else if (_error != null)
          _ResultPlaceholder(icon: LucideIcons.alertTriangle, text: _error!, t: t)
        else if (_resultBytes != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(_resultBytes!, fit: BoxFit.cover),
              ),
              const SizedBox(height: 8),
              if (_demo)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: t.brandSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('演示模式 · 未接入真实 API',
                      style: TextStyle(fontSize: 12, color: t.brand)),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saveToAlbum,
                  icon: const Icon(LucideIcons.download),
                  label: const Text('保存到相册'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.brand,
                    side: BorderSide(color: t.brand),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
            ],
          )
        else
          _ResultPlaceholder(
            icon: LucideIcons.image,
            text: _selected == null ? '请先选择一张照片' : '选择风格后点击「开始生成」',
            t: t,
          ),
      ],
    );
  }
}

/// AI 写真结果区占位（加载/错误/空态）。
class _ResultPlaceholder extends StatelessWidget {
  const _ResultPlaceholder({
    required this.icon,
    required this.text,
    required this.t,
    this.spinning = false,
  });
  final IconData icon;
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
              : Icon(icon, size: 36, color: t.textSecondary),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.textSecondary)),
        ],
      ),
    );
  }
}

/// 相册页：宠物/时间双视图，种子照片 + 用户拍摄照片合并展示。
class AlbumPage extends ConsumerWidget {
  const AlbumPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(photosProvider);
    final petsAsync = ref.watch(petsProvider);
    final captured = ref.watch(capturedPhotosProvider);
    return Scaffold(
      backgroundColor: context.tokens.bgBase,
      body: Stack(
        children: [
          // 主内容区
          photosAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败：$e')),
            data: (photos) => petsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _AlbumView(items: _mergePhotos(photos, captured), pets: []),
              data: (pets) => _AlbumView(items: _mergePhotos(photos, captured), pets: pets),
            ),
          ),
          // 返回按钮（悬浮左上角）
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.tokens.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Icon(LucideIcons.chevronLeft, size: 20, color: context.tokens.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 相册统一显示单元（种子图用 AssetImage，拍摄图用 MemoryImage）。
class _AlbumItem {
  const _AlbumItem({required this.image, required this.caption, required this.takenAt, this.petId = ''});
  final ImageProvider image;
  final String caption;
  final DateTime takenAt;
  final String petId; // 所属宠物ID，用于"按宠物"分组
  String get monthKey => '${takenAt.year}年${takenAt.month}月';
}

List<_AlbumItem> _mergePhotos(List<Photo> seed, List<CapturedPhoto> captured) => <_AlbumItem>[
      for (final c in captured)
        _AlbumItem(
          image: MemoryImage(c.bytes),
          caption: _fmtDateTime(c.takenAt),
          takenAt: c.takenAt,
          // 拍摄的照片暂不归属特定宠物（用户后续可指定）
        ),
      for (final p in seed)
        _AlbumItem(
          image: AssetImage(p.assetPath),
          caption: p.capturedAt.toString().replaceFirst('.000', ''),
          takenAt: p.capturedAt,
          petId: p.petId,
        ),
    ];

String _fmtDateTime(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _AlbumView extends StatefulWidget {
  const _AlbumView({required this.items, required this.pets});
  final List<_AlbumItem> items;
  final List<Pet> pets;

  @override
  State<_AlbumView> createState() => _AlbumViewState();
}

class _AlbumViewState extends State<_AlbumView> {
  bool _byTime = false;
  String? _selectedPetId; // null = 全部宠物

  @override
  void initState() {
    super.initState();
    // 从路由参数读取 petId，自动筛选到对应宠物相册
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
    final t = context.tokens;
    return CustomScrollView(
      slivers: [
        // 切换栏（胶囊式）
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 8), // top=48 避开悬浮返回按钮
            child: Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _byTime = false),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: !_byTime ? t.brand : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.pawPrint, size: 15, color: !_byTime ? Colors.white : t.textSecondary),
                              const SizedBox(width: 4),
                              Text('按宠物', style: TextStyle(fontSize: 13, fontWeight: !_byTime ? FontWeight.w700 : FontWeight.w500, color: !_byTime ? Colors.white : t.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _byTime = true),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _byTime ? t.brand : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.calendar, size: 15, color: _byTime ? Colors.white : t.textSecondary),
                              const SizedBox(width: 4),
                              Text('按时间', style: TextStyle(fontSize: 13, fontWeight: _byTime ? FontWeight.w700 : FontWeight.w500, color: _byTime ? Colors.white : t.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 照片网格 / 宠物分组 / 时间分组
        if (_byTime)
          ..._buildTimeSlivers()
        else ...[
          _petFilterSliver(),
          ..._buildPetSlivers(),
        ],
      ],
    );
  }

  /// 按宠物分组：每个宠物一个档案头 + 该宠物的照片瀑布流
  List<Widget> _buildPetSlivers() {
    final t = context.tokens;

    if (widget.pets.isEmpty) {
      return [SliverPadding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), sliver: _MasonryGrid(items: widget.items))];
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
      slivers.add(SliverMainAxisGroup(
        slivers: [
          // 宠物档案头（紧凑版）
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, i == 0 ? 16 : 24, 16, 8),
              child: _PetProfileHeader(pet: pet, count: petItems.length, compact: true),
            ),
          ),
          // 该宠物的照片瀑布流
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: _MasonryGrid(items: petItems),
          ),
        ],
      ));

      // 组间分隔线（最后一组不加）
      if (i < petList.length - 1) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Divider(color: t.brandSoft.withOpacity(0.4), thickness: 1),
          ),
        ));
      }
    }

    // "其他"分组（拍摄的无归属照片）——仅"全部"模式显示
    final otherItems = _selectedPetId == null ? groups['__other__'] : null;
    if (otherItems != null && otherItems.isNotEmpty) {
      slivers.add(SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
              child: Row(
                children: [
                  Container(width: 4, height: 18, decoration: BoxDecoration(color: t.brand, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Text('最近拍摄', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.textPrimary)),
                  const SizedBox(width: 6),
                  Text('${otherItems.length}张', style: TextStyle(fontSize: 13, color: t.textSecondary)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: _MasonryGrid(items: otherItems),
          ),
        ],
      ));
    }

    // 如果没有任何照片
    if (slivers.isEmpty) {
      slivers.add(SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('还没有照片哦～', style: TextStyle(fontSize: 15, color: t.textSecondary))),
      ));
    }

    return slivers;
  }

  /// 顶部宠物筛选栏（横向滚动 chip）：全部 + 每只宠物头像+名字，点哪个只看哪个
  Widget _petFilterSliver() {
    final t = context.tokens;
    final petsWithPhotos = widget.pets
        .where((p) => widget.items.any((it) => it.petId == p.id))
        .toList();

    final chips = <Widget>[
      _petFilterChip(
        selected: _selectedPetId == null,
        onTap: () => setState(() => _selectedPetId = null),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.layoutGrid, size: 14, color: _selectedPetId == null ? Colors.white : t.textSecondary),
            const SizedBox(width: 4),
            Text('全部', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _selectedPetId == null ? Colors.white : t.textSecondary)),
          ],
        ),
      ),
      for (final pet in petsWithPhotos)
        _petFilterChip(
          selected: _selectedPetId == pet.id,
          onTap: () => setState(() => _selectedPetId = pet.id),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(child: Image.asset(pet.avatarPath, width: 22, height: 22, fit: BoxFit.cover)),
              const SizedBox(width: 5),
              Text(pet.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _selectedPetId == pet.id ? Colors.white : t.textPrimary)),
            ],
          ),
        ),
    ];

    return SliverToBoxAdapter(
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => chips[i],
        ),
      ),
    );
  }

/// 宠物筛选 chip（方法版，避免嵌套类）
  Widget _petFilterChip({required bool selected, required VoidCallback onTap, required Widget child}) {
    final t = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? t.brand : t.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? t.brand : t.brandSoft.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: child,
        ),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  children: [
                    Container(width: 4, height: 18, decoration: BoxDecoration(color: context.tokens.brand, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Text(key, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.tokens.textPrimary)),
                    const SizedBox(width: 6),
                    Text('${groups[key]!.length}张', style: TextStyle(fontSize: 13, color: context.tokens.textSecondary)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: _MasonryGrid(items: groups[key]!),
            ),
          ],
        ),
    ];
  }
}

/// 宠物档案头（横排：左侧头像+名字+品种，右侧统计卡片）。
class _PetProfileHeader extends StatelessWidget {
  const _PetProfileHeader({required this.pet, required this.count, this.compact = false});
  final Pet pet;
  final int count;
  final bool compact; // 紧凑模式：用于按宠物分组内的标题（小头像+紧凑间距）

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final avatarSize = compact ? 40.0 : 56.0;
    final nameFontSize = compact ? 16.0 : 18.0;
    final subFontSize = compact ? 11.5 : 12.5;
    final countFontSize = compact ? 14.0 : 16.0;
    final subtitle = pet.breed.isNotEmpty
        ? (pet.ageLabel != '未知' ? '${pet.breed} · ${pet.ageLabel}' : pet.breed)
        : (pet.ageLabel != '未知' ? pet.ageLabel : '');

    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 4 : 48, 16, compact ? 6 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：头像 + 名字 + 品种年龄
          ClipOval(
            child: Image.asset(pet.avatarPath, width: avatarSize, height: avatarSize, fit: BoxFit.cover),
          ),
          SizedBox(width: compact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(pet.name, style: TextStyle(fontSize: nameFontSize, fontWeight: FontWeight.w800, color: t.textPrimary)),
                if (subtitle.isNotEmpty) ...[
                  SizedBox(height: compact ? 2 : 3),
                  Text(subtitle, style: TextStyle(fontSize: subFontSize, color: t.textSecondary)),
                ],
              ],
            ),
          ),
          SizedBox(width: compact ? 8 : 12),
          // 右侧：照片计数
          Container(
            padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8, horizontal: compact ? 11 : 14),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(compact ? 12 : 14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.image, size: compact ? 13 : 15, color: t.brand),
                SizedBox(width: compact ? 4 : 5),
                Text('$count', style: TextStyle(fontSize: countFontSize, fontWeight: FontWeight.w800, color: t.textPrimary)),
                const SizedBox(width: 3),
                Text('张', style: TextStyle(fontSize: compact ? 10 : 11, color: t.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.tokens.textPrimary)),
        const SizedBox(height: 1),
        Text(label, style: TextStyle(fontSize: 10, color: context.tokens.textSecondary)),
      ],
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
      case 0: return 0.78;  // 偏宽（横构图猫照）
      case 1: return 1.05;  // 偏高（竖构图猫照）
      case 2: return 0.88;  // 接近方
      case 3: return 1.15;  // 高
      default: return 0.95; // 标准
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    // 分成左右两列
    final leftItems = <int>[];
    final rightItems = <int>[];
    for (var i = 0; i < items.length; i++) {
      if (i.isEven) leftItems.add(i); else rightItems.add(i);
    }

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _MasonryColumn(items: items, indices: leftItems, getRatio: _aspectRatio)),
          const SizedBox(width: 10),
          Expanded(child: _MasonryColumn(items: items, indices: rightItems, getRatio: _aspectRatio)),
        ],
      ),
    );
  }
}

class _MasonryColumn extends StatelessWidget {
  const _MasonryColumn({required this.items, required this.indices, required this.getRatio});
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
            padding: const EdgeInsets.only(bottom: 10),
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
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE8E4DE), // 浅暖灰边框，定义卡片边界
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
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
      SnackBar(content: Text('拍摄于 ${item.caption}'), duration: const Duration(seconds: 1)),
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
              decoration: BoxDecoration(
                color: context.tokens.surface,
              ),
              child: Text(item.caption, textAlign: TextAlign.center, style: TextStyle(color: context.tokens.textSecondary, fontSize: 12)),
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

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final petsAsync = ref.watch(petsProvider);
    return _Shell(
      title: '成长手记',
      icon: LucideIcons.bookOpen,
      body: petsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (pets) {
          if (pets.isEmpty) return const Center(child: Text('暂无宠物档案'));
          _selectedPetId ??= pets.first.id;
          final pet =
              pets.firstWhere((p) => p.id == _selectedPetId, orElse: () => pets.first);
          final photosAsync = ref.watch(photosProvider);
          final recordsAsync = ref.watch(growthRecordsProvider(pet.id));
          return recordsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('记录加载失败')),
            data: (records) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _PetSwitch(
                  pets: pets,
                  selectedId: pet.id,
                  onSelect: (id) => setState(() => _selectedPetId = id),
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
                const SizedBox(height: 20),
                _buildAddButtons(context, pet.id),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('成长时间线',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary)),
                ),
                const SizedBox(height: 12),
                if (records.isEmpty)
                  const _EmptyTimeline()
                else
                  ...records.map(
                    (r) => _TimelineItem(
                      record: r,
                      onDelete: () => ref
                          .read(growthRecordsMutationProvider)
                          .remove(pet.id, r.id),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddButtons(BuildContext context, String petId) {
    return Row(
      children: [
        Expanded(
          child: _AddButton(
            type: GrowthType.weight,
            onTap: () => _showAddSheet(context, petId, GrowthType.weight),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _AddButton(
            type: GrowthType.vaccine,
            onTap: () => _showAddSheet(context, petId, GrowthType.vaccine),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _AddButton(
            type: GrowthType.note,
            onTap: () => _showAddSheet(context, petId, GrowthType.note),
          ),
        ),
      ],
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

/// 宠物切换横滑（4 只头像 + 名字，修掉「只显示第一只」的缺口）。
class _PetSwitch extends StatelessWidget {
  const _PetSwitch({
    required this.pets,
    required this.selectedId,
    required this.onSelect,
  });
  final List<Pet> pets;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: pets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (c, i) {
          final pet = pets[i];
          final active = pet.id == selectedId;
          return GestureDetector(
            onTap: () => onSelect(pet.id),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active ? t.brand : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(pet.avatarPath, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pet.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? t.brand : t.textSecondary,
                  ),
                ),
              ],
            ),
          );
        },
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

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 42,
            backgroundImage: AssetImage(pet.avatarPath),
          ),
          const SizedBox(height: 10),
          Text(pet.name,
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800, color: t.textPrimary)),
          Text('${pet.breed} · ${pet.ageLabel}',
              style: TextStyle(color: t.textSecondary)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(pet.bio,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, fontSize: 13)),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatTile(icon: LucideIcons.image, label: '照片', value: '$photoCount'),
              _StatTile(icon: LucideIcons.bookOpen, label: '记录', value: '$recordCount'),
              _StatTile(icon: LucideIcons.calendar, label: '年龄', value: pet.ageLabel),
            ],
          ),
        ],
      ),
    );
  }
}

/// 录入按钮（体重 / 疫苗 / 趣事）。
class _AddButton extends StatelessWidget {
  const _AddButton({required this.type, required this.onTap});
  final GrowthType type;
  final VoidCallback onTap;

  (Color, Color, String) get _style {
    switch (type) {
      case GrowthType.weight:
        return (const Color(0xFFD6EEF5), const Color(0xFF5BA8C8), '体重');
      case GrowthType.vaccine:
        return (const Color(0xFFFFE4DD), const Color(0xFFD4826A), '疫苗');
      case GrowthType.note:
        return (const Color(0xFFE8E0F6), const Color(0xFF9B8AC4), '趣事');
    }
  }

  IconData get _icon {
    switch (type) {
      case GrowthType.weight:
        return LucideIcons.scale;
      case GrowthType.vaccine:
        return LucideIcons.syringe;
      case GrowthType.note:
        return LucideIcons.heart;
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = _style;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 84,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_icon, size: 22, color: fg),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// 时间线单条记录。
class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.record, required this.onDelete});
  final GrowthRecord record;
  final VoidCallback onDelete;

  (Color, Color, IconData, String) get _style {
    switch (record.type) {
      case GrowthType.weight:
        return (const Color(0xFFD6EEF5), const Color(0xFF5BA8C8),
            LucideIcons.scale, '体重');
      case GrowthType.vaccine:
        return (const Color(0xFFFFE4DD), const Color(0xFFD4826A),
            LucideIcons.syringe, '疫苗');
      case GrowthType.note:
        return (const Color(0xFFE8E0F6), const Color(0xFF9B8AC4),
            LucideIcons.heart, '趣事');
    }
  }

  String get _valueText {
    switch (record.type) {
      case GrowthType.weight:
        return '${record.value} kg';
      case GrowthType.vaccine:
        return record.value;
      case GrowthType.note:
        return record.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon, typeName) = _style;
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: fg),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(typeName,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: fg)),
                      const SizedBox(width: 8),
                      Text(
                        '${record.date.year}-${record.date.month.toString().padLeft(2, '0')}-${record.date.day.toString().padLeft(2, '0')}',
                        style: TextStyle(fontSize: 12, color: t.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(_valueText,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary)),
                  if (record.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(record.note,
                        style: TextStyle(fontSize: 13, color: t.textSecondary)),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: Icon(LucideIcons.trash2, size: 18, color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(LucideIcons.clipboardList, size: 36, color: t.textSecondary),
          const SizedBox(height: 10),
          Text('还没有记录，点上方按钮添加第一条',
              style: TextStyle(fontSize: 13, color: t.textSecondary)),
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

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.bgBase,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
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
            Text(_title,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: t.textPrimary)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2018),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = d);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.brandSoft),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.calendar, size: 18, color: t.brand),
                    const SizedBox(width: 10),
                    Text(
                      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 14, color: t.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _valueCtl,
              keyboardType: widget.type == GrowthType.weight
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: _valueLabel,
                filled: true,
                fillColor: t.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.brandSoft),
                ),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '此项必填' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteCtl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _noteLabel,
                filled: true,
                fillColor: t.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.brandSoft),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: t.brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: const Text('保存',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 96,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Icon(icon, color: t.brand),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.textPrimary)),
          Text(label, style: TextStyle(fontSize: 12, color: t.textSecondary)),
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
      icon: LucideIcons.settings,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _SettingsSectionTitle(icon: LucideIcons.palette, title: '外观'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: SegmentedButton<ThemeMode>(
              selected: {mode},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).setMode(s.first),
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(LucideIcons.sun),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(LucideIcons.moon),
                  label: Text('深色'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(LucideIcons.smartphone),
                  label: Text('系统'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const _SettingsSectionTitle(icon: LucideIcons.database, title: '数据'),
          const SizedBox(height: 12),
          _ActionRow(
            icon: LucideIcons.image,
            title: '清除相册缓存',
            subtitle: '删除应用内拍摄的照片（不可恢复）',
            onTap: () => _confirmClear(context, '相册',
                () => ref.read(capturedPhotosProvider.notifier).clear()),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            icon: LucideIcons.clapperboard,
            title: '清除短片缓存',
            subtitle: '删除已保存的萌宠短片（不可恢复）',
            onTap: () => _confirmClear(context, '短片',
                () => ref.read(shortVideosProvider.notifier).clear()),
          ),
          const SizedBox(height: 28),
          const _SettingsSectionTitle(icon: LucideIcons.info, title: '关于'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.pawPrint, color: t.brand, size: 22),
                    const SizedBox(width: 8),
                    Text('元宝拍拍',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: t.textPrimary)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('版本 1.0.0', style: TextStyle(fontSize: 13, color: t.textSecondary)),
                const SizedBox(height: 8),
                Text('为毛孩子记录每一刻 · 毛孩写真 · 毛孩相册 · 一键成片',
                    style: TextStyle(fontSize: 13, color: t.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 清除缓存二次确认。
Future<void> _confirmClear(BuildContext context, String label, VoidCallback clear) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('清除$label缓存'),
      content: Text('确定要删除所有$label吗？此操作不可恢复。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: context.tokens.brand),
          child: const Text('清除'),
        ),
      ],
    ),
  );
  if (ok == true) {
    clear();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已清除$label缓存')));
    }
  }
}

/// 设置分区标题（图标 + 文字）。
class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Icon(icon, size: 18, color: t.brand),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary)),
      ],
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
  final IconData icon;
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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: t.brandSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: t.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: t.textSecondary)),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, color: t.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
