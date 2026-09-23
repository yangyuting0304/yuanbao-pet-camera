// 页面库宿主（library host）。
//
// 本文件现在只保留三样东西：
//   1. 各页面的**公共 import 集合**（part 文件自己不能写 import，全靠这里）；
//   2. 五个页面 part 的声明；
//   3. 二级页公共外壳 `_Shell` —— 被「成长手记 / AI 写真 / 设置」三页复用。
//
// 页面实体都在同目录下：camera_page.dart、portrait_page.dart、
// album_page.dart、pet_profile_page.dart、settings_page.dart。
// 为什么用 part 而不是各自独立的 library，见 camera_page.dart 顶部说明。
//
// 原 8631 行的巨型 pages.dart 已于 2026-09 完成拆分；其中约 1245 行
// （旧首页 OnboardingPage 及其全套组件、旧底栏 _InsBottomNav）经确认
// 零引用后删除 —— 首页早已由 primary_tab_page.dart 接管。
import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pet_camera/app/album_import.dart';
import 'package:pet_camera/app/app_image.dart';
import 'package:pet_camera/app/app_generated_result_page.dart';
import 'package:pet_camera/app/app_primary_action_button.dart';
import 'package:pet_camera/app/app_photo_preview_panel.dart';
import 'package:pet_camera/app/app_back_button.dart';
import 'package:pet_camera/app/app_loading_view.dart';
import 'package:pet_camera/app/app_top_nav_bar.dart';
import 'package:pet_camera/app/beian_footer.dart';
import 'package:pet_camera/app/live_player.dart';
import 'package:pet_camera/app/media_platform.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/ai_portrait_service.dart';
import 'package:pet_camera/data/burst_selector.dart';
import 'package:pet_camera/data/camera_capability.dart';
import 'package:pet_camera/data/camera_frame.dart';
import 'package:pet_camera/data/captured_photos.dart';
import 'package:pet_camera/data/default_species_detector.dart';
import 'package:pet_camera/data/frame_fusion.dart';
import 'package:pet_camera/data/live_photo.dart';
import 'package:pet_camera/data/lure_sound_player.dart';
import 'package:pet_camera/data/pet_auto_profiler.dart';
import 'package:pet_camera/data/pet_capture_profile.dart';
import 'package:pet_camera/data/pet_detector.dart';
import 'package:pet_camera/data/pet_eye_detector.dart';
import 'package:pet_camera/data/pet_filter.dart';
import 'package:pet_camera/data/pet_species_detector.dart';
import 'package:pet_camera/data/photo_saver.dart';
import 'package:pet_camera/data/photo_storage.dart';
import 'package:pet_camera/data/short_videos.dart';
import 'package:pet_camera/data/app_settings.dart';
import 'package:pet_camera/data/models.dart';
import 'package:pet_camera/data/seed_repository.dart';
import 'package:pet_camera/data/growth_records.dart';
import 'package:pet_camera/data/library_service.dart';

part 'camera_page.dart';

part 'portrait_page.dart';
part 'album_page.dart';
part 'pet_profile_page.dart';
part 'settings_page.dart';

/// 统一页面外壳：二级页顶栏统一提供返回入口。
class _Shell extends StatelessWidget {
  const _Shell({
    required this.title,
    required this.body,
    this.backgroundColor,
    this.appBarBackgroundColor,
    this.bottomBar,
  });

  final String title;
  final Widget body;
  final Color? backgroundColor;
  final Color? appBarBackgroundColor;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 44,
        leading: AppBackButton(
          onTap: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
          },
        ),
        centerTitle: true,
        title: Text(
          title,
          style: TextStyle(
            fontSize: AppUi.fontTitle,
            height: AppUi.lineHeight(AppUi.fontTitle),
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: appBarBackgroundColor ?? t.surface,
        foregroundColor: t.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      backgroundColor: backgroundColor ?? t.bgBase,
      body: body,
      bottomNavigationBar: bottomBar,
    );
  }
}
