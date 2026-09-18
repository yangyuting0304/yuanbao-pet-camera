/// 多帧融合 —— 画质超越原生相机的核心手段。
///
/// ## 为什么必须走这条路
///
/// 单帧照片里，**噪声是随机的，细节是真实的**。连拍多帧后：
///   - 同一位置的噪声在各帧间**不相关** → 平均后被抵消
///   - 真实细节在各帧间**高度相关** → 平均后原样保留
///
/// 3 帧融合即可把信噪比提升约 √3 ≈ 1.7 倍。这是**任何单帧降噪算法都拿不到**
/// 的增益：单帧降噪只能"用模糊换降噪"，细节必然一起丢。
/// 苹果的 Deep Fusion 正是这个思路。
///
/// ## 运动自适应是关键
///
/// 无脑平均会把"猫在动"的部分糊出鬼影。所以逐像素判断帧间一致性：
///   - 帧间差异小（静止区）→ 融合降噪
///   - 帧间差异大（运动区）→ **直接用参考帧**，绝不留拖影
///
/// 这一条决定了融合到底是"提升画质"还是"毁片"。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 融合任务（compute 要求可跨 isolate 传递，只用基本类型）。
typedef FusionRequest = ({
  List<Uint8List> frames,
  /// 输出长边上限（与滤镜同一档，避免内存爆掉）。
  int maxSide,
  int jpegQuality,
});

/// 帧间极差超过它 → 判定该像素"动了"，不参与融合。
///
/// 取值权衡：太低会把噪声误判成运动（融合退化、白忙一场）；
/// 太高会把运动误判成静止（出现鬼影）。26 落在"噪声幅度（≤15）"
/// 与"运动差异（≥40）"之间。
const int _motionThreshold = 26;

/// 对齐搜索半径（按 1/8 降采样尺度计）。
/// 手持 0.3 秒内的抖动通常在原图 ±80px 内，1/8 后约 ±10px。
const int _alignRadius = 10;

/// 找参考帧与当前帧之间的平移量（在当前帧里，ref[y][x] ≈ cur[y+dy][x+dx]）。
///
/// 用 SAD（绝对差和）在 1/8 灰度图上穷举搜索：这个尺度下噪声已被平滑，
/// 而且搜索代价极低（几百个候选 × 几千个采样点）。
({int dx, int dy}) _estimateShift(
  Uint8List ref,
  Uint8List cur,
  int w,
  int h,
) {
  // 搜索半径不得超过图幅的 1/4：否则采样区间为空、SAD 恒为 0，
  // 位移会被错判成搜索边界的极值（足以把整帧推出画面，
  // 融合随即全部退回参考帧 = 白忙一场）。小图场景真的会踩到。
  final radius = math.min(_alignRadius, math.min(w, h) ~/ 4);
  if (radius < 1) return (dx: 0, dy: 0);

  var bestDx = 0;
  var bestDy = 0;
  var bestScore = 1 << 30;
  for (var dy = -radius; dy <= radius; dy++) {
    for (var dx = -radius; dx <= radius; dx++) {
      var sad = 0;
      // 步长 2 采样：精度足够，速度翻倍。
      for (var y = radius; y < h - radius; y += 2) {
        final row = y * w;
        final rowShift = (y + dy) * w;
        for (var x = radius; x < w - radius; x += 2) {
          sad += (ref[row + x] - cur[rowShift + x + dx]).abs();
        }
      }
      if (sad < bestScore) {
        bestScore = sad;
        bestDx = dx;
        bestDy = dy;
      }
    }
  }
  return (dx: bestDx, dy: bestDy);
}

/// 把一帧缩到 1/8 并转灰度，专供对齐搜索用。
Uint8List _graySmall(img.Image src, int w, int h) {
  final small = img.copyResize(src, width: w, height: h);
  final rgba = small.getBytes(order: img.ChannelOrder.rgba);
  final out = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    final o = i * 4;
    out[i] = (0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2])
        .round()
        .clamp(0, 255);
  }
  return out;
}

/// 离群剔除容差（8bit 亮度）。
/// 样本与均值的差超过它就认为该样本不可信（某帧糊了 / 被遮挡）。
const int _outlierTolerance = 40;

/// 最多参与融合的帧数。
///
/// 降噪收益按 √N 增长（3 帧 42%、5 帧 55%、9 帧 67%），而耗时与内存线性上涨。
/// 5 帧是这条曲线上的拐点：再往上加，拍照等待时间的代价超过画质收益。
/// （苹果 Deep Fusion 用 9 帧，代价是它有专用硬件做对齐与融合。）
const int _maxFusionFrames = 5;

/// 抗离群平均（支持最多 [_maxFusionFrames] 个样本）。
///
/// **为什么不用中值**：三样本中值的降噪只有约 11%，而平均可达 42%（1/√N）
/// ——这 4 倍差距正是"能不能超过原生相机"的本钱。
/// 但纯平均怕异常帧，所以先算均值、剔掉偏离过大的样本、再重新平均。
/// 用"均值 + 剔除 + 重平均"而不是中值，是因为中值要排序，
/// 逐像素排序在三千万次调用下会直接拖垮耗时可观。
int _robustAverageOf(Int32List values, int count) {
  if (count <= 1) return values[0];
  var sum = 0;
  for (var i = 0; i < count; i++) {
    sum += values[i];
  }
  final mean = sum / count;
  var keptSum = 0;
  var kept = 0;
  for (var i = 0; i < count; i++) {
    if ((values[i] - mean).abs() <= _outlierTolerance) {
      keptSum += values[i];
      kept++;
    }
  }
  return kept == 0 ? mean.round() : (keptSum / kept).round();
}

/// 运动判定的块边长。
///
/// **必须先块平均再判定**：单像素的帧间极差里混着两帧各自的噪声
/// （幅度 ±10 的噪声叠起来极差能到 40），会直接把阈值击穿，
/// 结果是"到处都在动"、融合完全不生效。按 4×4 平均后噪声降 4 倍，
/// 而运动造成的差异不受影响，判定才可靠。
const int _motionBlock = 4;

/// 按块判定"这块在动吗"。返回每块 1 字节：1 = 运动、0 = 静止。
Uint8List _detectMotion(
  List<Uint8List> planes,
  List<({int dx, int dy})> shifts,
  int w,
  int h,
  double scaleBack,
) {
  final bw = (w + _motionBlock - 1) ~/ _motionBlock;
  final bh = (h + _motionBlock - 1) ~/ _motionBlock;
  final blocks = bw * bh;
  final out = Uint8List(blocks);
  final used = math.min(_maxFusionFrames, planes.length);
  if (used < 2) return out; // 不足两帧无从比较

  final minOf = List<int>.filled(blocks, 255);
  final maxOf = List<int>.filled(blocks, 0);

  for (var f = 0; f < used; f++) {
    final sh = shifts[f];
    final dx = (sh.dx * scaleBack).round();
    final dy = (sh.dy * scaleBack).round();
    final acc = List<int>.filled(blocks, 0);
    final cnt = List<int>.filled(blocks, 0);
    for (var y = 0; y < h; y++) {
      final sy = y + dy;
      if (sy < 0 || sy >= h) continue;
      final row = sy * w;
      final brow = (y ~/ _motionBlock) * bw;
      for (var x = 0; x < w; x++) {
        final sx = x + dx;
        if (sx < 0 || sx >= w) continue;
        final o = (row + sx) * 4;
        final luma =
            (planes[f][o] * 299 + planes[f][o + 1] * 587 + planes[f][o + 2] * 114) ~/
            1000;
        final b = brow + (x ~/ _motionBlock);
        acc[b] += luma;
        cnt[b]++;
      }
    }
    for (var b = 0; b < blocks; b++) {
      if (cnt[b] == 0) continue;
      final mean = acc[b] ~/ cnt[b];
      if (mean < minOf[b]) minOf[b] = mean;
      if (mean > maxOf[b]) maxOf[b] = mean;
    }
  }

  for (var b = 0; b < blocks; b++) {
    out[b] = (maxOf[b] - minOf[b]) > _motionThreshold ? 1 : 0;
  }
  return out;
}

/// 多帧融合入口（供 `compute` 调用）。
///
/// 任何一步失败都退回**参考帧**——融合是加分项，绝不能反过来把照片弄丢。
Uint8List fuseFrames(FusionRequest req) {
  final frames = req.frames;
  if (frames.isEmpty) return Uint8List(0);
  if (frames.length == 1) return frames.first;

  final decoded = <img.Image>[];
  for (final bytes in frames) {
    try {
      final one = img.decodeImage(bytes);
      if (one != null) decoded.add(one);
    } catch (_) {
      // 单帧解码失败就跳过它，其余帧照常融合。
    }
  }
  if (decoded.isEmpty) return frames.first;
  if (decoded.length == 1) {
    return img.encodeJpg(decoded.first, quality: req.jpegQuality);
  }

  // 统一尺寸：以第一帧为准，其余帧缩到同尺寸才能逐像素融合。
  final longSide = math.max(decoded[0].width, decoded[0].height);
  final scale = req.maxSide > 0 && longSide > req.maxSide
      ? req.maxSide / longSide
      : 1.0;
  final targetW = (decoded[0].width * scale).round();
  final targetH = (decoded[0].height * scale).round();
  if (targetW < 8 || targetH < 8) return frames.first;

  final planes = <Uint8List>[];
  for (final one in decoded) {
    final sized = (one.width == targetW && one.height == targetH)
        ? one
        : img.copyResize(
            one,
            width: targetW,
            height: targetH,
            interpolation: img.Interpolation.average,
          );
    planes.add(sized.getBytes(order: img.ChannelOrder.rgba));
  }

  // 对齐：把每帧相对参考帧的平移量找出来。
  final grayW = math.max(8, targetW ~/ 8);
  final grayH = math.max(8, targetH ~/ 8);
  final refGray = _graySmall(decoded[0], grayW, grayH);
  final shifts = <({int dx, int dy})>[const (dx: 0, dy: 0)];
  for (var i = 1; i < decoded.length; i++) {
    shifts.add(
      _estimateShift(refGray, _graySmall(decoded[i], grayW, grayH), grayW, grayH),
    );
  }
  // 灰度图上的位移量要放回原尺寸。
  final scaleBack = targetW / grayW;

  // 运动判定在**块**上做（见 _detectMotion）：单像素极差会被噪声击穿。
  final motion = _detectMotion(planes, shifts, targetW, targetH, scaleBack);
  final motionW = (targetW + _motionBlock - 1) ~/ _motionBlock;

  final n = targetW * targetH;
  final out = Uint8List(n * 4);
  final layers = planes.length;
  final ref = planes[0];

  // 每像素的样本缓冲在主循环外分配一次——逐像素 new List 会拖垮性能。
  final rs = Int32List(_maxFusionFrames);
  final gs = Int32List(_maxFusionFrames);
  final bs = Int32List(_maxFusionFrames);

  for (var y = 0; y < targetH; y++) {
    final blockRow = (y ~/ _motionBlock) * motionW;
    for (var x = 0; x < targetW; x++) {
      final o = (y * targetW + x) * 4;

      if (motion[blockRow + (x ~/ _motionBlock)] != 0) {
        // 运动块：整块退回参考帧，绝不留鬼影——宁可噪一点，也不要糊。
        out[o] = ref[o];
        out[o + 1] = ref[o + 1];
        out[o + 2] = ref[o + 2];
        out[o + 3] = ref[o + 3];
        continue;
      }

      // 静止块：把所有可用帧的样本收齐，再抗离群平均。
      rs[0] = ref[o];
      gs[0] = ref[o + 1];
      bs[0] = ref[o + 2];
      var samples = 1;
      for (var f = 1; f < layers && samples < _maxFusionFrames; f++) {
        final sh = shifts[f];
        final sx = x + (sh.dx * scaleBack).round();
        final sy = y + (sh.dy * scaleBack).round();
        if (sx < 0 || sx >= targetW || sy < 0 || sy >= targetH) continue;
        final so = (sy * targetW + sx) * 4;
        rs[samples] = planes[f][so];
        gs[samples] = planes[f][so + 1];
        bs[samples] = planes[f][so + 2];
        samples++;
      }

      if (samples < 2) {
        // 对齐后越界的像素没有可用样本，直接用参考帧。
        out[o] = rs[0];
        out[o + 1] = gs[0];
        out[o + 2] = bs[0];
      } else {
        out[o] = _robustAverageOf(rs, samples);
        out[o + 1] = _robustAverageOf(gs, samples);
        out[o + 2] = _robustAverageOf(bs, samples);
      }
      out[o + 3] = ref[o + 3];
    }
  }

  final merged = img.Image.fromBytes(
    width: targetW,
    height: targetH,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(merged, quality: req.jpegQuality);
}
