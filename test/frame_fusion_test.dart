// 多帧融合 —— 这是"画质优于原生相机"的核心手段，必须锁死它的行为。
//
// 三条产品承诺，逐个用合成像素验证：
//  1. 静止区域的随机噪声要被压下去（融合的全部意义）；
//  2. 运动区域必须逐像素退回参考帧（否则会出现鬼影，比噪点更难看）；
//  3. 任何异常都不能把照片弄丢（融合是加分项，不是必需品）。
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pet_camera/data/frame_fusion.dart';

const int _size = 96;

/// 造一帧：底色 + 确定性噪声（用 PNG 无损编码，避免 JPEG 损失干扰测量）。
Uint8List _frame(int base, int amp, int seed, {int? patchValue}) {
  final rnd = math.Random(seed);
  final im = img.Image(width: _size, height: _size);
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      var v = base + rnd.nextInt(amp * 2 + 1) - amp;
      // patchValue：在右下角贴一块"运动"区域。
      if (patchValue != null && x > _size * 0.6 && y > _size * 0.6) {
        v = patchValue;
      }
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return img.encodePng(im);
}

/// 相邻像素差的平均绝对值（噪声的粗略度量）。
double _roughness(img.Image image) {
  var sum = 0.0;
  var count = 0;
  for (var y = 1; y < image.height - 1; y++) {
    for (var x = 1; x < image.width - 2; x++) {
      final a = image.getPixel(x, y).r.toDouble();
      final b = image.getPixel(x + 1, y).r.toDouble();
      sum += (a - b).abs();
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}

Uint8List _fuse(List<Uint8List> frames) => fuseFrames((
  frames: frames,
  maxSide: _size,
  jpegQuality: 96,
));

void main() {
  group('静止区域：噪声必须被压下去', () {
    test('三帧带噪融合后，粗糙度显著低于单帧', () {
      final a = _frame(128, 12, 1);
      final b = _frame(128, 12, 2);
      final c = _frame(128, 12, 3);

      final fused = img.decodeJpg(_fuse([a, b, c]))!;
      // 对照组必须走**同样的 JPEG 编码**再比：JPEG 本身就会平滑高频，
      // 拿无损 PNG 去比会把编码损失误当成融合收益（或反过来掩盖它）。
      final singleEncoded = img.decodeJpg(
        img.encodeJpg(img.decodePng(a)!, quality: 96),
      )!;

      final fusedRough = _roughness(fused);
      final singleRough = _roughness(singleEncoded);
      expect(
        fusedRough,
        lessThan(singleRough * 0.85),
        reason:
            '中值融合应把随机噪声明显压下去——这是融合存在的全部意义'
            '（单帧 $singleRough → 融合 $fusedRough）',
      );
    });

    test('帧数越多降噪越强（5 帧优于 3 帧）', () {
      // 降噪收益按 √N 增长。这条测试锁住"多给帧就该多拿到收益"，
      // 防止将来把 _maxFusionFrames 调小却没人发现画质退步。
      final frames = [for (var i = 0; i < 5; i++) _frame(128, 12, 100 + i)];
      final three = img.decodeJpg(_fuse(frames.sublist(0, 3)))!;
      final five = img.decodeJpg(_fuse(frames))!;
      expect(
        _roughness(five),
        lessThan(_roughness(three)),
        reason: '5 帧的降噪必须强于 3 帧',
      );
    });

    test('三帧完全相同时，融合结果与单帧基本一致（不引入额外损失）', () {
      final same = _frame(128, 6, 7);
      final fused = img.decodeJpg(_fuse([same, same, same]))!;
      final single = img.decodePng(same)!;
      // 输出经过了一次 JPEG 编码，允许小幅差异。
      var maxDiff = 0;
      for (var y = 0; y < _size; y += 7) {
        for (var x = 0; x < _size; x += 7) {
          final d =
              (fused.getPixel(x, y).r.toInt() -
                      single.getPixel(x, y).r.toInt())
                  .abs();
          if (d > maxDiff) maxDiff = d;
        }
      }
      expect(maxDiff, lessThan(12), reason: '输入相同时不该被改出明显差异');
    });
  });

  group('运动区域：必须退回参考帧，绝不留鬼影', () {
    test('帧间差异大的区块不被融合（取参考帧原值）', () {
      // 参考帧：右下角是 40 的暗块；另两帧同一位置是 200 的亮块。
      final ref = _frame(128, 8, 11, patchValue: 40);
      final moving1 = _frame(128, 8, 12, patchValue: 200);
      final moving2 = _frame(128, 8, 13, patchValue: 200);

      final fused = img.decodeJpg(_fuse([ref, moving1, moving2]))!;

      // 运动区（右下角）应保持参考帧的暗值，而不是被平均成中间灰。
      final patch = fused.getPixel((_size * 0.8).round(), (_size * 0.8).round());
      expect(
        patch.r,
        lessThan(80),
        reason: '运动区域若被融合成中间值，就是鬼影——比噪点难看得多',
      );

      // 静止区（左上角）仍应是底色附近，说明融合正常工作。
      final still = fused.getPixel(8, 8);
      expect(still.r, closeTo(128, 20));
    });

    test('全图都在动时，结果退化为参考帧（不产生平均糊）', () {
      final ref = _frame(60, 4, 21);
      final bright1 = _frame(220, 4, 22);
      final bright2 = _frame(220, 4, 23);
      final fused = img.decodeJpg(_fuse([ref, bright1, bright2]))!;
      // 参考帧整体暗（60），另两帧整体亮（220）→ 运动判定到处成立，
      // 输出应贴近参考帧，而不是两者平均出来的 140。
      expect(fused.getPixel(48, 48).r, lessThan(100));
    });
  });

  group('异常与边界：融合失败绝不能弄丢照片', () {
    test('只有一帧时原样返回该帧字节', () {
      final one = _frame(128, 5, 31);
      final out = _fuse([one]);
      expect(out, same(one));
    });

    test('空输入返回空，不抛异常', () {
      expect(_fuse(const []), isEmpty);
    });

    test('全部帧都无法解码时，退回原始字节', () {
      final broken1 = Uint8List.fromList([1, 2, 3]);
      final broken2 = Uint8List.fromList([4, 5, 6]);
      final out = _fuse([broken1, broken2]);
      expect(out, isNotEmpty, reason: '解不开也要把原图交回去');
    });

    test('部分帧损坏时，用剩余的好帧继续融合', () {
      final good1 = _frame(128, 8, 41);
      final good2 = _frame(128, 8, 42);
      final broken = Uint8List.fromList([9, 9, 9]);
      final out = _fuse([good1, broken, good2]);
      expect(out.length, greaterThan(100), reason: '不该因为一帧坏掉就整组失败');
    });
  });
}
