import 'package:flutter/material.dart';

/// 设计 Token（Spec §8 锁定）：暖橘 brand + 深青 ink 双色，禁紫粉渐变。
/// 全部颜色经 Token 引用，禁止硬编码。
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brand,
    required this.brandSoft,
    required this.ink,
    required this.bgBase,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
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
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  static const light = AppTokens(
    brand: Color(0xFFF2864B),
    brandSoft: Color(0xFFFAD9C6),
    ink: Color(0xFF1F6F6B),
    bgBase: Color(0xFFFAF7F2),
    surface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF2B2622),
    textSecondary: Color(0xFF7A726A),
    success: Color(0xFF3F8F5B),
    warning: Color(0xFFE0A33C),
    error: Color(0xFFC8503C),
    info: Color(0xFF2E7D8A),
  );

  static const dark = AppTokens(
    brand: Color(0xFFF4975C),
    brandSoft: Color(0xFF5A3A2C),
    ink: Color(0xFF2E8B86),
    bgBase: Color(0xFF181614),
    surface: Color(0xFF242120),
    textPrimary: Color(0xFFF2ECE2),
    textSecondary: Color(0xFFA89E94),
    success: Color(0xFF3F8F5B),
    warning: Color(0xFFE0A33C),
    error: Color(0xFFC8503C),
    info: Color(0xFF2E7D8A),
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
