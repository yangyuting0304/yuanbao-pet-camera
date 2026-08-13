import 'package:flutter/material.dart';
import 'package:pet_camera/app/tokens.dart';

ButtonStyle _primaryActionButtonStyle(BuildContext context) {
  final t = context.tokens;
  return FilledButton.styleFrom(
    backgroundColor: t.brand,
    disabledBackgroundColor: const Color(0xFFF6F8FA),
    foregroundColor: t.textPrimary,
    disabledForegroundColor: t.textSecondary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 0,
  );
}

Widget _primaryActionButtonChild({
  required BuildContext context,
  required String label,
  required bool isLoading,
  IconData? icon,
  Widget? iconWidget,
}) {
  final t = context.tokens;
  if (isLoading) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: t.textPrimary),
    );
  }
  final text = Text(
    label,
    style: const TextStyle(
      fontSize: AppUi.fontTitle,
      fontWeight: FontWeight.w400,
    ),
  );
  if (iconWidget != null) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [iconWidget, const SizedBox(width: 8), text],
    );
  }
  if (icon == null) {
    return text;
  }
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, size: AppUi.iconSmall),
      const SizedBox(width: 8),
      text,
    ],
  );
}

Widget _primaryActionBottomBar({
  required BuildContext context,
  required Widget child,
}) {
  final t = context.tokens;
  return Container(
    color: t.surface,
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    child: SafeArea(top: false, child: child),
  );
}

/// 公共主按钮。
/// 统一“开始生成”这类主操作按钮的尺寸和视觉参数。
class AppPrimaryActionButton extends StatelessWidget {
  const AppPrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: _primaryActionButtonStyle(context),
        child: _primaryActionButtonChild(
          context: context,
          label: label,
          isLoading: isLoading,
        ),
      ),
    );
  }
}

/// 公共主按钮（图标 + 文字）。
/// 用于结果页这类需要同时展示图标和主文案的底部操作。
class AppPrimaryActionIconButton extends StatelessWidget {
  const AppPrimaryActionIconButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconWidget,
    this.isLoading = false,
  }) : assert(icon != null || iconWidget != null, '图标按钮需要传入图标');

  final String label;
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: _primaryActionButtonStyle(context),
        child: _primaryActionButtonChild(
          context: context,
          label: label,
          isLoading: isLoading,
          icon: icon,
          iconWidget: iconWidget,
        ),
      ),
    );
  }
}

/// 公共底部主按钮容器。
/// 用于把主操作按钮固定在页面底部，并统一底部留白与安全区。
class AppPrimaryActionBottomBar extends StatelessWidget {
  const AppPrimaryActionBottomBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return _primaryActionBottomBar(
      context: context,
      child: AppPrimaryActionButton(
        label: label,
        onPressed: onPressed,
        isLoading: isLoading,
      ),
    );
  }
}

/// 公共底部主按钮容器（图标 + 文字）。
/// 用于把图标主按钮固定在页面底部，并统一底部留白与安全区。
class AppPrimaryActionIconBottomBar extends StatelessWidget {
  const AppPrimaryActionIconBottomBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconWidget,
    this.isLoading = false,
  }) : assert(icon != null || iconWidget != null, '图标按钮需要传入图标');

  final String label;
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return _primaryActionBottomBar(
      context: context,
      child: AppPrimaryActionIconButton(
        label: label,
        icon: icon,
        iconWidget: iconWidget,
        onPressed: onPressed,
        isLoading: isLoading,
      ),
    );
  }
}
