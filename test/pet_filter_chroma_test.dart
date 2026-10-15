// 色度降噪 —— 像素级单元测试。
//
// 为什么单独立一组测试：手机上低光噪点绝大多数是**彩色**的，
// 而此前整条降噪链路只作用在亮度上。人眼对色度噪声远比对亮度噪声敏感，
// 彩色斑点一眼就"脏"——这是"成片不如原相机糙"最实的一个来源。
//
// 这里的三个产品承诺逐条锁死：
//   ① 色度高频（斑与斑之间的差异）必须被压下去
//   ② 亮度不得漂移（毛发边缘/眼神光靠高频撑着，动亮度就等于磨平细节）
//   ③ 强度为 0 时必须与"不走色度降噪"逐字节一致（不能污染既有行为）
import 'dart:typed_data';

import 'package:camera/camera.dart' show ResolutionPreset;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/camera_capability.dart';
import 'package:pet_camera/data/pet_filter.dart';

/// 生成"亮度恒定 + 色度隔列跳变"的图：模拟低光彩色噪点/色斑。
///
/// 关键点：相邻像素亮度完全相同（128），只有 r/b 交替——
/// 于是任何"色度粗糙度"的下降都不可能来自亮度被磨平。
Uint8List _chromaNoise(int w, int h, {int base = 128, int swing = 40}) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      // 亮度恒定在 base，色度按 x 的奇偶 ±swing/2（均值仍为 base）。
      final sign = x.isEven ? 1 : -1;
      final d = (swing / 2 * sign).round();
      out[o] = (base + d).clamp(0, 255);
      out[o + 1] = base;
      out[o + 2] = (base - d).clamp(0, 255);
      out[o + 3] = 255;
    }
  }
  return out;
}

/// 色度粗糙度：相邻像素色度（r−b）差绝对值的平均。
///
/// 只看色度、不看亮度：亮度被磨平会让这个指标"假性下降"，
/// 那样测出来的就不是色度降噪而是一张被磨糊的图。
double _chromaRoughness(Uint8List buf, int w, int h) {
  var sum = 0.0;
  var count = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x + 1 < w; x++) {
      final a = (y * w + x) * 4;
      final b = (y * w + x + 1) * 4;
      final ca = buf[a] - buf[a + 2];
      final cb = buf[b] - buf[b + 2];
      sum += (cb - ca).abs();
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}

/// 平均 Rec.709 亮度。
double _meanLuma(Uint8List buf, int n) {
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    sum +=
        0.2126 * buf[o] + 0.7152 * buf[o + 1] + 0.0722 * buf[o + 2];
  }
  return sum / n;
}

void main() {
  group('色度降噪：彩色噪点必须被压下去', () {
    test('开启后色度粗糙度显著下降', () {
      const w = 64, h = 64;
      final src = _chromaNoise(w, h);
      final before = _chromaRoughness(src, w, h);

      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        chromaDenoise: 1.0,
      );
      final after = _chromaRoughness(out, w, h);

      expect(before, greaterThan(20), reason: '样本本身必须是强色度噪点');
      expect(after, lessThan(before * 0.35), reason: '色度噪点应被大幅压平');
    });

    test('亮度不漂移：动色度不动亮度', () {
      const w = 64, h = 64;
      final src = _chromaNoise(w, h);
      final before = _meanLuma(src, w * h);
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        chromaDenoise: 1.0,
      );
      final after = _meanLuma(out, w * h);
      // r/b 对称改动时亮度本应严格不变；留2 级容差给 8bit 量化。
      expect((after - before).abs(), lessThan(2.0));
    });

    test('强度 0 时逐字节等价于不走色度降噪（不污染既有管线）', () {
      const w = 40, h = 40;
      final src = _chromaNoise(w, h);
      final baseline = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        clarity: 0.2,
        noiseReduction: 0.4,
      );
      final same = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        clarity: 0.2,
        noiseReduction: 0.4,
        chromaDenoise: 0.0,
      );
      expect(same, baseline);
    });

    test('强度递增：色度粗糙度单调不增', () {
      const w = 48, h = 48;
      final src = _chromaNoise(w, h);
      final light = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        chromaDenoise: 0.3,
      );
      final heavy = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        chromaDenoise: 1.0,
      );
      expect(
        _chromaRoughness(heavy, w, h),
        lessThanOrEqualTo(_chromaRoughness(light, w, h)),
      );
    });

    test('纯色图（无噪点）几乎不被改动', () {
      const w = 32, h = 32;
      final src = _chromaNoise(w, h, swing: 0);
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        chromaDenoise: 1.0,
      );
      for (var i = 0; i < w * h; i++) {
        final o = i * 4;
        expect(out[o], src[o]);
        expect(out[o + 1], src[o + 1]);
        expect(out[o + 2], src[o + 2]);
      }
    });
  });

  group('色度降噪：只磨色度，不啃毛发亮度高频', () {
    test('黑白条纹（亮度高频）不因色度降噪而变灰', () {
      const w = 64, h = 8;
      final src = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        final o = i * 4;
        final v = (i % 2 == 0) ? 20 : 220; // 极端亮度边缘
        src[o] = v;
        src[o + 1] = v;
        src[o + 2] = v;
        src[o + 3] = 255;
      }
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        chromaDenoise: 1.0,
      );
      // 边缘两端的对比必须基本保留：色度是 0，降噪不该碰它。
      final lo = _pixel(out, w, 0, 0);
      final hi = _pixel(out, w, 1, 0);
      expect((hi[0] - lo[0]).abs(), greaterThan(150));
    });
  });

  group('iOS 画质档位：超清必须封顶到 veryHigh', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('iOS 上超清不使用 max（48MP 会顶穿进程内存被系统杀掉）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(CaptureQuality.ultra.preset, ResolutionPreset.max,
          reason: '名义档位保持不变，只是实际取值被封顶');
      expect(CaptureQuality.ultra.effectivePreset, ResolutionPreset.veryHigh);
      expect(
        CaptureQuality.ultra.fallbackChain,
        isNot(contains(ResolutionPreset.max)),
        reason: '降级链第一档就是 max 等于没封顶',
      );
      expect(
        CaptureQuality.ultra.fallbackChain.first,
        ResolutionPreset.veryHigh,
      );
    });

    test('Android 上超清维持 max（平台内存余量更大）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(CaptureQuality.ultra.effectivePreset, ResolutionPreset.max);
    });

    test('iOS 上其余档位与降级链保持单调不增', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      for (final q in CaptureQuality.values) {
        final chain = q.fallbackChain;
        expect(chain.first, q.effectivePreset);
        expect(chain.length, lessThanOrEqualTo(3));
        for (var i = 1; i < chain.length; i++) {
          expect(chain[i].index, lessThan(chain[i - 1].index));
        }
        expect(
          q.effectivePreset.index,
          greaterThan(ResolutionPreset.medium.index),
          reason: '不能为了保命把画质降到 480p',
        );
      }
    });
  });
}

/// 读某个像素的 RGB。
List<int> _pixel(Uint8List buf, int w, int x, int y) {
  final o = (y * w + x) * 4;
  return [buf[o], buf[o + 1], buf[o + 2]];
}