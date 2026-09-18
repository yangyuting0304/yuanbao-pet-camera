/// 相机帧 → 检测模型输入（纯函数，可单测）。
///
/// 关键优化：**不做全图转换**。1080p 全图转 RGB 每帧要几十毫秒，逐帧做必然
/// 卡死主线程；而模型只需要 320×320 —— 所以直接从 YUV/ BGRA 平面**按比例
/// 采样**，只计算 10 万个像素，单帧开销降到几毫秒。
library;

import 'dart:typed_data';

/// 帧像素格式（对应 camera 插件 ImageFormatGroup 的常用取值）。
enum FrameFormat { yuv420, bgra8888, unknown }

/// 把一帧降采样成 `size × size × 3` 的 RGB 字节。
///
/// 越界像素留黑而不是整体失败——帧流里偶尔出现平面尺寸不匹配是常态，
/// 为它丢掉整帧检测不值得。
Uint8List? cameraFrameToRgb({
  required int width,
  required int height,
  required List<Uint8List> planes,
  required List<int> bytesPerRow,
  required List<int> bytesPerPixel,
  required FrameFormat format,
  int size = 320,
}) {
  if (width <= 0 || height <= 0 || planes.isEmpty) return null;
  if (bytesPerRow.length < planes.length) return null;
  final out = Uint8List(size * size * 3);

  switch (format) {
    case FrameFormat.yuv420:
      // 缺平面说明这帧不完整：返回 null 让上层跳过，而不是拿一张黑图去推理。
      if (planes.length < 3) return null;
      return _fromYuv420(
        out: out,
        size: size,
        width: width,
        height: height,
        planes: planes,
        bytesPerRow: bytesPerRow,
        bytesPerPixel: bytesPerPixel,
      );
    case FrameFormat.bgra8888:
      return _fromBgra(
        out: out,
        size: size,
        width: width,
        height: height,
        plane: planes[0],
        rowStride: bytesPerRow[0],
        pixelStride: bytesPerPixel.isNotEmpty ? bytesPerPixel[0] : 4,
      );
    case FrameFormat.unknown:
      return null;
  }
}

Uint8List _fromYuv420({
  required Uint8List out,
  required int size,
  required int width,
  required int height,
  required List<Uint8List> planes,
  required List<int> bytesPerRow,
  required List<int> bytesPerPixel,
}) {
  final yPlane = planes[0];
  final uPlane = planes[1];
  final vPlane = planes[2];
  final yRow = bytesPerRow[0];
  final uRow = bytesPerRow[1];
  final vRow = bytesPerRow[2];
  final uPix = bytesPerPixel.length > 1 ? bytesPerPixel[1] : 1;
  final vPix = bytesPerPixel.length > 2 ? bytesPerPixel[2] : 1;

  for (var y = 0; y < size; y++) {
    final sy = (y * height ~/ size).clamp(0, height - 1);
    final syHalf = sy >> 1;
    for (var x = 0; x < size; x++) {
      final sx = (x * width ~/ size).clamp(0, width - 1);
      final sxHalf = sx >> 1;
      final yIdx = sy * yRow + sx;
      final uIdx = syHalf * uRow + sxHalf * uPix;
      final vIdx = syHalf * vRow + sxHalf * vPix;
      if (yIdx >= yPlane.length ||
          uIdx >= uPlane.length ||
          vIdx >= vPlane.length) {
        continue; // 越界像素保持黑色
      }
      _yuvToRgb(yPlane[yIdx], uPlane[uIdx], vPlane[vIdx], out, (y * size + x) * 3);
    }
  }
  return out;
}

Uint8List _fromBgra({
  required Uint8List out,
  required int size,
  required int width,
  required int height,
  required Uint8List plane,
  required int rowStride,
  required int pixelStride,
}) {
  for (var y = 0; y < size; y++) {
    final sy = (y * height ~/ size).clamp(0, height - 1);
    for (var x = 0; x < size; x++) {
      final sx = (x * width ~/ size).clamp(0, width - 1);
      final idx = sy * rowStride + sx * pixelStride;
      if (idx + 2 >= plane.length) continue;
      final o = (y * size + x) * 3;
      out[o] = plane[idx + 2]; // BGRA → RGB
      out[o + 1] = plane[idx + 1];
      out[o + 2] = plane[idx];
    }
  }
  return out;
}

/// BT.601 YUV → RGB。
///
/// Dart 的 `>>` 是算术移位，负值结果仍为负，交给 clamp 兜到 0 即可。
void _yuvToRgb(int y, int u, int v, Uint8List out, int o) {
  final c = y - 16;
  final d = u - 128;
  final e = v - 128;
  out[o] = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
  out[o + 1] = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
  out[o + 2] = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);
}
