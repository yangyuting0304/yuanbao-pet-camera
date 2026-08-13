import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/tokens.dart';

/// 通用顶部导航栏。
/// 统一首页和相册页的品牌 Logo、返回按钮和“我的”入口布局。
class AppTopNavBar extends StatelessWidget {
  const AppTopNavBar({super.key, required this.onOpenMine});

  final VoidCallback onOpenMine;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      // 一级页面导航栏本体为 44，但内容区保持 36，避免视觉上显得更厚。
      height: 36,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              // 顶部品牌区统一使用 SVG Logo，保持首页和相册页一致。
              child: SizedBox(
                width: 96,
                height: 28,
                child: SvgPicture.asset(
                  'assets/brand/logo.svg',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppUi.space12),
          _MineEntryButton(onTap: onOpenMine, backgroundColor: t.brand),
        ],
      ),
    );
  }
}

/// 顶部“我的”入口。
/// 保持 36x36 黄色圆形按钮，放进 44 高度导航里做垂直居中。
class _MineEntryButton extends StatelessWidget {
  const _MineEntryButton({required this.onTap, required this.backgroundColor});

  final VoidCallback onTap;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const MingCuteIcon(
          MingCuteIcons.user3Fill,
          size: 24,
          color: Colors.black,
        ),
      ),
    );
  }
}
