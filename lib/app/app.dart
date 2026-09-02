import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_camera/app/ai_video_page.dart';
import 'package:pet_camera/app/primary_tab_page.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/app/pages.dart';
import 'package:pet_camera/app/retouch_page.dart';
import 'package:pet_camera/data/app_settings.dart';

class PetCameraApp extends ConsumerWidget {
  const PetCameraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '元宝拍拍',
      debugShowCheckedModeBanner: false,
      // 桌面端允许直接用鼠标拖拽滚动，保证顶部宠物展示区可左右滑动。
      scrollBehavior: const _AppScrollBehavior(),
      themeMode: ref.watch(themeModeProvider),
      theme: _buildTheme(AppTokens.light, Brightness.light),
      darkTheme: _buildTheme(AppTokens.dark, Brightness.dark),
      initialRoute: '/onboarding',
      routes: <String, WidgetBuilder>{
        // 一级页面全部收口到 PrimaryTabPage，避免底部导航在切页时丢失。
        '/onboarding': (c) => const PrimaryTabPage(initialIndex: 0),
        '/album': (c) => const PrimaryTabPage(initialIndex: 1),
        '/album-detail': (c) => const AlbumPage(),
        '/mine': (c) => const MinePage(),
        '/camera': (c) => const CameraPage(),
        '/portrait': (c) => const PortraitPage(),
        '/ai-video': (c) => const AiVideoPage(),
        '/retouch': (c) => const RetouchPage(),
        '/pet-profile': (c) => const PetProfilePage(),
        '/settings': (c) => const SettingsPage(),
      },
      // Web 刷新遇到未知地址时，统一兜底回首页。
      onUnknownRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => const PrimaryTabPage(initialIndex: 0),
        settings: const RouteSettings(name: '/onboarding'),
      ),
    );
  }

  /// 统一收口主题，确保品牌黄底组件默认使用黑色前景。
  ThemeData _buildTheme(AppTokens tokens, Brightness brightness) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: tokens.brand,
          brightness: brightness,
        ).copyWith(
          primary: tokens.brand,
          onPrimary: tokens.textPrimary,
          primaryContainer: tokens.brand,
          onPrimaryContainer: tokens.textPrimary,
          secondary: tokens.brandSoft,
          onSecondary: tokens.textPrimary,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Noto Sans SC',
      scaffoldBackgroundColor: tokens.bgBase,
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.surface,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      // 这是 APP 风格页面，全局关闭悬停和按压时的材质反馈。
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      colorScheme: colorScheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          disabledForegroundColor: tokens.textSecondary,
        ).copyWith(overlayColor: _appOverlayColor(tokens)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          disabledForegroundColor: tokens.textSecondary,
        ).copyWith(overlayColor: _appOverlayColor(tokens)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          disabledForegroundColor: tokens.textSecondary,
        ).copyWith(overlayColor: _appOverlayColor(tokens)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          disabledForegroundColor: tokens.textSecondary,
        ).copyWith(overlayColor: _appOverlayColor(tokens)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          disabledForegroundColor: tokens.textSecondary,
        ).copyWith(overlayColor: _appOverlayColor(tokens)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          borderSide: const BorderSide(color: Color(0xFF000000)),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Color(0xFF000000),
        selectionHandleColor: Color(0xFF000000),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return tokens.brand;
            }
            return tokens.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return tokens.textPrimary;
            }
            return tokens.textSecondary;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return tokens.textPrimary;
            }
            return tokens.textSecondary;
          }),
          overlayColor: _appOverlayColor(tokens),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[tokens],
    );
  }

  /// 全局去掉悬停、按压和聚焦的颜色覆盖，保持 APP 的静态点击态。
  WidgetStateProperty<Color?> _appOverlayColor(AppTokens tokens) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) {
        return Colors.transparent;
      }
      if (states.contains(WidgetState.pressed)) {
        return Colors.transparent;
      }
      if (states.contains(WidgetState.focused)) {
        return Colors.transparent;
      }
      return null;
    });
  }
}

/// 统一滚动行为，补上桌面端鼠标拖拽滚动能力。
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}
