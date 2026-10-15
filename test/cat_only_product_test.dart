// 「只拍猫」产品收敛的契约测试。
//
// 收敛内容：物种维度对用户不可见、恒为猫；端侧与云端物种识别全部停用。
//
// 这些不是实现细节，而是**产品承诺**：用户按「自动判断毛色」时不该被
// 反问"识别出是狗还是猫"；App 也不该为了一个常量去加载 4MB 模型、
// 在 iOS 上冒native 崩溃的风险、或把用户的猫照片传到云端去识别。
//
// 测试放在 data 层（工厂返回什么），因为那正是两个平台共用的收敛点。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/default_species_detector.dart';
import 'package:pet_camera/data/pet_auto_profiler.dart';
import 'package:pet_camera/data/pet_capture_profile.dart';
import 'package:pet_camera/data/pet_coat_analyzer.dart';

void main() {
  group('物种识别已停用', () {
    test('工厂返回的识别器恒为不可用', () {
      final detector = createDefaultSpeciesDetector();
      expect(detector.isAvailable, isFalse);
    });

    test('即使被调用也只会返回 null，绝不联网、绝不上传', () async {
      final detector = createDefaultSpeciesDetector();
      final guess = await detector.detect(
        Uint8List.fromList([1, 2, 3, 4]),
        width: 2,
        height: 1,
      );
      expect(guess, isNull);
    });
  });

  group('只拍猫：参数集恒以猫为物种', () {
    test('白毛仍按猫的曝光基准加 EV（毛色维度没被砍掉）', () {
      final profile = PetCaptureProfile.resolve(
        species: PetSpecies.cat,
        coat: PetCoat.white,
        scene: PetScene.portrait,
      );
      expect(profile.species, PetSpecies.cat);
      expect(
        profile.exposureCompensation,
        greaterThan(0),
        reason: '白毛被拍成灰毛是宠物摄影第一翻车点，必须加曝光',
      );
    });

    test('自动配置在没有识别结果时也落到猫', () {
      final setup = PetAutoProfiler.resolve(
        coat: _whiteCoat(),
        speciesGuess: null,
        fallbackSpecies: PetSpecies.cat,
      );
      expect(setup.species, PetSpecies.cat);
      expect(setup.detectedSpecies, isNull);
    });
  });
}

/// 高置信度的白毛分析结果（直接用分类器，避免为了一个常量去解码图片）。
PetCoatAnalysis _whiteCoat() => PetCoatAnalyzer.classify(
  meanLuma: 0.9,
  saturation: 0.02,
  lightFraction: 0.95,
  darkFraction: 0,
);