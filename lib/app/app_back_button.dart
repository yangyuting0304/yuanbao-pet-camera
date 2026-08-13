import 'package:flutter/material.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/tokens.dart';

/// 统一返回按钮。
/// 只保留 24x24 返回图标，并去掉 hover / 点击时的灰色底片。
class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    required this.onTap,
    // 返回按钮点击区统一按 44，高度与导航栏规范保持一致。
    this.hitSize = 44,
    this.color,
  });

  final VoidCallback onTap;
  final double hitSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: hitSize,
        height: hitSize,
        child: Align(
          alignment: Alignment.center,
          child: MingCuteIcon(
            MingCuteIcons.leftLine,
            size: AppUi.iconLarge,
            color: color ?? context.tokens.textPrimary,
          ),
        ),
      ),
    );
  }
}
