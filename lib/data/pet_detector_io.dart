// 原生端实现：EfficientDet-Lite0 TFLite 推理。
//
// 输出约定（TFLite 检测后处理版，已内置 NMS）：
//   0: location [1, 25, 4]  → [ymin, xmin, ymax, xmax] 归一化
//   1: category [1, 25]     → 1-based（0 = 背景）
//   2: score    [1, 25]     → 0..1
//   3: count    [1]         → 有效条目数
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'pet_detector.dart';

const String _modelAsset = 'assets/models/efficientdet_lite0_320.tflite';

/// EfficientDet-Lite0 的固定输出条目数。
const int _maxDetections = 25;

/// 低于此置信度的框丢弃。0.45 是实测"不漏宠物、少误检"的折中：
/// 调高会漏掉背对镜头/局部遮挡的猫，调低会把沙发靠垫认成猫。
const double _minScore = 0.45;

class _DetectorImpl {
  static final _DetectorImpl instance = _DetectorImpl._();
  _DetectorImpl._();

  Interpreter? _interpreter;
  bool _failed = false;

  bool get isAvailable => !_failed;

  Future<void> _ensureLoaded() async {
    if (_interpreter != null || _failed) return;
    try {
      final raw = await rootBundle.load(_modelAsset);
      _interpreter = Interpreter.fromBuffer(
        raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      );
    } catch (e) {
      debugPrint('[宠物跟踪] 检测模型加载失败，本次会话不再跟踪：$e');
      _failed = true;
    }
  }

  Future<List<PetDetection>> detect(Uint8List rgb) async {
    if (_failed) return const [];
    try {
      await _ensureLoaded();
      final interpreter = _interpreter;
      if (interpreter == null) return const [];
      if (rgb.length < kDetectorInputSize * kDetectorInputSize * 3) {
        return const [];
      }

      final input = rgb.reshape([1, kDetectorInputSize, kDetectorInputSize, 3]);
      final locations = [
        List.generate(_maxDetections, (_) => List<double>.filled(4, 0.0)),
      ];
      final categories = [List<double>.filled(_maxDetections, 0.0)];
      final scores = [List<double>.filled(_maxDetections, 0.0)];
      final count = [0.0];

      interpreter.runForMultipleInputs([input], {
        0: locations,
        1: categories,
        2: scores,
        3: count,
      });

      final total = count[0].toInt().clamp(0, _maxDetections);
      final found = <PetDetection>[];
      for (var i = 0; i < total; i++) {
        final score = scores[0][i];
        if (score < _minScore) continue;
        final label = CocoLabels.labelOf(categories[0][i].round());
        if (label == null) continue;
        final box = locations[0][i];
        found.add(
          PetDetection(
            top: box[0].clamp(0.0, 1.0),
            left: box[1].clamp(0.0, 1.0),
            bottom: box[2].clamp(0.0, 1.0),
            right: box[3].clamp(0.0, 1.0),
            confidence: score.clamp(0.0, 1.0),
            label: label,
          ),
        );
      }
      // 同框多目标时按置信度排序，上层取第一个作为跟踪主体。
      found.sort((a, b) => b.confidence.compareTo(a.confidence));
      return found;
    } catch (e) {
      debugPrint('[宠物跟踪] 推理失败：$e');
      return const [];
    }
  }
}

bool get isAvailable => _DetectorImpl.instance.isAvailable;

Future<List<PetDetection>> detect(Uint8List rgb) =>
    _DetectorImpl.instance.detect(rgb);
