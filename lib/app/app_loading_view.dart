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
        // 固定一个更清晰的尺寸，避免手机上默认 loading 过小。
        SizedBox(
          width: compact ? 28 : 40,
          height: compact ? 28 : 40,
          child: CircularProgressIndicator(color: t.brand, strokeWidth: 3.5),
        ),
        if (!compact) ...[
          const SizedBox(height: AppUi.space12),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              height: 24 / 16,
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
