import 'package:flutter/material.dart';
import 'package:pet_camera/app/tokens.dart';

/// 统一加载视图。
/// 白底、主色 loading、黑色文案，供页面级和区块级加载复用。
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({
    super.key,
    this.label = '加载中...',
    this.compact = false,
    this.height,
  });

  final String label;
  final bool compact;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: t.brand, strokeWidth: 3),
        if (!compact) ...[
          const SizedBox(height: AppUi.space12),
          const Text(
            '加载中...',
            style: TextStyle(
              fontSize: AppUi.fontBody,
              color: Color(0xFF000000),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );

    if (height != null) {
      return SizedBox(
        height: height,
        child: Center(child: content),
      );
    }

    return ColoredBox(
      color: Colors.white,
      child: Center(child: content),
    );
  }
}
