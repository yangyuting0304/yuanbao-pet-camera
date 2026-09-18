// 宠物实时检测 —— 坐标/类别映射与帧转换（纯逻辑，可脱离设备验证）。
//
// 这里锁死两件最容易写错、又最难在真机上发现的事：
// 1. TFLite 的类别号与 COCO 索引差一个偏移（错一位就把狗认成猫）；
// 2. YUV/BGRA 降采样取值的正确性（错一位整个跟踪框都会飘）。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/camera_frame.dart';
import 'package:pet_camera/data/pet_detector.dart';

/// 构造一张 YUV420 测试帧：Y 平面 width×height，UV 平面各 (w/2)×(h/2)。
({Uint8List y, Uint8List u, Uint8List v}) _yuv(
  int w,
  int h,
  int yv,
  int uv,
) => (
  y: Uint8List(w * h)..fillRange(0, w * h, yv),
  u: Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), uv),
  v: Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), uv),
);

void main() {
  group('COCO 类别映射：差一个偏移就会认错宠物', () {
    test('模型输出的类别号比 COCO 索引大 1', () {
      // COCO 0-based：14=bird, 15=cat, 16=dog
      expect(CocoLabels.labelOf(15), '鸟');
      expect(CocoLabels.labelOf(16), '猫', reason: '16 → COCO 15 = cat');
      expect(CocoLabels.labelOf(17), '狗', reason: '17 → COCO 16 = dog');
    });

    test('背景与无关类别一律返回 null（不显示框）', () {
      expect(CocoLabels.labelOf(0), isNull, reason: '0 是背景');
      expect(CocoLabels.labelOf(1), isNull, reason: '1 是人');
      expect(CocoLabels.labelOf(100), isNull, reason: '越界不应崩');
    });
  });

  group('帧转换：降采样到模型输入', () {
    test('YUV 中性灰输入得到中性灰输出', () {
      final f = _yuv(8, 8, 128, 128);
      final rgb = cameraFrameToRgb(
        width: 8,
        height: 8,
        planes: [f.y, f.u, f.v],
        bytesPerRow: [8, 4, 4],
        bytesPerPixel: [1, 1, 1],
        format: FrameFormat.yuv420,
        size: 4,
      );
      expect(rgb, isNotNull);
      expect(rgb!.length, 4 * 4 * 3);
      // BT.601：Y=128(全范围) → 约 130，三通道近似相等
      for (var i = 0; i < rgb.length; i += 3) {
        expect(rgb[i], closeTo(130, 2));
        expect(rgb[i + 1], closeTo(130, 2));
        expect(rgb[i + 2], closeTo(130, 2));
      }
    });

    test('输出尺寸恒为 size² × 3，与源帧比例无关', () {
      final f = _yuv(16, 9, 100, 128);
      final rgb = cameraFrameToRgb(
        width: 16,
        height: 9,
        planes: [f.y, f.u, f.v],
        bytesPerRow: [16, 8, 8],
        bytesPerPixel: [1, 1, 1],
        format: FrameFormat.yuv420,
        size: 8,
      );
      expect(rgb!.length, 8 * 8 * 3);
    });

    test('BGRA 帧按 BGR 顺序取通道（R 与 B 不能颠倒）', () {
      // 单个像素 BGRA = (10, 20, 30, 255) → RGB 应为 (30, 20, 10)
      final plane = Uint8List.fromList([10, 20, 30, 255]);
      final rgb = cameraFrameToRgb(
        width: 1,
        height: 1,
        planes: [plane],
        bytesPerRow: [4],
        bytesPerPixel: [4],
        format: FrameFormat.bgra8888,
        size: 1,
      );
      expect(rgb, isNotNull);
      expect(rgb!.sublist(0, 3), [30, 20, 10]);
    });

    test('不支持的格式返回 null（上层跳过这帧，而不是崩掉）', () {
      final f = _yuv(4, 4, 128, 128);
      final rgb = cameraFrameToRgb(
        width: 4,
        height: 4,
        planes: [f.y],
        bytesPerRow: [4],
        bytesPerPixel: [1],
        format: FrameFormat.unknown,
        size: 2,
      );
      expect(rgb, isNull);
    });

    test('平面数量不足时返回 null 而不是越界崩溃', () {
      final f = _yuv(4, 4, 128, 128);
      final rgb = cameraFrameToRgb(
        width: 4,
        height: 4,
        planes: [f.y], // 只有 Y，缺 UV
        bytesPerRow: [4, 2, 2],
        bytesPerPixel: [1, 1, 1],
        format: FrameFormat.yuv420,
        size: 2,
      );
      expect(rgb, isNull);
    });

    test('平面缓冲比标称尺寸小时不崩溃（越界像素留黑）', () {
      final f = _yuv(8, 8, 128, 128);
      final rgb = cameraFrameToRgb(
        width: 64, // 故意谎报更大的宽高
        height: 64,
        planes: [f.y, f.u, f.v],
        bytesPerRow: [64, 32, 32],
        bytesPerPixel: [1, 1, 1],
        format: FrameFormat.yuv420,
        size: 4,
      );
      expect(rgb, isNotNull, reason: '宁可部分像素为黑，也不能抛异常');
    });
  });

  group('检测结果的数据契约', () {
    test('框的中心/尺寸由四边推出，且不依赖顺序', () {
      const d = PetDetection(
        left: 0.2,
        top: 0.4,
        right: 0.6,
        bottom: 0.8,
        confidence: 0.9,
        label: '猫',
      );
      expect(d.centerX, closeTo(0.4, 1e-9));
      expect(d.centerY, closeTo(0.6, 1e-9));
      expect(d.width, closeTo(0.4, 1e-9));
      expect(d.height, closeTo(0.4, 1e-9));
      expect(d.area, closeTo(0.16, 1e-9));
    });
  });
}
