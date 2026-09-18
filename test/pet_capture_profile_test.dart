// 宠物拍摄参数引擎 —— 单元测试。
//
// 这些断言锁定的都是**有产品含义的规律**，不是实现细节：
// 白毛必须加曝光、黑毛必须减曝光、猫兔龙猫必须禁闪光、
// 动态场景快门必须≥1/1000s、宠物美颜不得出现磨皮类开关。
// 后续调参时若打破这些规律，测试会立刻失败。
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/pet_capture_profile.dart';

/// 有「毛色」维度的物种。
///
/// 鱼是唯一例外：它没有毛，曝光补偿、眼睛增强、毛发质感、引诱音效这些
/// 按"毛感"或"陆地听觉"推导的规则对它都不适用（见 [PetSpecies.fish] 说明）。
/// 所以凡是"所有物种都…"的断言都要避开它，并**另写一条测试**明确记录
/// 鱼的例外行为——否则将来有人把鱼当成 bug 改回去，就没有防线了。
bool _hasCoat(PetSpecies s) => s != PetSpecies.fish;

void main() {
  group('曝光补偿：白毛加、黑毛减', () {
    test('白毛为正 EV，且幅度够大（≥ +0.7）', () {
      for (final species in PetSpecies.values.where(_hasCoat)) {
        final p = PetCaptureProfile.resolve(
          species: species,
          coat: PetCoat.white,
        );
        expect(
          p.exposureCompensation,
          greaterThanOrEqualTo(0.7),
          reason: '${species.label}白毛应显著加曝光，否则会被相机拍成灰毛',
        );
      }
    });

    test('黑毛为负 EV', () {
      for (final species in PetSpecies.values.where(_hasCoat)) {
        final p = PetCaptureProfile.resolve(
          species: species,
          coat: PetCoat.black,
        );
        expect(
          p.exposureCompensation,
          lessThan(0),
          reason: '${species.label}黑毛应减曝光，否则会拍成一团灰',
        );
      }
    });

    test('虎斑等中间毛色曝光为 0', () {
      final p = PetCaptureProfile.resolve(
        species: PetSpecies.cat,
        coat: PetCoat.tabby,
      );
      expect(p.exposureCompensation, 0);
    });
  });

  group('闪光策略：伤眼物种必须禁用', () {
    test('猫 / 兔 / 龙猫禁用闪光', () {
      for (final species in [
        PetSpecies.cat,
        PetSpecies.rabbit,
        PetSpecies.chinchilla,
      ]) {
        final p = PetCaptureProfile.resolve(
          species: species,
          coat: PetCoat.tabby,
        );
        expect(
          p.flashPolicy,
          FlashPolicy.forbidden,
          reason: '${species.label}眼睛对光敏感，必须禁闪光',
        );
      }
    });

    test('易惊物种强制静音快门', () {
      for (final species in [
        PetSpecies.cat,
        PetSpecies.rabbit,
        PetSpecies.chinchilla,
      ]) {
        final p = PetCaptureProfile.resolve(
          species: species,
          coat: PetCoat.tabby,
        );
        expect(p.silentShutter, isTrue);
      }
    });
  });

  group('快门：不糊是第一底线', () {
    test('任何物种任何场景快门不慢于 1/320s', () {
      for (final species in PetSpecies.values) {
        for (final scene in PetScene.values) {
          final p = PetCaptureProfile.resolve(
            species: species,
            coat: PetCoat.tabby,
            scene: scene,
          );
          expect(
            p.shutterDenominator,
            greaterThanOrEqualTo(320),
            reason: '${species.label}/${scene.label} 快门过慢会糊片',
          );
        }
      }
    });

    test('动态场景快门至少 1/1000s', () {
      final p = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.tabby,
        scene: PetScene.action,
      );
      expect(p.shutterDenominator, greaterThanOrEqualTo(1000));
    });

    test('动态场景启用连续对焦', () {
      final p = PetCaptureProfile.resolve(
        species: PetSpecies.cat,
        coat: PetCoat.tabby,
        scene: PetScene.action,
      );
      expect(p.continuousFocus, isTrue);
    });
  });

  group('画质上限：ISO 不得失控', () {
    test('弱光场景 ISO 上限不超过 6400', () {
      for (final species in PetSpecies.values) {
        final p = PetCaptureProfile.resolve(
          species: species,
          coat: PetCoat.black,
          scene: PetScene.lowLight,
        );
        expect(p.isoMax, lessThanOrEqualTo(6400));
      }
    });
  });

  group('毛色保护：只调亮度/对比，不做色相偏移', () {
    test('色温偏移一律为正（宠物滤镜只偏暖）', () {
      for (final species in PetSpecies.values) {
        for (final coat in PetCoat.values) {
          final p = PetCaptureProfile.resolve(species: species, coat: coat);
          expect(p.tempShift, greaterThan(0), reason: '不得使用冷调，否则毛色发灰');
        }
      }
    });

    test('饱和度增益在安全区间内（禁止过饱和）', () {
      for (final species in PetSpecies.values) {
        for (final scene in PetScene.values) {
          final p = PetCaptureProfile.resolve(
            species: species,
            coat: PetCoat.tabby,
            scene: scene,
          );
          expect(p.saturation, greaterThanOrEqualTo(0.9));
          expect(
            p.saturation,
            lessThanOrEqualTo(1.15),
            reason: '过饱和会把品种固有色"染色"',
          );
        }
      }
    });

    test('白毛高光滚降强于黑毛（白毛更怕死白）', () {
      final white = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.white,
        scene: PetScene.portrait,
      );
      final black = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.black,
        scene: PetScene.portrait,
      );
      expect(white.highlightRolloff, greaterThan(black.highlightRolloff));
    });

    test('黑毛暗部提亮强于白毛（黑毛更怕糊成一团）', () {
      final white = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.white,
        scene: PetScene.portrait,
      );
      final black = PetCaptureProfile.resolve(
        species: PetSpecies.dog,
        coat: PetCoat.black,
        scene: PetScene.portrait,
      );
      expect(black.shadowLift, greaterThan(white.shadowLift));
    });
  });

  group('美颜：质感增强而非平滑', () {
    test('有毛物种都开启眼睛增强与毛发质感增强', () {
      for (final species in PetSpecies.values.where(_hasCoat)) {
        final p = PetCaptureProfile.resolve(
          species: species,
          coat: PetCoat.tabby,
        );
        expect(p.eyeEnhance, isTrue);
        expect(p.furTextureBoost, isTrue);
      }
    });

    test('鱼例外：水下不适用眼区提亮与毛发增强', () {
      final p = PetCaptureProfile.resolve(
        species: PetSpecies.fish,
        coat: PetCoat.tabby,
      );
      expect(
        p.eyeEnhance,
        isFalse,
        reason: '眼区定位是"画面中上部椭圆"的廉价近似，鱼缸那里正好是水面与灯管',
      );
      expect(
        p.furTextureBoost,
        isFalse,
        reason: '毛发质感增强会连带放大水中的悬浮颗粒与气泡边缘，画面立刻变脏',
      );
      expect(p.tearStainFix, isFalse, reason: '鱼没有泪痕');
    });

    test('猫与狗需要泪痕淡化，兔与龙猫不需要', () {
      expect(
        PetCaptureProfile.resolve(species: PetSpecies.cat, coat: PetCoat.white)
            .tearStainFix,
        isTrue,
      );
      expect(
        PetCaptureProfile.resolve(
          species: PetSpecies.chinchilla,
          coat: PetCoat.tabby,
        ).tearStainFix,
        isFalse,
      );
    });
  });

  group('龙猫：弱光优先', () {
    test('龙猫 ISO 上限高于猫狗（夜行性）', () {
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
      expect(chilla.isoMax, greaterThan(cat.isoMax));
      expect(chilla.flashPolicy, FlashPolicy.forbidden);
    });

    test('龙猫绒毛微对比强于猫（细绒毛更易糊）', () {
      final chilla = PetCaptureProfile.resolve(
        species: PetSpecies.chinchilla,
        coat: PetCoat.tabby,
      );
      final cat = PetCaptureProfile.resolve(
        species: PetSpecies.cat,
        coat: PetCoat.tabby,
      );
      expect(chilla.clarity, greaterThan(cat.clarity));
    });
  });

  group('音效引诱', () {
    test('陆生物种都有自己的引诱音效，且不串种', () {
      for (final species in PetSpecies.values.where(_hasCoat)) {
        final p = PetCaptureProfile.resolve(
          species: species,
          coat: PetCoat.tabby,
        );
        expect(p.lureSounds, isNotEmpty, reason: '${species.label}没有配置音效');
        expect(
          p.lureSounds.every((s) => s.forSpecies == species),
          isTrue,
          reason: '不得把狗的哨声推给猫',
        );
      }
    });

    test('鱼没有引诱音效（水下声音无意义，还可能惊缸）', () {
      final p = PetCaptureProfile.resolve(
        species: PetSpecies.fish,
        coat: PetCoat.tabby,
      );
      expect(p.lureSounds, isEmpty);
    });
  });

  group('鱼缸模式：隔着玻璃拍的三条硬规则', () {
    test('必须禁闪光——闪光会被玻璃直接反回来', () {
      final p = PetCaptureProfile.resolve(
        species: PetSpecies.fish,
        coat: PetCoat.tabby,
      );
      expect(p.flashPolicy, FlashPolicy.forbidden);
      expect(p.silentShutter, isTrue, reason: '快门声与水波震动会惊鱼');
    });

    test('高光压制与暖调偏移都是全物种最强（压反光、中和水色）', () {
      final fish = PetCaptureProfile.resolve(
        species: PetSpecies.fish,
        coat: PetCoat.tabby,
      );
      for (final other in PetSpecies.values.where(_hasCoat)) {
        final o = PetCaptureProfile.resolve(
          species: other,
          coat: PetCoat.tabby,
        );
        expect(
          fish.highlightRolloff,
          greaterThanOrEqualTo(o.highlightRolloff),
          reason: '${other.label}的高光压制不该比鱼缸更强',
        );
        expect(
          fish.tempShift,
          greaterThanOrEqualTo(o.tempShift),
          reason: '${other.label}的暖调偏移不该比鱼缸更强',
        );
      }
    });

    test('任何场景下快门都不低于 1/1000s（鱼的动作碎且不可预测）', () {
      for (final scene in PetScene.values) {
        final p = PetCaptureProfile.resolve(
          species: PetSpecies.fish,
          coat: PetCoat.tabby,
          scene: scene,
        );
        expect(p.shutterDenominator, greaterThanOrEqualTo(1000));
      }
    });

    test('毛色不影响鱼的曝光——否则"白毛档"会把整个鱼缸拍过曝', () {
      final white = PetCaptureProfile.resolve(
        species: PetSpecies.fish,
        coat: PetCoat.white,
      );
      final black = PetCaptureProfile.resolve(
        species: PetSpecies.fish,
        coat: PetCoat.black,
      );
      expect(white.exposureCompensation, black.exposureCompensation);
      expect(
        white.exposureCompensation,
        lessThan(0.5),
        reason: '不能把白毛的 +0.85EV 套到鱼缸上',
      );
    });

    test('摘要文案不提毛色（鱼没有毛）', () {
      final p = PetCaptureProfile.resolve(
        species: PetSpecies.fish,
        coat: PetCoat.white,
      );
      expect(p.summary.contains('白/奶油毛'), isFalse);
      expect(p.summary.contains('鱼'), isTrue);
      expect(p.summary.contains('鱼缸整体亮度'), isTrue);
    });
  });

  group('展示文案', () {
    test('快门与曝光补偿文案格式正确', () {
      final p = PetCaptureProfile.resolve(
        species: PetSpecies.cat,
        coat: PetCoat.white,
        scene: PetScene.action,
      );
      expect(p.shutterLabel, '1/1000 s');
      expect(p.evLabel, contains('+'));
      expect(p.summary, isNotEmpty);
    });

    test('0 EV 不显示正负号', () {
      final p = PetCaptureProfile.resolve(
        species: PetSpecies.cat,
        coat: PetCoat.tabby,
      );
      expect(p.evLabel, '0 EV');
    });
  });
}
