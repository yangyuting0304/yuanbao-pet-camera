import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/ai_portrait_service.dart';
import 'package:pet_camera/data/captured_photos.dart';
import 'package:pet_camera/data/models.dart';
import 'package:pet_camera/data/seed_repository.dart';

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
                  const SizedBox(height: 20),

                  // ===== Snapshot 横滑区（彩色底卡片 + 宠物照 + 名字标签） =====
                  _buildSnapshotSection(),
                  const SizedBox(height: 28),

                  // ===== Hero 横幅卡（薰衣草紫底 + CTA） =====
                  _HeroBannerCard(),
                  const SizedBox(height: 24),

                  // ===== 功能卡片网格（2列 + 足够高度显示完整文字） =====
                  _SectionHeader(icon: LucideIcons.sparkles, title: '探索全部功能', colorBlue: false),
                  const SizedBox(height: 14),
                  _FeatureGridSection(),
                  const SizedBox(height: 24),

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
          height: 180,
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
    (bg: Color(0xFFF5E6FA), name: '金元宝',   photo: 'yuanbao_headshot.png', align: Alignment(0.0, -0.2)),  // 头像居中偏上
    (bg: Color(0xFFD6EEF5), name: '小棉花',   photo: 'xiaomianhua_005.jpg', align: Alignment(0.0, -0.45)), // ★ 猫脸放大：强力上移聚焦脸部
    (bg: Color(0xFFFFE4DD), name: '小汤圆',   photo: 'xiaotangyuan_008.jpg', align: Alignment(0.0, -0.65)), // ★ 猫脸在照片上25%，需负值下移
    (bg: Color(0xFFE8F0E0), name: '猫友圈',   photo: 'friend_007.jpg', align: Alignment(0.0, -0.2)),      // 默认偏上
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _cardColors[index % _cardColors.length];

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/album'),
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
            height: 160,
            decoration: BoxDecoration(
              gradient: _heroGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.fromLTRB(22, 20, 16, 20),
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
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2B2622),
                            height: 1.3,
                          )),
                      const SizedBox(height: 8),
                      const Text('AI 写真 · 智能相册 · 短片剪辑',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF8A7FA8), // 薰衣草灰紫
                          )),
                      const SizedBox(height: 16),
                      // CTA 胶囊按钮（柔紫蓝，参考 Try it 按钮）
                      Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA694C8), // 马卡龙柔紫
                          borderRadius: BorderRadius.circular(19),
                        ),
                        alignment: Alignment.center,
                        child: const Text('开始拍照',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            )),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // 右侧宠物照片
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/seed/photos/yuanbao_headshot.png',
                    fit: BoxFit.cover,
                    width: 110,
                    height: 120,
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
    title: 'AI 写真',
    desc: '一键生成专业级宠物艺术照',
    tag: 'AI 驱动',
    assetPath: 'assets/seed/photos/yuanbao_025.png',   // 金元宝透明底大头照 → 写真感
    route: '/portrait',
  ),
  _FeatCardData(
    icon: LucideIcons.image,
    title: '智能相册',
    desc: '按宠物自动分类，瀑布流浏览',
    tag: '170 张照片',
    assetPath: 'assets/seed/photos/xiaomianhua_005.jpg', // 小棉花 → 相册多宠物概念
    route: '/album',
  ),
  _FeatCardData(
    icon: LucideIcons.clapperboard,
    title: '短片剪辑',
    desc: '照片自动生成萌宠短视频',
    tag: '即将上线',
    assetPath: 'assets/seed/photos/xiaotangyuan_008.jpg', // 小汤圆 → 动态短片感
    route: '/short-video',
    align: const Alignment(0.0, -0.55),   // ★ 猫脸在照片上部，负值聚焦顶部
  ),
  _FeatCardData(
    icon: LucideIcons.sparkles,
    title: '宠物 P 图',
    desc: '智能抠图、换背景、加贴纸',
    tag: '即将上线',
    assetPath: 'assets/seed/photos/friend_010.jpg',     // 猫友 → 趣味P图
    route: '/retouch',
    align: const Alignment(0.0, -0.5),    // ★ 负值：聚焦顶部猫脸
  ),
  _FeatCardData(
    icon: LucideIcons.heart,
    title: '毛孩档案',
    desc: '记录成长轨迹和健康信息',
    tag: '4 只宠物',
    assetPath: 'assets/seed/photos/yuanbao_040.jpg',    // 金元宝日常 → 档案记录感
    route: '/pet-profile',
    align: const Alignment(0.0, -0.45),  // ★ 负值：聚焦顶部猫脸
  ),
  _FeatCardData(
    icon: LucideIcons.camera,
    title: '相机',
    desc: '全屏取景框，一键快门拍照',
    tag: '已接入',
    assetPath: 'assets/seed/photos/xiaomianhua_010.jpg', // 小棉花特写 → 拍照感
    route: '/camera',
    align: const Alignment(0.0, -0.5),    // ★ 负值：聚焦顶部猫脸
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
  });
  final IconData icon;
  final String title;
  final String desc;
  final String tag;
  final String assetPath;
  final String route;
  final Alignment align;  // 每张卡片独立的 cover 焦点
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
          mainAxisSpacing: 14,
          crossAxisSpacing: 12,
          childAspectRatio: 0.96,            // 加高到近正方，确保文字+标签全显示
        ),
        itemCount: _featureCards.length,       // 6张 = 2行
        itemBuilder: (context, i) => _FeatCard(data: _featureCards[i], isFeatured: i == 0),
      ),
    );
  }
}

/// 单张功能卡片（统一结构 + 首卡 isFeatured 加粗视觉）
class _FeatCard extends StatelessWidget {
  const _FeatCard({required this.data, this.isFeatured = false});
  final _FeatCardData data;
  final bool isFeatured;

  // 马卡龙色（每张卡片不同）
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
            // ★ 主次之分：首卡有紫色渐变边框 + 更强阴影
            border: isFeatured
                ? Border.all(color: const Color(0xFF9B8AC4).withValues(alpha: 0.45), width: 1.8)
                : null,
            boxShadow: isFeatured
                ? [
                    BoxShadow(color: const Color(0xFF9B8AC4).withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6)),
                    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3)),
                  ]
                : [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 图片区
              Expanded(
                flex: 55,
                child: Stack(
                  children: [
                    // ★ cover 填满卡片 + 每张独立焦点（默认偏上保猫脸，可逐张调）
                    Positioned.fill(child: Image.asset(data.assetPath, fit: BoxFit.cover, alignment: data.align)),
                    // 右上角图标标签
                    Positioned(
                      top: 7,
                      right: 7,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colors.bg,
                          shape: BoxShape.circle,
                          // 首卡图标稍大+实心
                          border: isFeatured
                              ? Border.all(color: colors.icon.withValues(alpha: 0.3), width: 1.5)
                              : null,
                        ),
                        child: Icon(data.icon, size: isFeatured ? 15 : 13, color: colors.icon),
                      ),
                    ),
                    // ★ 首卡独有：左上角"推荐"小标
                    if (isFeatured)
                      Positioned(
                        top: 7,
                        left: 7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF9B8AC4).withValues(alpha: 0.90),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('推荐',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),

              // 文字区
              Expanded(
                flex: 45,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ★ 标题 + 标签同一行（不再被截断）
                      Row(
                        children: [
                          Expanded(
                            child: Text(data.title,
                                style: TextStyle(
                                  fontSize: isFeatured ? 14 : 13,
                                  fontWeight: isFeatured ? FontWeight.w800 : FontWeight.w700,
                                  color: const Color(0xFF2B2622),
                                )),
                          ),
                          const SizedBox(width: 5),
                          // 标签 pill 移到标题右侧（缩小确保单行）
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.bg.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(data.tag,
                                  style: TextStyle(
                                    fontSize: isFeatured ? 9 : 8.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.icon,
                                    height: 1.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // 描述（给更多空间，maxLines: 3）
                      Expanded(
                        child: Text(data.desc,
                            style: TextStyle(
                              fontSize: isFeatured ? 11 : 10.5,
                              color: const Color(0xFF7A7570),
                              height: 1.35,
                            ),
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 毛孩近照 —— Pinterest 双行瀑布流（**等高 + 宽度随照片真实比例 + 完整显示不裁切**）
class _RecentPhotosRow extends StatelessWidget {
  // 上排 15 张
  static const _topRow = [
    'yuanbao_098.jpg', 'yuanbao_080.jpg', 'yuanbao_070.jpg', 'yuanbao_060.jpg',
    'xiaomianhua_005.jpg', 'xiaotangyuan_008.jpg', 'friend_007.jpg', 'yuanbao_090.jpg',
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

  Future<void> _setupController(CameraDescription desc) async {
    _controller?.dispose();
    final c = CameraController(desc, ResolutionPreset.medium, enableAudio: false);
    _controller = c;
    await c.initialize();
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
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _isInitialized = false);
    await _setupController(_cameras[_cameraIndex]);
  }

  Future<void> _capture() async {
    if (_controller == null || !_isInitialized) return;
    if (_modeIndex == 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('视频录制将在后续切片接入')),
        );
      }
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
                            onTap: () => setState(() => _modeIndex = i),
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
                              border: Border.all(color: const Color(0xFFF2864B), width: 4),
                            ),
                            child: const Center(
                              child: SizedBox(width: 60, height: 60, child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF2864B)))),
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

/// 短片剪辑页（占位）。
class ShortVideoPage extends StatelessWidget {
  const ShortVideoPage({super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        title: '短片剪辑',
        icon: LucideIcons.clapperboard,
        body: const Center(child: Text('时间轴 + 一键成片占位 · 后续接入图生视频 API + ffmpeg')),
      );
}

/// P 图编辑页（占位）。
class RetouchPage extends StatelessWidget {
  const RetouchPage({super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        title: 'P 图',
        icon: LucideIcons.sparkles,
        body: const Center(child: Text('编辑画布 + 工具 Tab 占位 · 后续接入宠物专用模型')),
      );
}

/// 宠物档案页：金元宝档案卡 + 统计。
class PetProfilePage extends ConsumerWidget {
  const PetProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final petsAsync = ref.watch(petsProvider);
    final photosAsync = ref.watch(photosProvider);
    final albumsAsync = ref.watch(albumsProvider);
    return _Shell(
      title: '宠物档案',
      icon: LucideIcons.user,
      body: petsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (pets) => photosAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const SizedBox.shrink(),
          data: (photos) {
            final pet = pets.isNotEmpty ? pets.first : null;
            if (pet == null) {
              return const Center(child: Text('暂无宠物档案'));
            }
            final albums = albumsAsync.maybeWhen(
              data: (a) => a.where((x) => x.petId == pet.id).toList(),
              orElse: () => <Album>[],
            );
            final latest = photos.isNotEmpty ? photos.first.capturedAt : null;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundImage: AssetImage(pet.avatarPath),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(pet.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.tokens.textPrimary)),
                ),
                Center(
                  child: Text('${pet.breed} · ${pet.ageYears}岁', style: TextStyle(color: context.tokens.textSecondary)),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(pet.bio, textAlign: TextAlign.center, style: TextStyle(color: context.tokens.textSecondary, fontSize: 13)),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatTile(icon: LucideIcons.image, label: '照片', value: '${photos.length}'),
                    _StatTile(icon: LucideIcons.bookOpen, label: '相册', value: '${albums.length}'),
                    _StatTile(icon: LucideIcons.calendar, label: '最近拍', value: latest == null ? '—' : '${latest.month}/${latest.day}'),
                  ],
                ),
              ],
            );
          },
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

/// 设置页（占位）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        title: '设置',
        icon: LucideIcons.settings,
        body: const Center(child: Text('外观分段 + 演示数据开关占位')),
      );
}
