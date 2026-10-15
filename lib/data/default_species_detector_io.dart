// 原生端实现：端侧 TFLite 优先 + 云端兜底。
//
// 模型：MobileNetV2 1.0x224 量化版（uint8，输入 [1,224,224,3]，
// 输出 [1,1001] 含 background），随包分发（assets/models/），
// 离线可用、零流量、无隐私顾虑。
//
// 识别策略：**全类超类聚合**——把 1001 个类别按 PetLabelMapper 关键词
// 归到 4 个物种后概率求和。ImageNet 有一百多个犬种，聚合后的置信度
// 远高于 top-1 单类，且单类误判会被同类其他项稀释。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'cloud_species_detector.dart';
import 'pet_capture_profile.dart';
import 'pet_species_detector.dart';

const String _modelAsset = 'assets/models/mobilenet_v2_1.0_224_quant.tflite';
const String _labelsAsset =
    'assets/models/labels_mobilenet_quant_v1_224.txt';
const int _inputSize = 224;

/// 单条标签进入聚合的最低概率（远低于物种判定阈值）。
const double _minLabelProb = 0.02;

/// isolate 顶层任务：JPEG 解码 + 缩放到 224x224 + 取 RGB 字节。
///
/// 解码大图是重活，必须放 isolate；Interpreter 本身不是 isolate-safe，
/// 推理留在主 isolate（224x224 量化模型推理 <50ms）。
Uint8List _preprocessTask(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return Uint8List(0);
  }
  if (decoded == null) return Uint8List(0);
  final resized = img.copyResize(
    decoded,
    width: _inputSize,
    height: _inputSize,
    interpolation: img.Interpolation.average,
  );
  return resized.getBytes(order: img.ChannelOrder.rgb);
}

class OnDeviceSpeciesDetector implements PetSpeciesDetector {
  static final OnDeviceSpeciesDetector _instance =
      OnDeviceSpeciesDetector._();
  factory OnDeviceSpeciesDetector() => _instance;
  OnDeviceSpeciesDetector._();

  Interpreter? _interpreter;
  List<String>? _labels;
  List<PetSpecies?>? _labelSpecies;
  bool _failed = false;

  /// 乐观返回 true：模型懒加载失败后置 false，本会话后续直接走云端。
  @override
  bool get isAvailable => !_failed;

  Future<void> _ensureLoaded() async {
    if (_interpreter != null || _failed) return;
    try {
      final raw = await rootBundle.load(_modelAsset);
      _interpreter = Interpreter.fromBuffer(
        raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      );
      final labelStr = await rootBundle.loadString(_labelsAsset);
      _labels = const LineSplitter().convert(labelStr);
      // 预计算 1001 个标签 → 物种的映射，推理后零扫描成本。
      _labelSpecies = _labels!
          .map((l) => PetLabelMapper.speciesOf(l))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[端侧识别] 模型加载失败，本会话退云端：$e');
      _failed = true;
      _interpreter = null;
    }
  }

  @override
  Future<PetSpeciesGuess?> detect(
    Uint8List image, {
    String? filePath,
    required int width,
    required int height,
  }) async {
    if (_failed) return null;
    try {
      await _ensureLoaded();
      final interpreter = _interpreter;
      final labelSpecies = _labelSpecies;
      if (interpreter == null || labelSpecies == null || _labels == null) {
        return null;
      }
      final rgb = await compute(_preprocessTask, image);
      if (rgb.length < _inputSize * _inputSize * 3) return null;

      final input = rgb.reshape([1, _inputSize, _inputSize, 3]);
      final output = [Uint8List(labelSpecies.length)];
      interpreter.run(input, output);

      final scored = <ImageLabelLike>[];
      final scores = output.first;
      for (var i = 0; i < scores.length; i++) {
        final p = scores[i] / 255.0;
        if (p < _minLabelProb) continue;
        scored.add((label: _labels![i], confidence: p));
      }
      return PetLabelMapper.aggregate(scored);
    } catch (e) {
      // 端侧一旦异常（模型/推理/形状不匹配），本会话不再重试，
      // 交给云端兜底——避免每张照片都重复失败一次。
      debugPrint('[端侧识别] 推理失败，退云端：$e');
      _failed = true;
      return null;
    }
  }
}

/// 平台工厂：**当前恒为「不识别」**。
///
/// ## 为什么整个物种识别被停用
///
/// 产品已收敛为**只拍猫**，物种不再是"需要判断的变量"——它恒为
/// [PetSpecies.cat]。识别带来的是纯成本，没有任何收益：
///
/// 1. **可靠性**：MobileNetV2 全类聚合在宠物特写上常常把猫判成狗
///    （ImageNet 里犬种过多，短毛猫与某些犬类的特征高度相似），
///    判错就直接套错物种参数；
/// 2. **稳定性**：tflite_flutter 的推理在 iOS 上是native 崩溃
///    （见 pet_detector_io 的同因说明），Android 上也要为每张照片多解一遍图；
/// 3. **成本**：加载 4MB 模型 + 每张图一次全尺寸解码。
///
/// 真正决定"拍得好看"的那一项——**毛色**（白毛加曝光、黑毛减曝光）——
/// 不需要模型：[PetCoatAnalyzer] 是纯颜色统计，纯 Dart、毫秒级、
/// 没有崩溃面。这才是自动识别该保留的部分，现在它单独留在
/// 「自动识别」按钮里。
///
/// 端侧与云端实现（[OnDeviceSpeciesDetector] / [CloudSpeciesDetector] /
/// [TieredSpeciesDetector]）全部保留在代码里，等产品要扩到狗/兔时开回来即可。
PetSpeciesDetector create() => const NoSpeciesDetector();
