import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_camera/app/app.dart';

void main() {
  // camera 插件需要 binding 初始化（权限/相机原生通道）
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: PetCameraApp()));
}
