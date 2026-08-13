import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pet_camera/app/app.dart';

void main() async {
  // camera 插件需要 binding 初始化（权限/相机原生通道）
  WidgetsFlutterBinding.ensureInitialized();
  // Web 预览里 IndexedDB 偶发不稳定；本地库失败时不阻塞 App 启动。
  try {
    await Hive.initFlutter();
    await Hive.openBox('growthRecords');
  } catch (e) {
    debugPrint('Hive 初始化失败，继续以内存模式启动: $e');
  }
  runApp(const ProviderScope(child: PetCameraApp()));
}
