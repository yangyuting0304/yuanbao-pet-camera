// 融合的「预解码帧」通路 —— 契约测试。
//
// 2026-10-20：iOS 闪退与卡顿排查的收尾。融合曾在 isolate 里用纯 Dart
// `img.decodeImage` 解**全尺寸** JPEG：iPhone 14 Pro Max 可能是 48MP
// （activeFormat 决定），单帧就 192MB、每帧还要几秒。
//
// 现在的做法是：主 isolate 用引擎原生解码器（ImageIO 缩略解码）把每帧
// 缩到统一尺寸，用 TransferableTypedData **零拷贝**移交进 isolate。
//
// 这里钉死三件事：
//   ① 预解码通路能正常出片，且尺寸符合预期；
//   ② 与旧路径（isolate 内自己解）**画质相当**——不能因为换了解码器就
//      把成片做差（两条路径的缩放方式必须一致）；
//   ③ 尺寸对不上的预解码帧被安全跳过，不崩、不产出坏图。
import 'dart:isolate' show TransferableTypedData;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pet_camera/data/frame_fusion.dart';
import 'package:pet_camera/data/image_decode.dart';

/// 造一张有明确纹理与噪声的图（模拟真实连拍帧）。
Uint8List _frame(int w, int h, int seed) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = ((x * 7 + y * 13 + seed * 29) % 60) + 90;
      im.setPixelRgb(x, y, v, (v + 20) % 255, (v + 40) % 255);
    }
  }
  return img.encodeJpg(im, quality: 92);
}

/// 拉普拉斯方差（清晰度）。
double _sharpness(img.Image im) {
  var sum = 0.0;
  var sq = 0.0;
  var n = 0;
  for (var y = 1; y < im.height - 1; y++) {
    for (var x = 1; x < im.width - 1; x++) {
      double lum(int px, int py) {
        final p = im.getPixel(px, py);
        return 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
      }

      final lap =
          4 * lum(x, y) -
          lum(x - 1, y) -
          lum(x + 1, y) -
          lum(x, y - 1) -
          lum(x, y + 1);
      sum += lap;
      sq += lap * lap;
      n++;
    }
  }
  final mean = sum / n;
  return sq / n - mean * mean;
}

void main() {
  const size = 320;

  test('预解码通路能出片，且尺寸等于目标尺寸', () async {
    final frames = [_frame(size, size, 1), _frame(size, size, 2)];

    // 主 isolate 预解码：先定尺寸，再把每帧解到同一尺寸。
    final first = await decodeRgbaLimited(frames.first, size);
    expect(first, isNotNull);
    final base = first!;
    final packed = <TransferableTypedData>[];
    for (final f in frames) {
      final d = await decodeRgbaToSize(f, base.width, base.height);
      expect(d, isNotNull);
      packed.add(TransferableTypedData.fromList([d!.rgba]));
    }

    final result = fuseFramesWithPick((
      frames: frames,
      preDecoded: packed,
      preWidth: first.width,
      preHeight: first.height,
      maxSide: size,
      jpegQuality: 96,
      sampleTarget: 320,
    ));

    expect(result.total, 2);
    final out = img.decodeImage(result.bytes);
    expect(out, isNotNull);
    expect(out!.width, first.width);
    expect(out.height, first.height);
  });

  test('预解码通路与旧路径画质相当（换解码器不能把成片做差）', () async {
    final frames = [_frame(size, size, 1), _frame(size, size, 2)];

    final old = fuseFramesWithPick((
      frames: frames,
      preDecoded: null,
      preWidth: 0,
      preHeight: 0,
      maxSide: size,
      jpegQuality: 96,
      sampleTarget: 320,
    ));

    final first = await decodeRgbaLimited(frames.first, size);
    final base = first!;
    final packed = <TransferableTypedData>[];
    for (final f in frames) {
      final d = await decodeRgbaToSize(f, base.width, base.height);
      packed.add(TransferableTypedData.fromList([d!.rgba]));
    }
    final fresh = fuseFramesWithPick((
      frames: frames,
      preDecoded: packed,
      preWidth: first.width,
      preHeight: first.height,
      maxSide: size,
      jpegQuality: 96,
      sampleTarget: 320,
    ));

    final oldImage = img.decodeImage(old.bytes)!;
    final newImage = img.decodeImage(fresh.bytes)!;
    expect(newImage.width, oldImage.width);
    expect(newImage.height, oldImage.height);

    final oldSharp = _sharpness(oldImage);
    final newSharp = _sharpness(newImage);
    expect(
      newSharp,
      greaterThan(oldSharp * 0.75),
      reason: '预解码通路（原生缩略解码）不该明显比旧路径更糊',
    );
  });

  test('尺寸对不上的预解码帧被跳过，不崩也不产出坏图', () async {
    final frames = [_frame(size, size, 1), _frame(size, size, 2)];
    final first = await decodeRgbaLimited(frames.first, size);

    // 故意塞一个尺寸不对的帧（长宽乘 2）。
    final base = first!;
    final wrong = await decodeRgbaToSize(frames[1], base.width * 2, base.height * 2);
    final packed = <TransferableTypedData>[
      TransferableTypedData.fromList([base.rgba]),
      TransferableTypedData.fromList([wrong!.rgba]),
    ];

    final result = fuseFramesWithPick((
      frames: frames,
      preDecoded: packed,
      preWidth: first.width,
      preHeight: first.height,
      maxSide: size,
      jpegQuality: 96,
      sampleTarget: 320,
    ));
    // 只剩一帧可用 → 不重编码，直接返回原图字节。
    expect(result.bytes, frames.first);
  });
}
