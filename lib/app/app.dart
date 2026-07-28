import 'package:flutter/material.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/app/pages.dart';

class PetCameraApp extends StatelessWidget {
  const PetCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '元宝拍拍',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Poppins',
        fontFamilyFallback: const ['Noto Sans SC'],
        scaffoldBackgroundColor: AppTokens.light.bgBase,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTokens.light.brand,
          brightness: Brightness.light,
        ),
        extensions: const <ThemeExtension<dynamic>>[AppTokens.light],
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Poppins',
        fontFamilyFallback: const ['Noto Sans SC'],
        scaffoldBackgroundColor: AppTokens.dark.bgBase,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTokens.dark.brand,
          brightness: Brightness.dark,
        ),
        extensions: const <ThemeExtension<dynamic>>[AppTokens.dark],
      ),
      initialRoute: '/onboarding',
      routes: <String, WidgetBuilder>{
        '/onboarding': (c) => const OnboardingPage(),
        '/camera': (c) => const CameraPage(),
        '/portrait': (c) => const PortraitPage(),
        '/album': (c) => const AlbumPage(),
        '/short-video': (c) => const ShortVideoPage(),
        '/retouch': (c) => const RetouchPage(),
        '/pet-profile': (c) => const PetProfilePage(),
        '/settings': (c) => const SettingsPage(),
      },
    );
  }
}
