import 'package:flutter/material.dart';

/// 设计 Token。
/// 全部颜色经 Token 引用，避免页面层继续写散色值。
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brand,
    required this.brandSoft,
    required this.ink,
    required this.bgBase,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  final Color brand;
  final Color brandSoft;
  final Color ink;
  final Color bgBase;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  static const light = AppTokens(
    // 产品主色统一改为 FEDE2C。
    brand: Color(0xFFFEDE2C),
    // 辅助色统一改为 79FAC3。
    brandSoft: Color(0xFF79FAC3),
    ink: Color(0xFF79FAC3),
    // 页面背景统一改为 F6F8FA。
    bgBase: Color(0xFFF6F8FA),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF999999),
    textTertiary: Color(0xFFB4B4B4),
    success: Color(0xFF15C87D),
    warning: Color(0xFFFF4E62),
    error: Color(0xFFFF4E62),
    info: Color(0xFF4DA6FF),
  );

  static const dark = AppTokens(
    // 深色模式先沿用同一套品牌色，避免主题切换后语义跑偏。
    brand: Color(0xFFFEDE2C),
    brandSoft: Color(0xFF79FAC3),
    ink: Color(0xFF79FAC3),
    bgBase: Color(0xFFF6F8FA),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF999999),
    textTertiary: Color(0xFFB4B4B4),
    success: Color(0xFF15C87D),
    warning: Color(0xFFFF4E62),
    error: Color(0xFFFF4E62),
    info: Color(0xFF4DA6FF),
  );

  @override
  AppTokens copyWith({
    Color? brand,
    Color? brandSoft,
    Color? ink,
    Color? bgBase,
    Color? surface,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
  }) {
    return AppTokens(
      brand: brand ?? this.brand,
      brandSoft: brandSoft ?? this.brandSoft,
      ink: ink ?? this.ink,
      bgBase: bgBase ?? this.bgBase,
      surface: surface ?? this.surface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      brand: Color.lerp(brand, other.brand, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      bgBase: Color.lerp(bgBase, other.bgBase, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

extension AppTokensX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}

/// 全局 UI 规范常量。
/// 所有页面统一使用这里的尺寸，避免每个文件重复写字面值。
abstract final class AppUi {
  /// 图标尺寸只保留 16 / 20 / 24 三档。
  static const double iconSmall = 16;
  static const double iconMedium = 20;
  static const double iconLarge = 24;

  /// 页面左右留白统一为 16。
  static const double pagePadding = 16;

  /// 字号只保留 12 / 14 / 16 / 20 四档。
  static const double fontCaption = 12;
  static const double fontBody = 14;
  static const double fontTitle = 16;
  static const double fontHeadline = 20;

  /// 间距统一使用 4 的倍数，最小 4，最大 32。
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space28 = 28;
  static const double space32 = 32;

  /// 所有卡片圆角统一为 16。
  static const double radiusCard = 16;

  /// 行高统一按“字号 + 8”计算。
  static double lineHeight(double fontSize) => (fontSize + 8) / fontSize;
}

/// 页面层常用的基础颜色常量。
abstract final class AppColors {
  static const Color pageBackground = Color(0xFFF6F8FA);
  static const Color divider = Color(0xFFF0ECE6);
  static const Color iconPlate = Color(0x80000000);
}
