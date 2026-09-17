// 连拍最佳帧选择 —— 单元测试。
//
// 评分函数是"从一堆糊片里自动挑出最清晰那张"的唯一依据，
// 一旦方向反了（糊片得分更高），功能就会把最差的照片推给用户。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pet_camera/data/burst_selector.dart';

/// 造一张纯色 RGBA。
Uint8List _flat(int w, int h, int v) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    out[i * 4] = v;
    out[i * 4 + 1] = v;
    out[i * 4 + 2] = v;
    out[i * 4 + 3] = 255;
  }
  return out;
}

/// 造一张棋盘图：clear=true 时高频锐利，false 时是低对比度的"糊片"。
Uint8List _checker(int w, int h, {required int amp, required int cell}) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final on = ((x ~/ cell) + (y ~/ cell)) % 2 == 0;
      final v = on ? 128 + amp : 128 - amp;
      final o = (y * w + x) * 4;
      out[o] = v;
      out[o + 1] = v;
      out[o + 2] = v;
      out[o + 3] = 255;
    }
  }
  return out;
}

/// 把 RGBA 编成 PNG，供 pickBest 解码。
Uint8List _png(Uint8List rgba, int w, int h) {
  final im = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodePng(im);
}

void main() {
  group('清晰度评分', () {
    test('纯色图分数为 0（没有任何边缘）', () {
      final score = BurstSelector.scoreSharpness(
        _flat(64, 64, 128),
        width: 64,
        height: 64,
      );
      expect(score, closeTo(0, 1e-6));
    });

    test('高频棋盘图分数明显大于 0', () {
      final score = BurstSelector.scoreSharpness(
        _checker(64, 64, amp: 60, cell: 1),
        width: 64,
        height: 64,
      );
      expect(score, greaterThan(0));
    });

    test('高对比度（清晰）比低对比度（糊）得分高', () {
      final sharp = BurstSelector.scoreSharpness(
        _checker(64, 64, amp: 60, cell: 2),
        width: 64,
        height: 64,
      );
      final blurry = BurstSelector.scoreSharpness(
        _checker(64, 64, amp: 6, cell: 2),
        width: 64,
        height: 64,
      );
      expect(
        sharp,
        greaterThan(blurry),
        reason: '糊片边缘被抹平、二阶差分能量低，必须得分更低',
      );
    });

    test('尺寸过小返回 0 而不是抛异常', () {
      expect(BurstSelector.scoreSharpness(_flat(2, 2, 100), width: 2, height: 2), 0);
    });

    test('分数随边缘密度增加而增加', () {
      final dense = BurstSelector.scoreSharpness(
        _checker(128, 128, amp: 50, cell: 1),
        width: 128,
        height: 128,
      );
      final sparse = BurstSelector.scoreSharpness(
        _checker(128, 128, amp: 50, cell: 16),
        width: 128,
        height: 128,
      );
      expect(dense, greaterThan(sparse));
    });
  });

  group('选帧', () {
    test('单张时直接返回，不做解码', () {
      final only = Uint8List.fromList([1, 2, 3]);
      final result = BurstSelector.pickBest((shots: [only], sampleTarget: 320));
      expect(result.index, 0);
      expect(result.bytes, only);
    });

    test('挑出最清晰的那一张', () {
      final blurry = _png(_checker(64, 64, amp: 4, cell: 2), 64, 64);
      final sharp = _png(_checker(64, 64, amp: 70, cell: 2), 64, 64);
      final blurry2 = _png(_checker(64, 64, amp: 8, cell: 2), 64, 64);

      final result = BurstSelector.pickBest((
        shots: [blurry, sharp, blurry2],
        sampleTarget: 320,
      ));
      expect(result.index, 1, reason: '中间那张最清晰，必须被选中');
      expect(result.score, greaterThan(0));
    });

    test('糊涂在最前 / 最后都能正确挑出中间的清晰帧', () {
      final sharp = _png(_checker(64, 64, amp: 70, cell: 2), 64, 64);
      final blurry = _png(_checker(64, 64, amp: 4, cell: 2), 64, 64);
      expect(
        BurstSelector.pickBest((shots: [blurry, sharp], sampleTarget: 320))
            .index,
        1,
      );
      expect(
        BurstSelector.pickBest((shots: [sharp, blurry], sampleTarget: 320))
            .index,
        0,
      );
    });

    test('全部解不开时退回最后一张，保证不丢照片', () {
      final junk = Uint8List.fromList([0, 1, 2, 3, 4]);
      final result = BurstSelector.pickBest((
        shots: [junk, junk, junk],
        sampleTarget: 320,
      ));
      expect(result.bytes, junk);
      expect(result.index, 2);
    });

    test('部分解不开时仍能从可解的部分里挑', () {
      final junk = Uint8List.fromList([9, 9, 9]);
      final sharp = _png(_checker(64, 64, amp: 70, cell: 2), 64, 64);
      final result = BurstSelector.pickBest((
        shots: [junk, sharp, junk],
        sampleTarget: 320,
      ));
      expect(result.index, 1);
    });
  });

  group('连拍档位', () {
    test('档位数值递增且与文案一致', () {
      final counts = [for (final b in BurstCount.values) b.count];
      for (var i = 1; i < counts.length; i++) {
        expect(counts[i], greaterThan(counts[i - 1]));
      }
      expect(BurstCount.single.count, 1);
      expect(BurstCount.ten.count, 10);
    });

    test('每个档位都有非空文案', () {
      for (final b in BurstCount.values) {
        expect(b.label, isNotEmpty);
      }
    });
  });
}
