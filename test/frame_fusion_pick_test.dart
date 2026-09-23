// 选帧 + 融合的**合并**入口（性能优化路径）。
//
// 存在的理由：旧流程是两条 compute、两次全尺寸解码——先 runBurstSelection
// 把每帧全尺寸解出来只为算一个 320px 的清晰度分数（算完整帧丢掉），紧接着
// fuseFrames 再把每帧全尺寸解一遍。同一批字节被纯 Dart JPEG 解码 **2N 次**，
// 5 连拍就是 10 次，这是「连拍非常慢」的最大一笔开销。
//
// 这里锁住三件事：
//   1. 选帧结果正确——最清晰的那张要被选为参考帧；
//   2. 参考帧恰好是第一张时，结果与 fuseFrames **逐字节一致**
//      （证明融合算法没有被复制成第二份实现）；
//   3. 任何异常都不能把照片弄丢。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pet_camera/data/frame_fusion.dart';

const int _size = 96;

/// 高频棋盘：拉普拉斯响应极高 → 必然被评为"最清晰"。
Uint8List _checker({int cell = 4}) {
  final im = img.Image(width: _size, height: _size);
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      final v = ((x ~/ cell) + (y ~/ cell)).isEven ? 235 : 20;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return img.encodePng(im);
}

/// 纯色：没有任何边缘 → 清晰度分数为 0。
Uint8List _flat(int v) {
  final im = img.Image(width: _size, height: _size);
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return img.encodePng(im);
}

Uint8List _fuse(List<Uint8List> frames) =>
    fuseFrames((frames: frames, maxSide: _size, jpegQuality: 96));

FusionPickResult _fuseWithPick(List<Uint8List> frames) => fuseFramesWithPick((
  frames: frames,
  maxSide: _size,
  jpegQuality: 96,
  sampleTarget: 320,
));

void main() {
  group('选帧', () {
    test('挑出最清晰的一帧作为参考帧', () {
      final result = _fuseWithPick([_flat(128), _checker(), _flat(128)]);
      expect(result.pickedIndex, 1, reason: '棋盘边缘最丰富，应当被选中');
      expect(result.total, 3);
      expect(img.decodeJpg(result.bytes), isNotNull, reason: '必须产出可解码的成片');
    });

    test('参考帧在首位时，结果与 fuseFrames 逐字节一致', () {
      final frames = [_checker(), _flat(128), _flat(128)];
      final picked = _fuseWithPick(frames);
      expect(picked.pickedIndex, 0);
      expect(
        picked.bytes,
        orderedEquals(_fuse(frames)),
        reason: '融合数学必须只有一份实现——参考帧相同就该逐字节相同',
      );
    });

    test('最清晰的一帧不在首位时，它会被换成参考帧', () {
      // 参考帧换成棋盘后，全图都算"运动"（帧间差异极大），
      // 结果应贴近棋盘的高对比，而不是被平均成中间灰。
      final result = _fuseWithPick([_flat(128), _flat(128), _checker()]);
      expect(result.pickedIndex, 2);
      final fused = img.decodeJpg(result.bytes)!;
      // 棋盘是 20/235 的黑白交替，平均值 128 会抹平它。
      var minV = 255;
      var maxV = 0;
      for (var y = 0; y < fused.height; y += 5) {
        for (var x = 0; x < fused.width; x += 5) {
          final v = fused.getPixel(x, y).r.toInt();
          if (v < minV) minV = v;
          if (v > maxV) maxV = v;
        }
      }
      expect(
        maxV - minV,
        greaterThan(120),
        reason: '参考帧是高对比棋盘，成片不该被融合糊成一片灰',
      );
    });
  });

  group('边界与异常：绝不能丢照片', () {
    test('单帧原样返回该帧字节', () {
      final one = _checker();
      final result = _fuseWithPick([one]);
      expect(result.bytes, same(one));
      expect(result.pickedIndex, 0);
      expect(result.total, 1);
    });

    test('空输入返回空，不抛异常', () {
      final result = _fuseWithPick(const []);
      expect(result.bytes, isEmpty);
      expect(result.pickedIndex, 0);
      expect(result.total, 0);
    });

    test('全部帧都无法解码时，退回原始字节', () {
      final broken = <Uint8List>[
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6]),
      ];
      final result = _fuseWithPick(broken);
      expect(result.bytes, isNotEmpty, reason: '解不开也要把原图交回去');
      expect(result.total, 2);
    });

    test('部分帧损坏时，用剩余的好帧继续融合', () {
      final frames = <Uint8List>[
        _checker(),
        Uint8List.fromList([9, 9, 9]),
        _flat(128),
      ];
      final result = _fuseWithPick(frames);
      expect(result.total, 3);
      expect(result.bytes.length, greaterThan(100));
      expect(img.decodeJpg(result.bytes), isNotNull);
    });
  });
}
