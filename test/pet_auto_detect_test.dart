// 自动识别（毛色 + 物种 + 自动配置）—— 单元测试。
//
// 毛色判定反了后果最严重：白毛会被按黑毛压曝光、黑毛会被按白毛提亮，
// 两种都是直接毁片。所以这里既测分类边界，也用合成图测真实输入，
// 还专门测"背景占比大"这类会把朴素做法带偏的场景。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/pet_auto_profiler.dart';
import 'package:pet_camera/data/pet_capture_profile.dart';
import 'package:pet_camera/data/pet_coat_analyzer.dart';
import 'package:pet_camera/data/pet_species_detector.dart';

/// 造纯色 RGBA 图。
Uint8List _solid(int w, int h, int r, int g, int b) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = 255;
  }
  return out;
}

/// 在底图上画一个居中的矩形块。
Uint8List _boxIn(
  int w,
  int h, {
  required int from,
  required int to,
  required List<int> bg,
  required List<int> fg,
}) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final inside = x >= from && x <= to && y >= from && y <= to;
      final c = inside ? fg : bg;
      final o = (y * w + x) * 4;
      out[o] = c[0];
      out[o + 1] = c[1];
      out[o + 2] = c[2];
      out[o + 3] = 255;
    }
  }
  return out;
}

/// 造左右两色的图，用于验证"花色"判定。
Uint8List _twoTone(int w, int h, List<int> left, List<int> right) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = x < w ~/ 2 ? left : right;
      final o = (y * w + x) * 4;
      out[o] = c[0];
      out[o + 1] = c[1];
      out[o + 2] = c[2];
      out[o + 3] = 255;
    }
  }
  return out;
}

void main() {
  group('毛色分类边界', () {
    test('很亮 → 白/奶油毛', () {
      final r = PetCoatAnalyzer.classify(
        meanLuma: 0.85,
        saturation: 0.05,
        lightFraction: 0.95,
        darkFraction: 0.0,
      );
      expect(r.coat, PetCoat.white);
      expect(r.confidence, greaterThan(0.3));
    });

    test('很暗 → 黑/深毛', () {
      final r = PetCoatAnalyzer.classify(
        meanLuma: 0.12,
        saturation: 0.05,
        lightFraction: 0.0,
        darkFraction: 0.95,
      );
      expect(r.coat, PetCoat.black);
    });

    test('中灰且低饱和 → 蓝灰/纯色亮毛', () {
      final r = PetCoatAnalyzer.classify(
        meanLuma: 0.45,
        saturation: 0.08,
        lightFraction: 0.0,
        darkFraction: 0.05,
      );
      expect(r.coat, PetCoat.blueGrey);
    });

    test('中亮且有颜色 → 虎斑/橘/三花', () {
      final r = PetCoatAnalyzer.classify(
        meanLuma: 0.45,
        saturation: 0.45,
        lightFraction: 0.05,
        darkFraction: 0.05,
      );
      expect(r.coat, PetCoat.tabby);
    });

    test('深浅各占一半 → 花色（优先级最高）', () {
      final r = PetCoatAnalyzer.classify(
        meanLuma: 0.5,
        saturation: 0.05,
        lightFraction: 0.5,
        darkFraction: 0.5,
      );
      expect(
        r.coat,
        PetCoat.multi,
        reason: '再"平均亮度居中"也要先判花色，否则黑白猫会被判走',
      );
    });

    test('只有少量暗部不足以判花色（避免把黑背景当花毛）', () {
      final r = PetCoatAnalyzer.classify(
        meanLuma: 0.8,
        saturation: 0.05,
        lightFraction: 0.85,
        darkFraction: 0.15,
      );
      expect(r.coat, PetCoat.white);
    });

    test('置信度恒在 0.30~0.95（不做"百分之百确定"的承诺）', () {
      final samples = [
        PetCoatAnalyzer.classify(
          meanLuma: 1.0,
          saturation: 0,
          lightFraction: 1,
          darkFraction: 0,
        ),
        PetCoatAnalyzer.classify(
          meanLuma: 0.0,
          saturation: 0,
          lightFraction: 0,
          darkFraction: 1,
        ),
        PetCoatAnalyzer.classify(
          meanLuma: 0.5,
          saturation: 0,
          lightFraction: 0,
          darkFraction: 0.01,
        ),
        PetCoatAnalyzer.classify(
          meanLuma: 0.5,
          saturation: 1,
          lightFraction: 1,
          darkFraction: 1,
        ),
      ];
      for (final s in samples) {
        expect(s.confidence, inInclusiveRange(0.30, 0.95));
      }
    });

    test('贴着判定边界时置信度低（提示用户确认）', () {
      final r = PetCoatAnalyzer.classify(
        meanLuma: 0.5,
        saturation: 0.3,
        lightFraction: 0.22,
        darkFraction: 0.22,
      );
      expect(r.confidence, lessThan(PetAutoProfiler.confirmBelow));
    });

    test('每个结果都带一句可展示的解释', () {
      final samples = [
        PetCoatAnalyzer.classify(
          meanLuma: 0.9,
          saturation: 0,
          lightFraction: 1,
          darkFraction: 0,
        ),
        PetCoatAnalyzer.classify(
          meanLuma: 0.1,
          saturation: 0,
          lightFraction: 0,
          darkFraction: 1,
        ),
        PetCoatAnalyzer.classify(
          meanLuma: 0.5,
          saturation: 0.01,
          lightFraction: 0,
          darkFraction: 0,
        ),
        PetCoatAnalyzer.classify(
          meanLuma: 0.5,
          saturation: 0.5,
          lightFraction: 0,
          darkFraction: 0,
        ),
        PetCoatAnalyzer.classify(
          meanLuma: 0.5,
          saturation: 0.5,
          lightFraction: 0.6,
          darkFraction: 0.6,
        ),
      ];
      for (final s in samples) {
        expect(s.reason, isNotEmpty);
      }
    });
  });

  group('毛色分析（真实图像输入）', () {
    test('浅色图 → 白毛', () {
      final r = PetCoatAnalyzer.analyze(
        _solid(64, 64, 230, 228, 222),
        width: 64,
        height: 64,
      );
      expect(r.coat, PetCoat.white);
    });

    test('深色图 → 黑毛', () {
      final r = PetCoatAnalyzer.analyze(
        _solid(64, 64, 28, 28, 32),
        width: 64,
        height: 64,
      );
      expect(r.coat, PetCoat.black);
    });

    test('中性灰图 → 蓝灰毛', () {
      final r = PetCoatAnalyzer.analyze(
        _solid(64, 64, 128, 130, 134),
        width: 64,
        height: 64,
      );
      expect(r.coat, PetCoat.blueGrey);
    });

    test('暖橘图 → 虎斑/橘毛', () {
      final r = PetCoatAnalyzer.analyze(
        _solid(64, 64, 205, 140, 78),
        width: 64,
        height: 64,
      );
      expect(r.coat, PetCoat.tabby);
    });

    test('黑白各半 → 花色', () {
      final r = PetCoatAnalyzer.analyze(
        _twoTone(64, 64, [240, 240, 240], [16, 16, 16]),
        width: 64,
        height: 64,
      );
      expect(r.coat, PetCoat.multi);
    });

    test('统计量合理：浅图亮度高于深图', () {
      final light = PetCoatAnalyzer.analyze(
        _solid(32, 32, 220, 220, 220),
        width: 32,
        height: 32,
      );
      final dark = PetCoatAnalyzer.analyze(
        _solid(32, 32, 30, 30, 30),
        width: 32,
        height: 32,
      );
      expect(light.meanLuma, greaterThan(dark.meanLuma));
    });

    test('图像过小时安全回退，不抛异常', () {
      final r = PetCoatAnalyzer.analyze(Uint8List(4), width: 1, height: 1);
      expect(r.confidence, 0);
      expect(r.reason, isNotEmpty);
    });

    test('黑色背景里的白猫仍判为白毛（中心加权起作用）', () {
      // 白猫只占画面 40%，但位于正中；朴素等权平均会被黑背景拉低。
      final r = PetCoatAnalyzer.analyze(
        _boxIn(
          80,
          80,
          from: 24,
          to: 55,
          bg: [20, 20, 20],
          fg: [235, 235, 232],
        ),
        width: 80,
        height: 80,
      );
      expect(
        r.coat,
        PetCoat.white,
        reason: '必须只信画面中心，否则黑背景会把白猫判成黑毛或花色',
      );
      expect(r.lightFraction, greaterThan(r.darkFraction));
    });

    test('宠物占画面一半时，黑背景也不会干扰判定', () {
      final r = PetCoatAnalyzer.analyze(
        _boxIn(
          80,
          80,
          from: 20,
          to: 59,
          bg: [18, 18, 18],
          fg: [238, 236, 230],
        ),
        width: 80,
        height: 80,
      );
      expect(r.coat, PetCoat.white);
      expect(r.lightFraction, greaterThan(0.8));
    });

    test('宠物太小（仅占画面 25%）时降置信度，而不是硬猜一个结果', () {
      final r = PetCoatAnalyzer.analyze(
        _boxIn(
          80,
          80,
          from: 30,
          to: 49,
          bg: [18, 18, 18],
          fg: [238, 236, 230],
        ),
        width: 80,
        height: 80,
      );
      // 主体在画面里太小时，任何基于亮度统计的方法都会被背景主导。
      // 正确的产品行为不是"猜对"，而是**如实降低置信度、提示用户确认**——
      // 悄悄套一套错的参数比报个不确定更糟。
      expect(
        r.confidence,
        lessThan(PetAutoProfiler.confirmBelow),
        reason: '判不准就应该说判不准',
      );
    });
  });

  group('物种标签映射', () {
    test('基础标签', () {
      expect(PetLabelMapper.speciesOf('cat'), PetSpecies.cat);
      expect(PetLabelMapper.speciesOf('Dog'), PetSpecies.dog);
      expect(PetLabelMapper.speciesOf('rabbit'), PetSpecies.rabbit);
      expect(PetLabelMapper.speciesOf('chinchilla'), PetSpecies.chinchilla);
    });

    test('细分标签也能归到正确物种', () {
      expect(PetLabelMapper.speciesOf('golden retriever'), PetSpecies.dog);
      expect(PetLabelMapper.speciesOf('kitten'), PetSpecies.cat);
      expect(PetLabelMapper.speciesOf('corgi'), PetSpecies.dog);
      expect(PetLabelMapper.speciesOf('maine coon'), PetSpecies.cat);
      expect(PetLabelMapper.speciesOf('bunny'), PetSpecies.rabbit);
    });

    test('豚鼠归到龙猫这一档（同为小宠），不会被误判成狗', () {
      expect(PetLabelMapper.speciesOf('guinea pig'), PetSpecies.chinchilla);
    });

    test('无关标签返回 null', () {
      expect(PetLabelMapper.speciesOf('car'), isNull);
      expect(PetLabelMapper.speciesOf('sofa'), isNull);
      expect(PetLabelMapper.speciesOf(''), isNull);
    });

    test('从标签列表里选置信度最高的物种', () {
      final guess = PetLabelMapper.fromLabels([
        (label: 'animal', confidence: 0.99),
        (label: 'cat', confidence: 0.72),
        (label: 'dog', confidence: 0.61),
      ]);
      expect(guess, isNotNull);
      expect(guess!.species, PetSpecies.cat);
      expect(guess.matchedLabel, 'cat');
    });

    test('低置信度标签被丢弃', () {
      final guess = PetLabelMapper.fromLabels([
        (label: 'cat', confidence: PetLabelMapper.minConfidence - 0.01),
      ]);
      expect(guess, isNull);
    });

    test('没有宠物标签时返回 null（不硬猜）', () {
      final guess = PetLabelMapper.fromLabels([
        (label: 'indoor', confidence: 0.9),
        (label: 'floor', confidence: 0.8),
      ]);
      expect(guess, isNull);
    });
  });

  group('自动配置合成', () {
    test('识别到物种时采用识别结果', () {
      final setup = PetAutoProfiler.resolve(
        coat: PetCoatAnalyzer.classify(
          meanLuma: 0.15,
          saturation: 0.03,
          lightFraction: 0,
          darkFraction: 0.9,
        ),
        speciesGuess: (
          species: PetSpecies.chinchilla,
          confidence: 0.88,
          matchedLabel: 'chinchilla',
        ),
        fallbackSpecies: PetSpecies.cat,
      );
      expect(setup.species, PetSpecies.chinchilla);
      expect(setup.coat, PetCoat.black);
      expect(setup.needsConfirmation, isFalse);
    });

    test('没有物种识别能力时用兜底物种，并明确要求用户确认', () {
      final setup = PetAutoProfiler.resolve(
        coat: PetCoatAnalyzer.classify(
          meanLuma: 0.9,
          saturation: 0.02,
          lightFraction: 0.95,
          darkFraction: 0,
        ),
        speciesGuess: null,
        fallbackSpecies: PetSpecies.cat,
      );
      expect(setup.species, PetSpecies.cat);
      expect(setup.detectedSpecies, isNull);
      expect(
        setup.needsConfirmation,
        isTrue,
        reason: '物种没识别出来是确定的事实，必须让用户知道',
      );
      expect(setup.summary, contains('未识别'));
    });

    test('毛色置信度偏低时也要提示确认', () {
      final setup = PetAutoProfiler.resolve(
        coat: PetCoatAnalyzer.classify(
          meanLuma: 0.5,
          saturation: 0.3,
          lightFraction: 0.22,
          darkFraction: 0.22,
        ),
        speciesGuess: (
          species: PetSpecies.dog,
          confidence: 0.9,
          matchedLabel: 'dog',
        ),
        fallbackSpecies: PetSpecies.cat,
      );
      expect(setup.needsConfirmation, isTrue);
    });

    test('生成的参数集与手选结果完全一致（自动不降低质量）', () {
      final setup = PetAutoProfiler.resolve(
        coat: PetCoatAnalyzer.classify(
          meanLuma: 0.9,
          saturation: 0.02,
          lightFraction: 0.95,
          darkFraction: 0,
        ),
        speciesGuess: (
          species: PetSpecies.dog,
          confidence: 0.92,
          matchedLabel: 'dog',
        ),
        fallbackSpecies: PetSpecies.cat,
      );
      final auto = PetAutoProfiler.toProfile(setup);
      final manual = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.white,
      );
      expect(auto.exposureCompensation, manual.exposureCompensation);
      expect(auto.shutterDenominator, manual.shutterDenominator);
      expect(auto.flashPolicy, manual.flashPolicy);
      expect(auto.noiseReduction, manual.noiseReduction);
    });

    test('白毛自动判定后拿到的是加曝光（而不是减曝光）', () {
      final setup = PetAutoProfiler.resolve(
        coat: PetCoatAnalyzer.classify(
          meanLuma: 0.92,
          saturation: 0.01,
          lightFraction: 1,
          darkFraction: 0,
        ),
        speciesGuess: null,
        fallbackSpecies: PetSpecies.cat,
      );
      final profile = PetAutoProfiler.toProfile(setup);
      expect(
        profile.exposureCompensation,
        greaterThan(0),
        reason: '白毛判成负曝光就是把照片拍废',
      );
    });

    test('summary 同时给出物种与毛色依据', () {
      final setup = PetAutoProfiler.resolve(
        coat: PetCoatAnalyzer.classify(
          meanLuma: 0.15,
          saturation: 0.03,
          lightFraction: 0,
          darkFraction: 0.9,
        ),
        speciesGuess: (
          species: PetSpecies.cat,
          confidence: 0.8,
          matchedLabel: 'cat',
        ),
        fallbackSpecies: PetSpecies.dog,
      );
      expect(setup.summary, contains('猫'));
      expect(setup.summary, contains('%'));
    });
  });

  group('空实现', () {
    test('未接入识别能力时 isAvailable 为 false 且不抛异常', () async {
      const detector = NoSpeciesDetector();
      expect(detector.isAvailable, isFalse);
      final r = await detector.detect(Uint8List(4), width: 1, height: 1);
      expect(r, isNull);
    });
  });
}
