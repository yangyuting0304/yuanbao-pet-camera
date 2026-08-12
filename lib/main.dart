import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pet_camera/app/app.dart';

void main() async {
  // camera 插件需要 binding 初始化（权限/相机原生通道）
  WidgetsFlutterBinding.ensureInitialized();
  // 成长手记本地持久化（Hive）
  await Hive.initFlutter();
  await Hive.openBox('growthRecords');
  runApp(const ProviderScope(child: PetCameraApp()));
}
