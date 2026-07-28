import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用户拍摄的照片（切片2：拍照后存入应用内相册）。
/// Web/Android 统一用内存态的字节流，跨页面可见；
/// 后续接入 Drift / 系统相册(gal) 时可直接映射，无需改动 UI 层。
class CapturedPhoto {
  const CapturedPhoto({required this.bytes, required this.takenAt});
  final Uint8List bytes;
  final DateTime takenAt;
}

/// 拍摄照片状态：最新拍摄排在列表最前。
class CapturedPhotosNotifier extends Notifier<List<CapturedPhoto>> {
  @override
  List<CapturedPhoto> build() => const [];

  void add(Uint8List bytes) {
    state = [CapturedPhoto(bytes: bytes, takenAt: DateTime.now()), ...state];
  }

  void clear() => state = const [];
}

final capturedPhotosProvider =
    NotifierProvider<CapturedPhotosNotifier, List<CapturedPhoto>>(
  CapturedPhotosNotifier.new,
);
