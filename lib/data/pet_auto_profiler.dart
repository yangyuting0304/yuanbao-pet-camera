/// 自动配置：把「毛色分析 + 物种识别」合成一次拍摄参数设置。
///
/// 目标是**减少选择**，而不是把选择换个地方摆：
/// 用户打开相机 → 自动抓一帧 → 直接给出一套参数 → 用户只需要
/// 「确认」或「改一下」，而不是从 4×5×5 个组合里自己挑。
///
/// 设计上刻意保留 [PetAutoSetup.needsConfirmation]：
/// 置信度不足时明确提示用户确认，而不是安静地套一个可能错的参数——
/// 白毛被当成黑毛压曝光，那张照片就废了。
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'pet_capture_profile.dart';
import 'pet_coat_analyzer.dart';
import 'pet_species_detector.dart';

/// 跨 isolate 传递的毛色分析任务。
typedef PetCoatRequest = ({Uint8List bytes, int sampleTarget});

/// isolate 入口：解码 + 毛色分析。
///
/// **物种识别不放在这里**——它依赖平台能力（ML Kit / 网络请求），
/// 没法在 isolate 里跑，由调用方在主 isolate 上补上后合并。
///
/// 解码失败时返回一个低置信度的回退结果，绝不抛异常：
/// 自动识别失败只能"降级为用户手选"，不能中断拍照主流程。
PetCoatAnalysis runPetCoatAnalysis(PetCoatRequest request) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(request.bytes);
  } catch (_) {
    // img.decodeImage 遇畸形数据会抛异常而不是返回 null，必须自己兜住。
    decoded = null;
  }
  if (decoded == null) {
    return (
      coat: PetCoat.tabby,
      confidence: 0.0,
      meanLuma: 0.5,
      lightFraction: 0.0,
      darkFraction: 0.0,
      saturation: 0.0,
      reason: '图像解码失败，已回退到通用参数',
    );
  }
  final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);
  return PetCoatAnalyzer.analyze(
    rgba,
    width: decoded.width,
    height: decoded.height,
    sampleTarget: request.sampleTarget,
  );
}

/// 一次自动配置的结果。
typedef PetAutoSetup = ({
  /// 真正识别到的物种；null 表示没识别出来。
  PetSpecies? detectedSpecies,

  /// 最终采用的物种（识别失败时用兜底值）。
  PetSpecies species,

  /// 分析出的毛色。
  PetCoat coat,

  /// 毛色判定的置信度。
  double coatConfidence,

  /// 物种识别的置信度；未识别时为 0。
  double speciesConfidence,

  /// 给用户看的一句话说明（已含判定依据）。
  String summary,

  /// 是否建议用户确认一下。
  bool needsConfirmation,
});

/// 自动配置器。
class PetAutoProfiler {
  PetAutoProfiler._();

  /// 低于此置信度就提示用户确认。
  static const double confirmBelow = 0.55;

  /// 合成自动配置结果。
  ///
  /// [speciesGuess] 为 null 表示没有可用的物种识别能力（例如网页端），
  /// 此时沿用 [fallbackSpecies]，并把 `needsConfirmation` 置为 true ——
  /// 物种没识别出来是确定的事实，必须让用户知道。
  static PetAutoSetup resolve({
    required PetCoatAnalysis coat,
    PetSpeciesGuess? speciesGuess,
    required PetSpecies fallbackSpecies,
  }) {
    final detected = speciesGuess?.species;
    final species = detected ?? fallbackSpecies;
    final speciesConfidence = speciesGuess?.confidence ?? 0.0;

    final needsConfirmation =
        coat.confidence < confirmBelow || speciesConfidence < confirmBelow;

    return (
      detectedSpecies: detected,
      species: species,
      coat: coat.coat,
      coatConfidence: coat.confidence,
      speciesConfidence: speciesConfidence,
      summary: _summary(
        species: species,
        detected: detected,
        coat: coat,
      ),
      needsConfirmation: needsConfirmation,
    );
  }

  /// 直接生成参数集，省得调用方再拼一次。
  static PetCaptureProfile toProfile(
    PetAutoSetup setup, {
    PetScene scene = PetScene.portrait,
  }) => PetCaptureProfile.resolve(
    species: setup.species,
    coat: setup.coat,
    scene: scene,
  );

  static String _summary({
    required PetSpecies species,
    required PetSpecies? detected,
    required PetCoatAnalysis coat,
  }) {
    final head = detected != null
        ? '识别到${detected.label}'
        : '未识别出物种，暂按${species.label}参数';
    return '$head；${coat.reason}（毛色置信度 ${(coat.confidence * 100).round()}%）';
  }
}
