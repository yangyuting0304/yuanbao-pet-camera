// 宠物滤镜内核 —— 像素级单元测试。
//
// 滤镜是"比系统相机好"的核心差异点，而且无法靠肉眼回归（改一行参数
// 观感就变了）。所以这里用合成像素锁死**产品承诺的物理行为**：
// 白毛提亮、黑毛压暗、高光不过曝、暖调不偏冷、暗角四周压暗、
// 降噪只压平坦区而不抹平毛发边缘。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/pet_capture_profile.dart';
import 'package:pet_camera/data/pet_filter.dart';

/// 生成纯色 RGBA 图。
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

/// 读某个像素的 RGB。
List<int> _px(Uint8List buf, int w, int x, int y) {
  final o = (y * w + x) * 4;
  return [buf[o], buf[o + 1], buf[o + 2]];
}

void main() {
  group('曝光：白毛加、黑毛减（网页端的数字兜底）', () {
    test('白毛 +0.85EV 让中灰明显变亮', () {
      final src = _solid(8, 8, 120, 120, 120);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        exposure: 0.85,
      );
      final p = _px(out, 8, 4, 4);
      expect(p[0], greaterThan(120), reason: '白毛必须被提亮，否则拍成灰毛');
      // 2^0.85 ≈ 1.80 → 120 * 1.80 ≈ 216
      expect(p[0], closeTo(216, 6));
    });

    test('黑毛 −0.5EV 让中灰明显压暗', () {
      final src = _solid(8, 8, 120, 120, 120);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        exposure: -0.5,
      );
      final p = _px(out, 8, 4, 4);
      expect(p[0], lessThan(120), reason: '黑毛必须被压暗，否则糊成一团灰');
      // 2^-0.5 ≈ 0.707 → 120 * 0.707 ≈ 85
      expect(p[0], closeTo(85, 6));
    });

    test('0EV 不改变画面', () {
      final src = _solid(8, 8, 128, 128, 128);
      final out = PetFilterKernel.apply(src, width: 8, height: 8);
      expect(_px(out, 8, 4, 4), [128, 128, 128]);
    });
  });

  group('高光滚降：保住毛发高光不死白', () {
    test('纯白被压下来，但不会压成灰（仍 > 200）', () {
      final src = _solid(8, 8, 255, 255, 255);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        highlightRolloff: 0.7,
      );
      final v = _px(out, 8, 4, 4)[0];
      expect(v, lessThan(255), reason: '不压就会死白，丢掉毛发层次');
      expect(v, greaterThan(200), reason: '压太狠白毛会变灰，观感更差');
    });

    test('滚降只影响膝盖以上，暗部不受影响', () {
      final src = _solid(8, 8, 100, 100, 100);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        highlightRolloff: 0.8,
      );
      expect(_px(out, 8, 4, 4)[0], 100);
    });

    test('滚降越强，高光压得越多（单调）', () {
      final src = _solid(4, 4, 255, 255, 255);
      var last = 256;
      for (final r in [0.0, 0.3, 0.6, 0.9]) {
        final out = PetFilterKernel.apply(
          src,
          width: 4,
          height: 4,
          highlightRolloff: r,
        );
        final v = _px(out, 4, 2, 2)[0];
        expect(v, lessThanOrEqualTo(last));
        last = v;
      }
    });
  });

  group('阴影提亮：黑毛不糊成一团', () {
    test('暗灰被抬起来', () {
      final src = _solid(8, 8, 40, 40, 40);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        shadowLift: 0.4,
      );
      expect(_px(out, 8, 4, 4)[0], greaterThan(40));
    });

    test('纯黑仍然是纯黑（不会整片发灰）', () {
      final src = _solid(8, 8, 0, 0, 0);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        shadowLift: 0.8,
      );
      expect(_px(out, 8, 4, 4)[0], 0);
    });

    test('提亮幅度随强度单调增加', () {
      final src = _solid(4, 4, 40, 40, 40);
      var last = -1;
      for (final s in [0.0, 0.2, 0.5, 0.9]) {
        final out = PetFilterKernel.apply(
          src,
          width: 4,
          height: 4,
          shadowLift: s,
        );
        final v = _px(out, 4, 2, 2)[0];
        expect(v, greaterThanOrEqualTo(last));
        last = v;
      }
    });
  });

  group('色温：只偏暖不偏冷', () {
    test('暖调抬红压蓝', () {
      final src = _solid(8, 8, 128, 128, 128);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        tempShift: 300,
      );
      final p = _px(out, 8, 4, 4);
      expect(p[0], greaterThan(p[1]), reason: 'R 应高于 G');
      expect(p[1], greaterThan(p[2]), reason: 'G 应高于 B（暖调）');
    });

    test('负色温偏移会变冷 —— 生产参数里不允许出现', () {
      // 这条测试是"反向证明"：说明参数为正才会有暖调效果。
      final src = _solid(8, 8, 128, 128, 128);
      final cold = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        tempShift: -300,
      );
      final cp = _px(cold, 8, 4, 4);
      expect(cp[2], greaterThan(cp[0]), reason: '负值会让画面发冷（毛色发灰）');
    });

    test('所有物种/毛色组合的色温偏移都是正的', () {
      for (final species in PetSpecies.values) {
        for (final coat in PetCoat.values) {
          final profile = PetCaptureProfile.resolve(
            species: species,
            coat: coat,
          );
          expect(profile.tempShift, greaterThan(0));
        }
      }
    });
  });

  group('饱和度：只调浓度不换色相', () {
    test('1.0 时完全不改', () {
      final src = _solid(8, 8, 200, 100, 50);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        saturation: 1.0,
      );
      expect(_px(out, 8, 4, 4), [200, 100, 50]);
    });

    test('>1 时拉开色差（更浓）', () {
      final src = _solid(8, 8, 200, 100, 50);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        saturation: 1.1,
      );
      final p = _px(out, 8, 4, 4);
      expect(p[0], greaterThan(200));
      expect(p[2], lessThan(50));
    });

    test('<1 时收敛色差（更淡）', () {
      final src = _solid(8, 8, 200, 100, 50);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        saturation: 0.9,
      );
      final p = _px(out, 8, 4, 4);
      expect(p[0], lessThan(200));
      expect(p[2], greaterThan(50));
    });
  });

  group('暗角：视线收拢到中心', () {
    test('四角比中心暗', () {
      final src = _solid(32, 32, 128, 128, 128);
      final out = PetFilterKernel.apply(
        src,
        width: 32,
        height: 32,
        vignette: 0.3,
      );
      final center = _px(out, 32, 16, 16)[0];
      final corner = _px(out, 32, 0, 0)[0];
      expect(corner, lessThan(center));
      expect(center, greaterThanOrEqualTo(125), reason: '中心不应被明显压暗');
    });

    test('0 强度时画面完全不变', () {
      final src = _solid(16, 16, 128, 128, 128);
      final out = PetFilterKernel.apply(src, width: 16, height: 16);
      expect(_px(out, 16, 0, 0)[0], 128);
      expect(_px(out, 16, 8, 8)[0], 128);
    });
  });

  group('微对比：让毛发根根分明（而非锐化）', () {
    /// 造一张左暗右亮的竖直接边图。
    Uint8List stepEdge(int w, int h, int dark, int bright) {
      final out = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = x < w ~/ 2 ? dark : bright;
          final o = (y * w + x) * 4;
          out[o] = v;
          out[o + 1] = v;
          out[o + 2] = v;
          out[o + 3] = 255;
        }
      }
      return out;
    }

    test('边缘两侧对比被拉开', () {
      const w = 64;
      final src = stepEdge(w, 64, 80, 180);
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: 64,
        clarity: 0.2,
      );
      // 微对比的模糊半径只有 2px，作用范围就贴在边缘紧邻的几个像素上
      // （这正是"局部对比"的含义：细密的绒毛纹理处处是边缘，所以处处生效；
      //  而一整条大接边只会在接缝附近被拉开）。取样必须贴着边缘取。
      final justDark = _px(out, w, w ~/ 2 - 1, 32)[0];
      final justBright = _px(out, w, w ~/ 2, 32)[0];
      expect(justDark, lessThan(80));
      expect(justBright, greaterThan(180));
    });

    test('远离边缘的平坦区基本不受影响', () {
      const w = 64;
      final src = stepEdge(w, 64, 80, 180);
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: 64,
        clarity: 0.2,
      );
      expect(_px(out, w, 4, 32)[0], closeTo(80, 3));
      expect(_px(out, w, w - 5, 32)[0], closeTo(180, 3));
    });
  });

  group('降噪：只压平坦区，不抹平毛发边缘', () {
    /// 造带噪点的平坦区（棋盘式抖动）。
    Uint8List noisyFlat(int w, int h, int base, int amp) {
      final out = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = (x + y) % 2 == 0 ? base + amp : base - amp;
          final o = (y * w + x) * 4;
          out[o] = v;
          out[o + 1] = v;
          out[o + 2] = v;
          out[o + 3] = 255;
        }
      }
      return out;
    }

    /// 相邻像素差的平均绝对值——噪声的粗略度量。
    double roughness(Uint8List buf, int w, int h) {
      var sum = 0;
      var count = 0;
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          final a = _px(buf, w, x, y)[0];
          final b = _px(buf, w, x + 1, y)[0];
          sum += (a - b).abs();
          count++;
        }
      }
      return count == 0 ? 0 : sum / count;
    }

    test('平坦噪点被压下去', () {
      const w = 48;
      final src = noisyFlat(w, 48, 128, 24);
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: 48,
        noiseReduction: 0.8,
      );
      expect(
        roughness(out, w, 48),
        lessThan(roughness(src, w, 48) * 0.6),
        reason: '噪点应被明显削弱',
      );
    });

    test('强边缘基本保留（不会被抹平）', () {
      // 左半 60、右半 200 的接边；降噪后边缘落差应基本保持。
      const w = 48;
      final src = Uint8List(w * 48 * 4);
      for (var y = 0; y < 48; y++) {
        for (var x = 0; x < w; x++) {
          final v = x < w ~/ 2 ? 60 : 200;
          final o = (y * w + x) * 4;
          src[o] = v;
          src[o + 1] = v;
          src[o + 2] = v;
          src[o + 3] = 255;
        }
      }
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: 48,
        noiseReduction: 0.9,
      );
      final left = _px(out, w, w ~/ 2 - 2, 24)[0];
      final right = _px(out, w, w ~/ 2 + 2, 24)[0];
      expect(
        right - left,
        greaterThan(100),
        reason: '门控应让强边缘几乎不被模糊，否则绒毛会糊成一片',
      );
    });
  });

  group('色调曲线：形状正确性', () {
    test('曲线单调不减（不会出现反转/色带）', () {
      final lut = PetFilterKernel.buildChannelLut(
        exposureGain: 1.0,
        channelGain: 1.0,
        shadowLift: 0.4,
        highlightRolloff: 0.6,
      );
      expect(lut.length, 256);
      for (var i = 1; i < 256; i++) {
        expect(lut[i], greaterThanOrEqualTo(lut[i - 1] - 1e-9));
      }
    });

    test('曲线输出恒在 0..1 内', () {
      for (final s in [0.0, 0.5, 1.0]) {
        for (final r in [0.0, 0.5, 1.0]) {
          final lut = PetFilterKernel.buildChannelLut(
            exposureGain: 2.0,
            channelGain: 1.1,
            shadowLift: s,
            highlightRolloff: r,
          );
          for (final v in lut) {
            expect(v, inInclusiveRange(0.0, 1.0));
          }
        }
      }
    });

    test('曲线首端为 0（黑仍是黑）', () {
      final lut = PetFilterKernel.buildChannelLut(
        exposureGain: 1.5,
        channelGain: 1.0,
        shadowLift: 0.5,
        highlightRolloff: 0.5,
      );
      expect(lut.first, 0.0);
    });
  });

  group('缓冲区与边界', () {
    test('缓冲区过小会明确报错，而不是静默出错图', () {
      expect(
        () => PetFilterKernel.apply(Uint8List(10), width: 8, height: 8),
        throwsArgumentError,
      );
    });

    test('alpha 通道被原样保留', () {
      final src = _solid(4, 4, 100, 100, 100);
      for (var i = 0; i < 16; i++) {
        src[i * 4 + 3] = 200;
      }
      final out = PetFilterKernel.apply(
        src,
        width: 4,
        height: 4,
        exposure: 0.5,
      );
      expect(out[3], 200);
      expect(out[7], 200);
    });

    test('极端参数不会产生越界值', () {
      final src = _solid(8, 8, 250, 250, 250);
      final out = PetFilterKernel.apply(
        src,
        width: 8,
        height: 8,
        exposure: 3.0,
        tempShift: 2000,
        shadowLift: 1.0,
        highlightRolloff: 1.0,
        clarity: 1.0,
        noiseReduction: 1.0,
        vignette: 1.0,
        saturation: 3.0,
      );
      for (final v in out) {
        expect(v, inInclusiveRange(0, 255));
      }
    });
  });

  group('与参数引擎联动', () {
    test('龙猫弱光的降噪强于猫（细绒毛+高感噪点）', () {
      final chilla = PetCaptureProfile.resolve(
        species: PetSpecies.chinchilla,
        coat: PetCoat.tabby,
        scene: PetScene.lowLight,
      );
      final cat = PetCaptureProfile.resolve(
        species: PetSpecies.cat,
        coat: PetCoat.tabby,
        scene: PetScene.lowLight,
      );
      expect(chilla.noiseReduction, greaterThan(cat.noiseReduction));
    });

    test('白毛的高光滚降强于黑毛（更怕死白）', () {
      final white = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.white,
      );
      final black = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.black,
      );
      expect(white.highlightRolloff, greaterThan(black.highlightRolloff));
    });

    test('furTextureBoost=true 的 profile 映射为固定 texture 强度', () {
      final profile = PetCaptureProfile.resolve(
        species: PetSpecies.cat,
        coat: PetCoat.tabby,
      );
      final req = PetFilter.buildRequest(Uint8List(0), profile);
      expect(profile.furTextureBoost, isTrue);
      expect(req.texture, PetCaptureProfile.furTextureStrength);
    });

    test('furTextureBoost=false 映射为 0（不增强）', () {
      // 全物种基线当前都是 true，这里手工构造 false 档验证开关通路。
      const profile = PetCaptureProfile(
        species: PetSpecies.cat,
        coat: PetCoat.tabby,
        scene: PetScene.portrait,
        look: PetLook.natural,
        shutterDenominator: 500,
        isoMin: 400,
        isoMax: 1600,
        exposureCompensation: 0,
        whiteBalanceK: 5000,
        continuousFocus: false,
        flashPolicy: FlashPolicy.forbidden,
        silentShutter: true,
        focusTarget: FocusTarget.nearestEye,
        tempShift: 0,
        highlightRolloff: 0,
        shadowLift: 0,
        clarity: 0,
        noiseReduction: 0,
        vignette: 0,
        saturation: 1,
        vibrance: 0,
        grain: 0,
        eyeEnhance: false,
        tearStainFix: false,
        furTextureBoost: false,
        summary: '',
      );
      final req = PetFilter.buildRequest(Uint8List(0), profile);
      expect(req.texture, 0.0);
    });
  });

  group('毛发质感：中频增强 + 边缘遮罩锐化', () {
    /// 左暗右亮的竖直接边（模拟毛发边缘）。
    Uint8List stepEdge(int w, int h, int dark, int bright) {
      final out = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = x < w ~/ 2 ? dark : bright;
          final o = (y * w + x) * 4;
          out[o] = v;
          out[o + 1] = v;
          out[o + 2] = v;
          out[o + 3] = 255;
        }
      }
      return out;
    }

    /// 边缘两侧的落差。
    int edgeContrast(Uint8List buf, int w, int h) {
      final dark = _px(buf, w, w ~/ 2 - 1, h ~/ 2)[0];
      final bright = _px(buf, w, w ~/ 2, h ~/ 2)[0];
      return bright - dark;
    }

    test('边缘两侧落差被拉大（毛根分明）', () {
      const w = 64;
      final src = stepEdge(w, 64, 80, 180);
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: 64,
        texture: 0.45,
      );
      expect(
        edgeContrast(out, w, 64),
        greaterThan(100),
        reason: 'texture 应放大毛发边缘落差（原落差 100）',
      );
    });

    test('增强幅度随强度单调增加', () {
      const w = 64;
      final src = stepEdge(w, 64, 80, 180);
      var last = 0;
      for (final t in [0.0, 0.2, 0.45, 0.8]) {
        final out = PetFilterKernel.apply(
          src,
          width: w,
          height: 64,
          texture: t,
        );
        final c = edgeContrast(out, w, 64);
        expect(c, greaterThanOrEqualTo(last));
        last = c;
      }
      expect(last, greaterThan(100), reason: '最强档必须有可感知的增强');
    });

    test('边缘增强远离边缘处衰减（局部性）', () {
      const w = 64;
      final src = stepEdge(w, 64, 80, 180);
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: 64,
        texture: 0.45,
      );
      // 平坦区（距边缘 4px 以上）的灰度基本不动。
      expect(_px(out, w, 4, 32)[0], closeTo(80, 3));
      expect(_px(out, w, w - 5, 32)[0], closeTo(180, 3));
    });

    test('小振幅噪点不被放大（门控挡住平坦区噪声）', () {
      // 振幅 4 的棋盘噪点：低于 _midGateLo/_sharpGateLo，
      // 门控应为 0，噪点幅度不应显著增长。
      const w = 48;
      Uint8List noisy(int w, int h, int base, int amp) {
        final out = Uint8List(w * h * 4);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final v = (x + y) % 2 == 0 ? base + amp : base - amp;
            final o = (y * w + x) * 4;
            out[o] = v;
            out[o + 1] = v;
            out[o + 2] = v;
            out[o + 3] = 255;
          }
        }
        return out;
      }

      double roughness(Uint8List buf, int w, int h) {
        var sum = 0;
        var count = 0;
        for (var y = 1; y < h - 1; y++) {
          for (var x = 1; x < w - 1; x++) {
            final a = _px(buf, w, x, y)[0];
            final b = _px(buf, w, x + 1, y)[0];
            sum += (a - b).abs();
            count++;
          }
        }
        return count == 0 ? 0 : sum / count;
      }

      final src = noisy(w, 48, 128, 4);
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: 48,
        texture: 0.45,
      );
      expect(
        roughness(out, w, 48),
        lessThan(roughness(src, w, 48) * 1.5),
        reason: '小振幅噪点不应被 texture 显著放大，否则背景虚化区越修越脏',
      );
    });

    test('texture=0 与旧版行为逐字节一致（回归保护）', () {
      const w = 24;
      final src = stepEdge(w, 24, 80, 180);
      final without = PetFilterKernel.apply(src, width: w, height: 24);
      final zero = PetFilterKernel.apply(
        src,
        width: w,
        height: 24,
        texture: 0,
      );
      expect(zero, without);
    });

    test('极端 texture 不产生越界值', () {
      final src = stepEdge(16, 16, 0, 255);
      final out = PetFilterKernel.apply(
        src,
        width: 16,
        height: 16,
        texture: 1.0,
        clarity: 1.0,
        noiseReduction: 1.0,
        exposure: 3.0,
      );
      for (final v in out) {
        expect(v, inInclusiveRange(0, 255));
      }
    });
  });

  group('眼睛增强：眼区暗部提亮（廉价近似区域）', () {
    // 16x16 图：眼区椭圆中心 (8, 6.4)，即 0.50w / 0.40h。
    test('眼区中心的暗像素被提亮', () {
      final src = _solid(16, 16, 60, 60, 60);
      final out = PetFilterKernel.apply(
        src,
        width: 16,
        height: 16,
        eyeEnhance: 1.0,
      );
      expect(
        _px(out, 16, 8, 6)[0],
        greaterThan(60),
        reason: '瞳孔/虹膜应被提亮，眼睛才有神',
      );
    });

    test('眼区外（画面角落）不受影响', () {
      final src = _solid(16, 16, 60, 60, 60);
      final out = PetFilterKernel.apply(
        src,
        width: 16,
        height: 16,
        eyeEnhance: 1.0,
      );
      expect(_px(out, 16, 0, 15)[0], 60, reason: '区域外必须零权重');
    });

    test('高光被护住：眼区里的白毛高光几乎不动', () {
      // 全图 250：区域内提亮走 (1−l)^1.5 曲线，l=250 时增量 <0.1；
      // 锐化项在整图平坦（hf≈0）时也为 0。
      final src = _solid(16, 16, 250, 250, 250);
      final out = PetFilterKernel.apply(
        src,
        width: 16,
        height: 16,
        eyeEnhance: 1.0,
      );
      expect(_px(out, 16, 8, 6)[0], closeTo(250, 1), reason: '眼神光/白毛不能被提爆');
    });
  });

  group('泪痕淡化：偏红+偏暗特征门控', () {
    /// 16x16 灰底，中心 (8,8)（泪痕椭圆中心）放一块指定颜色的斑。
    Uint8List stainAt(int r, int g, int b) {
      final out = _solid(16, 16, 140, 140, 140);
      final o = (8 * 16 + 8) * 4;
      out[o] = r;
      out[o + 1] = g;
      out[o + 2] = b;
      out[o + 3] = 255;
      return out;
    }

    test('暗红泪痕斑被去红且提亮', () {
      // (90,60,40)：r−b=50 全额过门控，亮度低全额过暗度门控。
      final out = PetFilterKernel.apply(
        stainAt(90, 60, 40),
        width: 16,
        height: 16,
        tearStain: 0.8,
      );
      final p = _px(out, 16, 8, 8);
      expect(p[0] - p[2], lessThan(50), reason: '偏红程度应收敛');
      expect(p[1], greaterThan(60), reason: '泪痕比周围毛暗，应被提亮');
    });

    test('亮橙毛发不被误去红（暗度门控）', () {
      // (200,120,40) 色相上也是"红主导"，但亮度高——
      // 橘猫/棕犬的脸毛就是这个特征，必须放过。
      final out = PetFilterKernel.apply(
        stainAt(200, 120, 40),
        width: 16,
        height: 16,
        tearStain: 0.8,
      );
      expect(
        _px(out, 16, 8, 8)[0],
        greaterThan(195),
        reason: '亮橙毛 r 不应被明显拉低，否则品种固有色被洗掉',
      );
    });

    test('区域外的泪痕斑不动（椭圆权重为零）', () {
      final src = _solid(16, 16, 140, 140, 140);
      final o = (15 * 16 + 0) * 4; // 左下角
      src[o] = 90;
      src[o + 1] = 60;
      src[o + 2] = 40;
      final out = PetFilterKernel.apply(
        src,
        width: 16,
        height: 16,
        tearStain: 0.8,
      );
      expect(_px(out, 16, 0, 15), [90, 60, 40]);
    });
  });

  group('三个美颜开关的参数映射', () {
    test('cat 默认 profile：三开关全开且映射为固定强度', () {
      final profile = PetCaptureProfile.resolve(
        species: PetSpecies.cat,
        coat: PetCoat.tabby,
      );
      final req = PetFilter.buildRequest(Uint8List(0), profile);
      expect(profile.eyeEnhance, isTrue);
      expect(profile.tearStainFix, isTrue);
      expect(req.texture, PetCaptureProfile.furTextureStrength);
      expect(req.eyeEnhance, PetCaptureProfile.eyeEnhanceStrength);
      expect(req.tearStain, PetCaptureProfile.tearStainStrength);
    });
  });
}
