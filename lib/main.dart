import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pet_camera/app/app.dart';
import 'package:pet_camera/data/app_font.dart';
import 'package:pet_camera/data/task_store.dart';

void main() async {
  // camera 插件需要 binding 初始化（权限/相机原生通道）
  WidgetsFlutterBinding.ensureInitialized();
  // 品牌字体与本地库并行初始化，且二者都不允许拖住首屏：
  // 字体超时降级为系统字体，本地库失败降级为内存模式。
  await Future.wait<void>(<Future<void>>[
    preloadBrandFont(),
    _initHive(),
  ]);
  runApp(const ProviderScope(child: PetCameraApp()));
}

/// 本地存储初始化；IndexedDB 偶发不稳定时不能影响启动。
Future<void> _initHive() async {
  try {
    await Hive.initFlutter();
    await Hive.openBox('growthRecords');
    await Hive.openBox(TaskStore.boxName);
  } catch (e) {
    debugPrint('Hive 初始化失败，继续以内存模式启动: $e');
  }
}
