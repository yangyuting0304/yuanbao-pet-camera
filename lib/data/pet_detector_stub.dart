// Web / 兜底：TFLite 在浏览器不可用，不做实时跟踪（相机页会跳过跟踪逻辑）。
import 'dart:typed_data';

import 'pet_detector.dart';

bool get isAvailable => false;

Future<List<PetDetection>> detect(Uint8List rgb) async => const [];
