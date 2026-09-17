// 宠物眼睛定位接入层 —— 单元测试（切片F）。
//
// 模型还没到位，但"选哪只眼、什么时候该放弃"这部分是纯逻辑，
// 必须现在就锁住：选错了会对焦到鼻梁上，那是宠物摄影里最典型的一张废片。
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/pet_eye_detector.dart';

PetEyeResult _r(Offset left, Offset right, double conf) =>
    (left: left, right: right, confidence: conf);

void main() {
  group('空实现（模型未就位）', () {
    test('isAvailable 为 false，避免上层误以为已就绪', () {
      expect(const NoPetEyeDetector().isAvailable, isFalse);
    });

    test('detect 返回 null 而不是抛异常', () async {
      final result = await const NoPetEyeDetector().detect(
        Uint8List(16),
        width: 2,
        height: 2,
      );
      expect(result, isNull);
    });
  });

  group('选眼策略', () {
    test('两只眼位置相同（持平）时稳定选左边，避免取景时来回跳', () {
      final picked = PetEyeTargeting.nearestEye(
        _r(const Offset(0.4, 0.5), const Offset(0.6, 0.5), 0.9),
      );
      expect(picked, const Offset(0.4, 0.5));
    });

    test('选画面里位置更低的那只（更靠近镜头）', () {
      final picked = PetEyeTargeting.nearestEye(
        _r(const Offset(0.62, 0.40), const Offset(0.38, 0.52), 0.9),
      );
      expect(picked, const Offset(0.38, 0.52));
    });

    test('结果为 null 时返回 null（上层退回画面中心）', () {
      expect(PetEyeTargeting.nearestEye(null), isNull);
    });

    test('置信度不足时宁可放弃，也不要对一个"猜"出来的点对焦', () {
      final weak = _r(
        const Offset(0.4, 0.5),
        const Offset(0.6, 0.6),
        PetEyeTargeting.minConfidence - 0.01,
      );
      expect(PetEyeTargeting.nearestEye(weak), isNull);
    });

    test('置信度刚好达到阈值即视为可用', () {
      final ok = _r(
        const Offset(0.4, 0.5),
        const Offset(0.6, 0.6),
        PetEyeTargeting.minConfidence,
      );
      expect(PetEyeTargeting.nearestEye(ok), isNotNull);
    });
  });

  group('眼睛区域（供眼睛增强限定范围）', () {
    test('外扩 pad 后包围两只眼', () {
      final region = PetEyeTargeting.eyeRegion(
        _r(const Offset(0.30, 0.40), const Offset(0.70, 0.44), 0.9),
        pad: 0.10,
      );
      expect(region, isNotNull);
      expect(region!.left, closeTo(0.20, 1e-9));
      expect(region.right, closeTo(0.80, 1e-9));
      expect(region.top, closeTo(0.30, 1e-9));
      expect(region.bottom, closeTo(0.54, 1e-9));
    });

    test('结果被夹在 0..1 内，不会越界', () {
      final region = PetEyeTargeting.eyeRegion(
        _r(const Offset(0.02, 0.01), const Offset(0.98, 0.99), 0.9),
        pad: 0.2,
      );
      expect(region!.left, 0.0);
      expect(region.top, 0.0);
      expect(region.right, 1.0);
      expect(region.bottom, 1.0);
    });

    test('置信度不足时不给区域（避免对错误的位置做增强）', () {
      final weak = _r(
        const Offset(0.3, 0.4),
        const Offset(0.7, 0.4),
        PetEyeTargeting.minConfidence - 0.01,
      );
      expect(PetEyeTargeting.eyeRegion(weak), isNull);
    });

    test('null 输入返回 null', () {
      expect(PetEyeTargeting.eyeRegion(null), isNull);
    });

    test('宽度与高度为正', () {
      final region = PetEyeTargeting.eyeRegion(
        _r(const Offset(0.30, 0.40), const Offset(0.70, 0.44), 0.9),
      );
      expect(region!.width, greaterThan(0));
      expect(region.height, greaterThan(0));
    });
  });
}
