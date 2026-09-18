/// 宠物实时检测（帧流上用），输出位置框 —— 「自动捕捉宠物」的感知层。
///
/// 模型：EfficientDet-Lite0（320×320，COCO 80 类，TFLite 量化版 4.3MB）。
/// 与物种识别（[PetSpeciesDetector]）的分工：
///   - 物种识别：静态图片、会话一次，回答"这是什么宠物"（决定拍摄参数）
///   - 本检测器：实时帧流、每秒数次，回答"宠物在哪"（决定对焦与跟踪）
///
/// COCO 不含兔/龙猫，所以这两类宠物的自动对焦会退回"画面中心"策略。
library;

import 'dart:typed_data';

import 'pet_detector_stub.dart'
    if (dart.library.io) 'pet_detector_io.dart' as impl;

/// 模型输入边长（EfficientDet-Lite0 固定 320）。
const int kDetectorInputSize = 320;

/// 一个检测到的目标框（归一化坐标，原点在左上角）。
class PetDetection {
  const PetDetection({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
    required this.label,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
  final double confidence;
  final String label;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;

  @override
  String toString() =>
      '$label(${confidence.toStringAsFixed(2)}) '
      '[${left.toStringAsFixed(2)},${top.toStringAsFixed(2)},'
      '${right.toStringAsFixed(2)},${bottom.toStringAsFixed(2)}]';
}

/// COCO 类别索引 ⇄ 标签（纯逻辑，可单测）。
class CocoLabels {
  CocoLabels._();

  /// 我们关心的类别，键是 **COCO 0-based 索引**。
  ///
  /// 收录猫狗之外的家养动物，是因为模型本来就认得，多认几种不增加成本。
  static const Map<int, String> interesting = {
    14: '鸟',
    15: '猫',
    16: '狗',
    17: '马',
    18: '羊',
    19: '牛',
  };

  /// 把模型输出的类别号翻译成标签；非目标类别返回 null。
  ///
  /// ⚠️ **TFLite 的 EfficientDet 输出类别从 1 开始**（0 表示背景），
  /// 而 COCO 官方列表是 0-based —— 差这一个偏移，狗就会被认成猫。
  static String? labelOf(int rawCategory) => interesting[rawCategory - 1];
}

abstract final class PetDetector {
  /// 模型是否可用（加载失败后恒为 false，上层直接跳过跟踪）。
  static bool get isAvailable => impl.isAvailable;

  /// 传入 [kDetectorInputSize]² × 3 的 RGB 字节，返回按置信度降序的框。
  static Future<List<PetDetection>> detect(Uint8List rgb) => impl.detect(rgb);
}
