// 画质地基 & 平台能力 —— 单元测试。
//
// 这里锁的是两条容易回归的规律：
//  1. 画质档位**绝不能退回 480p**（`medium` 是本项目画质被卡住的根因）
//  2. 降级链必须是**递减且有限的**，否则初始化失败时会反复重试拖死启动
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/camera_capability.dart';

void main() {
  group('CaptureQuality：画质档位', () {
    test('超清档不低于 1080p（不得退回 480p）', () {
      // 测试环境 kIsWeb == false，走原生档位。
      expect(CaptureQuality.ultra.preset, ResolutionPreset.max);
      expect(
        CaptureQuality.ultra.preset.index,
        greaterThan(ResolutionPreset.medium.index),
        reason: 'medium 只有约 480p，是本项目画质被卡住的根因',
      );
    });

    test('每一档都明显高于 medium', () {
      for (final q in CaptureQuality.values) {
        expect(
          q.preset.index,
          greaterThan(ResolutionPreset.medium.index),
          reason: '${q.label} 档比原来的 medium(480p) 还差，等于没改进',
        );
      }
    });

    test('档位越高，目标分辨率越高', () {
      final presets = [for (final q in CaptureQuality.values) q.preset.index];
      for (var i = 1; i < presets.length; i++) {
        expect(
          presets[i],
          greaterThan(presets[i - 1]),
          reason: '档位顺序必须与分辨率递增一致',
        );
      }
    });
  });

  group('CaptureQuality：降级链', () {
    test('降级链严格递减，且不高于所选档位', () {
      for (final q in CaptureQuality.values) {
        final chain = q.fallbackChain;
        expect(chain, isNotEmpty);
        expect(chain.first, q.preset, reason: '降级链必须从所选档位开始');
        for (final p in chain) {
          expect(
            p.index,
            lessThanOrEqualTo(q.preset.index),
            reason: '降级链里不能出现比所选档位更高的分辨率',
          );
        }
        for (var i = 1; i < chain.length; i++) {
          expect(chain[i].index, lessThan(chain[i - 1].index));
        }
      }
    });

    test('降级链有上限，避免逐档重试拖死启动', () {
      for (final q in CaptureQuality.values) {
        expect(
          q.fallbackChain.length,
          lessThanOrEqualTo(3),
          reason: '最多试 3 档，否则相机启动会被拖成几十秒',
        );
      }
    });

    test('最高档的降级链仍然落在可用范围内（不会退化到 low）', () {
      final chain = CaptureQuality.ultra.fallbackChain;
      expect(chain.length, 3);
      expect(chain, contains(ResolutionPreset.veryHigh));
      expect(
        chain.last.index,
        greaterThanOrEqualTo(ResolutionPreset.high.index),
        reason: '超清档即使降级，也应停在 720p 以上',
      );
    });

    test('每个档位的说明文案非空（设置面板要展示）', () {
      for (final q in CaptureQuality.values) {
        expect(q.label, isNotEmpty);
        expect(q.hint, isNotEmpty);
      }
    });
  });

  group('CameraCapability：能力判断', () {
    test('非网页环境下曝光与对焦默认视为可用', () {
      final cap = CameraCapability();
      // 测试运行在 VM 上，kIsWeb == false。
      expect(cap.exposureSupported, isTrue);
      expect(cap.focusSupported, isTrue);
    });

    test('曝光补偿会被夹到设备范围内', () {
      final cap = CameraCapability();
      // 默认区间为 [-2, 2]
      expect(cap.clampEv(0.85), 0.85);
      expect(cap.clampEv(5.0), 2.0);
      expect(cap.clampEv(-9.0), -2.0);
    });
  });
}
