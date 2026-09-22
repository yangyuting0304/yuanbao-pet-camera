// 主体感知滤镜（检测框驱动）—— 像素级单元测试。
//
// ①②是"宠物照片比原相机更打动人"的两个手段：
//   ① 眼区/泪痕增强锚定到检测框（不再固定画面 0.40h，猫不在中央时不打偏）
//   ② 清晰度/毛发质感按主体分区（猫身全额、背景衰减，主体跳出来）
// 这里用合成像素锁死这两个产品承诺。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/pet_filter.dart';

/// 生成纯色灰度 RGBA 图（三通道同值）。
Uint8List _solid(int w, int h, int v) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    out[i * 4] = v;
    out[i * 4 + 1] = v;
    out[i * 4 + 2] = v;
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
  group('① 眼区增强锚定到检测框', () {
    test('有框时锚定框内，原默认位置(0.50w, 0.40h)不再提亮', () {
      final src = _solid(100, 100, 60);
      // 无框：走旧的固定位置，(50, 40) 应被提亮。
      final noBox = PetFilterKernel.apply(
        src,
        width: 100,
        height: 100,
        eyeEnhance: 1.0,
      );
      // 有框（占左上 1/4）：框内眼区在 (25, 15) 附近；(50, 40) 已落到框外。
      final withBox = PetFilterKernel.apply(
        src,
        width: 100,
        height: 100,
        eyeEnhance: 1.0,
        subjectRect: (left: 0.0, top: 0.0, right: 0.5, bottom: 0.5),
      );

      expect(
        _px(noBox, 100, 50, 40)[0],
        greaterThan(60),
        reason: '无框时走旧的固定位置，(50,40) 必须被提亮',
      );
      expect(
        _px(withBox, 100, 50, 40)[0],
        closeTo(60, 2),
        reason: '眼区已锚定到检测框，(50,40) 在框外就不应再提亮',
      );
      expect(
        _px(withBox, 100, 25, 15)[0],
        greaterThan(60),
        reason: '眼区必须真正打在检测框内',
      );
    });
  });

  group('② 清晰度/质感按主体分区', () {
    test('框内全额、框外衰减', () {
      // 棋盘格（高频纹理），clarity 才有可增强的对比。
      const w = 60, h = 20;
      final src = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = ((x + y) % 2 == 0) ? 90 : 160;
          final o = (y * w + x) * 4;
          src[o] = v;
          src[o + 1] = v;
          src[o + 2] = v;
          src[o + 3] = 255;
        }
      }

      final noPart = PetFilterKernel.apply(src, width: w, height: h, clarity: 0.5);
      final part = PetFilterKernel.apply(
        src,
        width: w,
        height: h,
        clarity: 0.5,
        subjectRect: (left: 0.0, top: 0.0, right: 0.5, bottom: 1.0),
      );

      // 框内（左半，x=10）：分区与否增强一致（框内不受影响）。
      expect(_px(part, w, 10, 10), _px(noPart, w, 10, 10));

      // 框外（右半，x=50）：分区的改变量必须小于无分区（被衰减）。
      final orig = _px(src, w, 50, 10)[0];
      final dNoPart = (_px(noPart, w, 50, 10)[0] - orig).abs();
      final dPart = (_px(part, w, 50, 10)[0] - orig).abs();
      expect(dNoPart, greaterThan(0), reason: '前提：无分区时该点确实被 clarity 改变');
      expect(dPart, lessThan(dNoPart), reason: '框外清晰度增强必须被衰减');
    });
  });
}
