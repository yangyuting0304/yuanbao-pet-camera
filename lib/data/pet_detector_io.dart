// 原生端实现：EfficientDet-Lite0 TFLite 推理。
//
// 输出约定（TFLite 检测后处理版，已内置 NMS）：
//   0: location [1, 25, 4]  → [ymin, xmin, ymax, xmax] 归一化
//   1: category [1, 25]     → 1-based（0 = 背景）
//   2: score    [1, 25]     → 0..1
//   3: count    [1]         → 有效条目数
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'app_env.dart';
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

/// 实时宠物检测是否启用。
///
/// Android 恒为 true。
///
/// iOS 默认**关**：宠物模式帧流每秒约 5 次调 TFLite（EfficientDet）推理，
/// 在 iOS 上触发 native 崩溃——切模式闪退修复后，实拍崩溃点后移为
/// 「进宠物模式后未拍照就闪退」，正是这里。关掉时宠物模式退回点按对焦，
/// 先保「绝不闪退」这条底线。
///
/// ## 已经试过、都没能解决它的路子（别再走一遍）
///
/// 1. **改 Strip Style / 符号保留**——无效，说明不是符号可见性问题；
/// 2. **升级 tflite_flutter 到 0.12.1**（当前最新版）——无效：两版的
///    `ios/tflite_flutter.podspec` 逐字节相同，iOS 侧固定依赖
///    `TensorFlowLiteSwift 2.12.0`，换 Dart 包并不会换掉那个 CocoaPods 依赖；
/// 3. **换 Google 官方 `litert` 包**——不存在：pub.dev 上 `litert` 404，
///    社区替代品（flutter_litert 20 star、tflite_plus 6 star）体量与维护度
///    都不足以替换生产依赖。
///
/// 也就是说：**在没有真机崩溃日志之前，这条路是走不通的**，
/// 剩下的唯一低风险路径是拿到日志（云构建验证包复现 → Xcode 符号化）
/// 再对症下药。所以这里保留编译期开关，只为让那条验证包能跑起来。
///
/// 打开方式：`--dart-define=IOS_TFLITE_ENABLED=true`，详见 [AppEnv.iosTfliteEnabled]。
bool get isAvailable {
  if (Platform.isIOS && !AppEnv.iosTfliteEnabled) return false;
  return _DetectorImpl.instance.isAvailable;
}

Future<List<PetDetection>> detect(Uint8List rgb) =>
    _DetectorImpl.instance.detect(rgb);
