// 滤镜模板（PetLook）与新增内核参数（颗粒 / 自然饱和度）—— 单元测试。
//
// 这里的断言锁两件事：
//  1. 模板是**叠加**而不是覆盖——套任何模板都不能破坏毛色保护
//     （白毛该加曝光还是要加、暖调不能变冷）
//  2. 新参数确实起作用，而且行为方向正确
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/pet_capture_profile.dart';
import 'package:pet_camera/data/pet_filter.dart';

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

List<int> _px(Uint8List buf, int w, int x, int y) {
  final o = (y * w + x) * 4;
  return [buf[o], buf[o + 1], buf[o + 2]];
}

/// HSV 饱和度简易度量。
double _sat(List<int> rgb) {
  final maxC = rgb.reduce((a, b) => a > b ? a : b);
  final minC = rgb.reduce((a, b) => a < b ? a : b);
  return maxC == 0 ? 0 : (maxC - minC) / maxC;
}

/// 相邻像素差均值——用来度量"颗粒感"。
double _roughness(Uint8List buf, int w, int h) {
  var sum = 0;
  var count = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w - 1; x++) {
      sum += (_px(buf, w, x, y)[0] - _px(buf, w, x + 1, y)[0]).abs();
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}

void main() {
  group('滤镜模板：叠加而非覆盖', () {
    test('natural 不改变任何后处理参数', () {
      final base = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.white,
        scene: PetScene.outdoor,
      );
      final natural = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.white,
        scene: PetScene.outdoor,
        look: PetLook.natural,
      );
      expect(natural.tempShift, base.tempShift);
      expect(natural.highlightRolloff, base.highlightRolloff);
      expect(natural.shadowLift, base.shadowLift);
      expect(natural.clarity, base.clarity);
      expect(natural.saturation, base.saturation);
      expect(natural.grain, 0);
      expect(natural.vibrance, 0);
    });

    test('套任何模板都必须保持暖调（不得变冷）', () {
      for (final look in PetLook.values) {
        for (final species in PetSpecies.values) {
          final p = PetCaptureProfile.resolve(
            species: species,
            coat: PetCoat.tabby,
            look: look,
          );
          expect(
            p.tempShift,
            greaterThan(0),
            reason: '${look.label} × ${species.label} 的色温偏移必须为正',
          );
        }
      }
    });

    test('套任何模板都不能破坏毛色保护：白毛仍然加曝光、黑毛仍然减曝光', () {
      for (final look in PetLook.values) {
        final white = PetCaptureProfile.resolve(
          species: PetSpecies.cat,
          coat: PetCoat.white,
          look: look,
        );
        final black = PetCaptureProfile.resolve(
          species: PetSpecies.cat,
          coat: PetCoat.black,
          look: look,
        );
        expect(
          white.exposureCompensation,
          greaterThan(0),
          reason: '${look.label} 把白毛的曝光补偿弄丢了',
        );
        expect(
          black.exposureCompensation,
          lessThan(0),
          reason: '${look.label} 把黑毛的曝光补偿弄丢了',
        );
      }
    });

    test('模板增量确实生效（与原色有差异）', () {
      final natural = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.tabby,
        look: PetLook.natural,
      );
      final film = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.tabby,
        look: PetLook.filmBrown,
      );
      expect(film.grain, greaterThan(natural.grain));
      expect(film.shadowLift, greaterThan(natural.shadowLift));
      expect(film.tempShift, greaterThan(natural.tempShift));
    });

    test('暗光守护的颗粒最重（顺便掩盖高感噪点）', () {
      final night = PetCaptureProfile.resolve(
        species: PetSpecies.chinchilla,
        coat: PetCoat.tabby,
        scene: PetScene.lowLight,
        look: PetLook.nightGuard,
      );
      final plain = PetCaptureProfile.resolve(
        species: PetSpecies.chinchilla,
        coat: PetCoat.tabby,
        scene: PetScene.lowLight,
        look: PetLook.natural,
      );
      expect(night.grain, greaterThan(plain.grain));
      expect(night.shadowLift, greaterThanOrEqualTo(plain.shadowLift));
    });

    test('饱和度始终被夹在安全区间（禁止过饱和染色）', () {
      for (final look in PetLook.values) {
        for (final scene in PetScene.values) {
          final p = PetCaptureProfile.resolve(
            species: PetSpecies.dog,
            coat: PetCoat.blueGrey,
            scene: scene,
            look: look,
          );
          expect(p.saturation, inInclusiveRange(0.85, 1.15));
        }
      }
    });

    test('每个模板都有文案与说明', () {
      for (final look in PetLook.values) {
        expect(look.label, isNotEmpty);
        expect(look.hint, isNotEmpty);
      }
    });
  });

  group('胶片颗粒', () {
    test('grain = 0 时完全不改变画面', () {
      final src = _solid(16, 16, 128, 128, 128);
      final out = PetFilterKernel.apply(src, width: 16, height: 16, grain: 0);
      expect(_px(out, 16, 8, 8), [128, 128, 128]);
    });

    test('grain > 0 时画面变粗糙（颗粒确实铺上去了）', () {
      final src = _solid(48, 48, 128, 128, 128);
      final flat = PetFilterKernel.apply(src, width: 48, height: 48, grain: 0);
      final grainy = PetFilterKernel.apply(
        src,
        width: 48,
        height: 48,
        grain: 0.12,
      );
      expect(_roughness(flat, 48, 48), closeTo(0, 1e-6));
      expect(_roughness(grainy, 48, 48), greaterThan(1.0));
    });

    test('颗粒是确定性的（同一张图两次结果完全一致）', () {
      final src = _solid(32, 32, 100, 100, 100);
      final a = PetFilterKernel.apply(src, width: 32, height: 32, grain: 0.2);
      final b = PetFilterKernel.apply(src, width: 32, height: 32, grain: 0.2);
      expect(a, equals(b), reason: '跨平台/跨次数必须一致，否则无法回归');
    });

    test('颗粒强度单调：越强越粗糙', () {
      final src = _solid(48, 48, 128, 128, 128);
      var last = -1.0;
      for (final g in [0.0, 0.05, 0.12, 0.25]) {
        final out = PetFilterKernel.apply(
          src,
          width: 48,
          height: 48,
          grain: g,
        );
        final r = _roughness(out, 48, 48);
        expect(r, greaterThanOrEqualTo(last));
        last = r;
      }
    });

    test('颗粒不会把通道推出 0..255', () {
      final src = _solid(24, 24, 250, 250, 250);
      final out = PetFilterKernel.apply(
        src,
        width: 24,
        height: 24,
        grain: 1.0,
      );
      for (final v in out) {
        expect(v, inInclusiveRange(0, 255));
      }
    });
  });

  group('自然饱和度（vibrance）', () {
    test('vibrance = 0 时不变', () {
      final src = _solid(8, 8, 140, 130, 120);
      final out = PetFilterKernel.apply(src, width: 8, height: 8, vibrance: 0);
      expect(_px(out, 8, 4, 4), [140, 130, 120]);
    });

    test('对低饱和像素提得多，对已饱和像素提得少', () {
      // 低饱和：接近灰的暖色
      final lowSrc = _solid(8, 8, 140, 130, 120);
      // 高饱和：已经很浓的橘
      final highSrc = _solid(8, 8, 220, 60, 40);

      final lowOut = PetFilterKernel.apply(
        lowSrc,
        width: 8,
        height: 8,
        vibrance: 0.3,
      );
      final highOut = PetFilterKernel.apply(
        highSrc,
        width: 8,
        height: 8,
        vibrance: 0.3,
      );

      final lowGain = _sat(_px(lowOut, 8, 4, 4)) - _sat([140, 130, 120]);
      final highGain = _sat(_px(highOut, 8, 4, 4)) - _sat([220, 60, 40]);

      expect(lowGain, greaterThan(0));
      expect(
        lowGain,
        greaterThan(highGain),
        reason: 'vibrance 的意义就是"只提还不够鲜艳的"，已饱和的要少动',
      );
    });

    test('不改变色相（仍是同一个颜色，只是更浓）', () {
      final src = _solid(8, 8, 140, 130, 120);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        vibrance: 0.4,
      );
      final p = _px(out, 8, 4, 4);
      // 原本 R > G > B，提饱和后顺序不能变
      expect(p[0], greaterThan(p[1]));
      expect(p[1], greaterThan(p[2]));
    });

    test('极端值也不会越界', () {
      final src = _solid(8, 8, 250, 250, 250);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        vibrance: 1.0,
        grain: 1.0,
        saturation: 1.15,
      );
      for (final v in out) {
        expect(v, inInclusiveRange(0, 255));
      }
    });
  });
}
