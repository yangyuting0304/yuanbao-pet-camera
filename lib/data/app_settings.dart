import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用主题模式（浅色 / 深色 / 跟随系统）。
/// 设置页切换，MaterialApp 通过 themeMode 读取应用。
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;
  void setMode(ThemeMode m) => state = m;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
