// 物种识别纯逻辑 —— 排除表 / 超类聚合 / 级联识别器。
//
// 端侧 MobileNetV2 是 ImageNet 1001 类模型，本组测试锁死三件事：
// 1. 含 'cat'/'dog' 字样的非宠物类（毛虫/热狗等）不参与聚合；
// 2. 超类聚合：同类多个品种的概率加总，总分决定物种；
// 3. 级联：端侧失败/异常时必须退到云端，且异常绝不外抛。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/pet_capture_profile.dart';
import 'package:pet_camera/data/pet_species_detector.dart';

ImageLabelLike _lbl(String label, double confidence) =>
    (label: label, confidence: confidence);

/// 可编程的假识别器。
class FakeDetector implements PetSpeciesDetector {
  FakeDetector({required this.available, this.result, this.thrower});

  final bool available;
  final PetSpeciesGuess? result;
  final Exception? thrower;
  int calls = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<PetSpeciesGuess?> detect(
    Uint8List image, {
    String? filePath,
    required int width,
    required int height,
  }) async {
    calls++;
    if (thrower != null) throw thrower!;
    return result;
  }
}

void main() {
  group('排除表：含 cat/dog 字样的非宠物类不参与判定', () {
    test('caterpillar / catfish / hot dog 均不映射', () {
      expect(PetLabelMapper.speciesOf('caterpillar'), isNull);
      expect(PetLabelMapper.speciesOf('catfish'), isNull);
      expect(PetLabelMapper.speciesOf('catamaran'), isNull);
      expect(PetLabelMapper.speciesOf('hot dog'), isNull);
      expect(PetLabelMapper.speciesOf('dogwood'), isNull);
    });

    test('真正的猫狗类不受排除影响', () {
      expect(PetLabelMapper.speciesOf('Egyptian cat'), PetSpecies.cat);
      expect(PetLabelMapper.speciesOf('tiger cat'), PetSpecies.cat);
      expect(PetLabelMapper.speciesOf('golden retriever'), PetSpecies.dog);
      expect(PetLabelMapper.speciesOf('chinchilla'), PetSpecies.chinchilla);
      expect(PetLabelMapper.speciesOf('hare'), PetSpecies.rabbit);
    });
  });

  group('超类聚合：同类概率加总', () {
    test('多个犬种加总后判定为狗，且总分高于任何单类', () {
      final guess = PetLabelMapper.aggregate([
        _lbl('golden retriever', 0.30),
        _lbl('Labrador retriever', 0.20),
        _lbl('toy poodle', 0.15),
        _lbl('tabby cat', 0.25),
        _lbl('tent', 0.10),
      ]);
      expect(guess, isNotNull);
      expect(guess!.species, PetSpecies.dog);
      expect(guess.confidence, closeTo(0.65, 0.001));
      expect(guess.matchedLabel, 'golden retriever', reason: '应记录同类内最高分标签');
    });

    test('单类小概率噪声不会被聚合误判', () {
      // 'Egyptian cat' 0.03 与大量无关类：聚合只收宠物类。
      final guess = PetLabelMapper.aggregate([
        _lbl('Egyptian cat', 0.03),
        _lbl('lakeshore', 0.60),
        _lbl('tripod', 0.30),
      ]);
      expect(guess, isNotNull);
      expect(guess!.species, PetSpecies.cat);
      expect(guess.confidence, closeTo(0.03, 0.001));
    });

    test('全部低于门槛时返回 null', () {
      expect(
        PetLabelMapper.aggregate([
          _lbl('tabby cat', 0.01),
          _lbl('tent', 0.90),
        ]),
        isNull,
      );
    });

    test('空输入返回 null', () {
      expect(PetLabelMapper.aggregate(const []), isNull);
    });
  });

  group('级联识别器：端侧失败退云端，异常不外抛', () {
    final image = Uint8List(16);

    PetSpeciesGuess guessOf(PetSpecies s) =>
        (species: s, confidence: 0.9, matchedLabel: 'test');

    test('主识别器成功时备用不被调用', () async {
      final primary = FakeDetector(available: true, result: guessOf(PetSpecies.cat));
      final fallback = FakeDetector(available: true);
      final tiered = TieredSpeciesDetector(primary, fallback);
      final r = await tiered.detect(image, width: 0, height: 0);
      expect(r!.species, PetSpecies.cat);
      expect(fallback.calls, 0);
    });

    test('主识别器返回 null 时退到备用', () async {
      final primary = FakeDetector(available: true, result: null);
      final fallback = FakeDetector(available: true, result: guessOf(PetSpecies.dog));
      final tiered = TieredSpeciesDetector(primary, fallback);
      final r = await tiered.detect(image, width: 0, height: 0);
      expect(r!.species, PetSpecies.dog);
      expect(fallback.calls, 1);
    });

    test('主识别器抛异常时退到备用且异常不外抛', () async {
      final primary = FakeDetector(
        available: true,
        thrower: TimeoutException('端侧超时'),
      );
      final fallback = FakeDetector(available: true, result: guessOf(PetSpecies.rabbit));
      final tiered = TieredSpeciesDetector(primary, fallback);
      final r = await tiered.detect(image, width: 0, height: 0);
      expect(r!.species, PetSpecies.rabbit);
      expect(fallback.calls, 1);
    });

    test('两侧都不可用 → isAvailable 为 false 且返回 null', () async {
      final tiered = TieredSpeciesDetector(
        FakeDetector(available: false),
        FakeDetector(available: false),
      );
      expect(tiered.isAvailable, isFalse);
      expect(await tiered.detect(image, width: 0, height: 0), isNull);
    });
  });
}
