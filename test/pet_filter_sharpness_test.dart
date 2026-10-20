// 锐化必须有节制 —— 像素级契约测试。
//
// 2026-10-20 用户实拍反馈：锐化过度了，还不如原相机。用离线实验台
// （tools/filter_lab）在真机实拍图上量了锐度比（滤镜后拉普拉斯方差
// 除以 原图拉普拉斯方差）：
//
//   修复前(clarity .10 + texture .22)：全图 1.99（锐度翻倍）、过冲 12.6%
//   修复后(clarity .04 + texture .08)：全图 1.12~1.24、背景区 0.88~0.97
//
// 结论：不是相机的问题，是我们的滤镜把锐度翻了一倍。毛发质感是在高频上
// 放大差异，而宠物照背景（瓷砖、地板、树叶）恰恰全是高频纹理 ——
// 分不清是猫毛还是地面，于是满屏一起放大，观感就是砂纸加白边。
//
// 这里钉死三条承诺：滤镜不得让画面比原图明显更锐；背景不得被放大；
// 主体不得被磨糊。
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/pet_capture_profile.dart';
import 'package:pet_camera/data/pet_filter.dart';

/// 拉普拉斯响应的方差 —— 边缘锐度的量化。
double _sharpnessIn(
  Uint8List rgba,
  int w,
  int h, {
  required double l,
  required double t,
  required double r,
  required double b,
  bool exclude = false,
}) {
  var sum = 0.0;
  var sumSq = 0.0;
  var count = 0;
  // 从 1 开始、到 w-1/h-1 结束：拉普拉斯要看四邻域，边缘像素没有完整的邻域
  // （访问 o-4 会越界成负下标）。
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final nx = x / w;
      final ny = y / h;
      final inBox = nx >= l && nx <= r && ny >= t && ny <= b;
      if (exclude == inBox) continue;
      final o = (y * w + x) * 4;
      double lum(int p) =>
          0.2126 * rgba[p] + 0.7152 * rgba[p + 1] + 0.0722 * rgba[p + 2];
      final lap =
          4 * lum(o) -
          lum(o - 4) -
          lum(o + 4) -
          lum(o - w * 4) -
          lum(o + w * 4);
      sum += lap;
      sumSq += lap * lap;
      count++;
    }
  }
  if (count == 0) return 1;
  final mean = sum / count;
  return math.max(1e-6, sumSq / count - mean * mean);
}

/// 中间是主体（毛发团块）、四周是高频纹理背景（瓷砖/布纹）。
Uint8List _scene(int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      final inSubject =
          x > w * 0.30 && x < w * 0.70 && y > h * 0.30 && y < h * 0.70;
      final v = inSubject
          ? 140 + ((x + y) % 7) * 2
          : 128 + ((x + y) % 2 == 0 ? 26 : -26);
      out[o] = v;
      out[o + 1] = v;
      out[o + 2] = v;
      out[o + 3] = 255;
    }
  }
  return out;
}

void main() {
  const w = 160;
  const h = 160;
  final src = _scene(w, h);
  final profile = PetCaptureProfile.resolve(
    species: PetSpecies.cat,
    coat: PetCoat.tabby,
    scene: PetScene.portrait,
    look: PetLook.natural,
  );

  group('锐化必须有节制', () {
    test('滤镜不得让整幅画面比原图明显更锐', () {
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        clarity: profile.clarity,
        texture: PetCaptureProfile.furTextureStrength,
        noiseReduction: profile.noiseReduction,
      );
      final before = _sharpnessIn(src, w, h, l: 0, t: 0, r: 1, b: 1);
      final after = _sharpnessIn(out, w, h, l: 0, t: 0, r: 1, b: 1);
      expect(
        after / before,
        lessThanOrEqualTo(1.30),
        reason: '修复前是 1.99（锐度翻倍）—— 那正是用户骂锐化过度的原因',
      );
    });

    test('高频背景不得被放大（主体清晰、背景不炸）', () {
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        clarity: profile.clarity,
        texture: PetCaptureProfile.furTextureStrength,
        noiseReduction: profile.noiseReduction,
        subjectRect: (left: 0.30, top: 0.30, right: 0.70, bottom: 0.70),
      );
      final before = _sharpnessIn(
        src,
        w,
        h,
        l: 0,
        t: 0,
        r: 1,
        b: 1,
        exclude: true,
      );
      final after = _sharpnessIn(
        out,
        w,
        h,
        l: 0,
        t: 0,
        r: 1,
        b: 1,
        exclude: true,
      );
      expect(
        after / before,
        lessThanOrEqualTo(1.05),
        reason: '背景是瓷砖/地板这类高频纹理，放大它就是砂纸感',
      );
    });

    test('主体区不得被磨糊（磨糊了就不是更好看，是更差）', () {
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        clarity: profile.clarity,
        texture: PetCaptureProfile.furTextureStrength,
        noiseReduction: profile.noiseReduction,
        subjectRect: (left: 0.30, top: 0.30, right: 0.70, bottom: 0.70),
      );
      final before = _sharpnessIn(
        src,
        w,
        h,
        l: 0.30,
        t: 0.30,
        r: 0.70,
        b: 0.70,
      );
      final after = _sharpnessIn(
        out,
        w,
        h,
        l: 0.30,
        t: 0.30,
        r: 0.70,
        b: 0.70,
      );
      expect(
        after / before,
        greaterThanOrEqualTo(0.95),
        reason: '主体至少要保持原图的清晰度',
      );
    });
  });

  group('过冲保护：强边缘不得拉出白边', () {
    test('把清晰度拉到夸张也不能让单像素改动失控', () {
      // 半黑半白的强边缘：unsharp 在这里最容易拉出白边/黑边。
      const w = 64;
      const h = 64;
      final src = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * w + x) * 4;
          final v = x < w ~/ 2 ? 20 : 235;
          src[o] = v;
          src[o + 1] = v;
          src[o + 2] = v;
          src[o + 3] = 255;
        }
      }
      final out = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        clarity: 1.0,
        texture: 0.5,
      );
      var maxDelta = 0;
      for (var i = 0; i < w * h; i++) {
        final o = i * 4;
        final d = (src[o] - out[o]).abs();
        if (d > maxDelta) maxDelta = d;
      }
      expect(
        maxDelta,
        lessThanOrEqualTo(24),
        reason: '软限幅（_deltaSoftLimit）应该把过冲尖峰压住',
      );
    });
  });
}
