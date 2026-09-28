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
import 'package:pet_camera/data/burst_selector.dart';

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

  // **逐帧解码 → 提取平面/灰度 → 立刻释放**。
  //
  // 不能"先把五帧全解码、再统一尺寸"：`decodeImage` 是全尺寸解码，
  // 相机原图 4000×3000 时单帧就占约 48MB，五帧 240MB —— 与后面的融合
  // 平面叠加足以顶穿进程内存上限（实拍反馈的"拍照后闪退"就是它）。
  // 改成流式之后，任意时刻只驻留一帧位图。
  img.Image? first;
  for (final bytes in frames) {
    try {
      first = img.decodeImage(bytes);
      if (first != null) break;
    } catch (_) {
      // 单帧解码失败就跳过它，其余帧照常融合。
    }
  }
  if (first == null) return frames.first;

  // 统一尺寸：以第一帧为准，其余帧缩到同尺寸才能逐像素融合。
  final longSide = math.max(first.width, first.height);
  final scale = req.maxSide > 0 && longSide > req.maxSide
      ? req.maxSide / longSide
      : 1.0;
  final targetW = (first.width * scale).round();
  final targetH = (first.height * scale).round();
  if (targetW < 8 || targetH < 8) {
    first.clear();
    return frames.first;
  }

  // 灰度图只有原图的 1/64，在这里就一起算出来——这样不必为了"稍后对齐"
  // 而把整幅位图留到最后，是流式处理能成立的关键。
  final grayW = math.max(8, targetW ~/ 8);
  final grayH = math.max(8, targetH ~/ 8);
  final planes = <Uint8List>[];
  final grays = <Uint8List>[];

  /// 收下一帧：转尺寸 → 取 RGBA 平面 → 取灰度；调用方随即释放该位图。
  void absorb(img.Image one) {
    final sized = (one.width == targetW && one.height == targetH)
        ? one
        : img.copyResize(
            one,
            width: targetW,
            height: targetH,
            interpolation: img.Interpolation.average,
          );
    planes.add(sized.getBytes(order: img.ChannelOrder.rgba));
    grays.add(_graySmall(sized, grayW, grayH));
  }

  absorb(first);
  first.clear(); // 显式清掉像素，不等 GC——这里是内存峰值的关键路径。
  first = null;

  for (var i = 1; i < frames.length; i++) {
    img.Image? one;
    try {
      one = img.decodeImage(frames[i]);
    } catch (_) {
      one = null;
    }
    // 坏帧直接跳过：planes / grays / shifts 三者下标仍一一对应。
    if (one == null) continue;
    absorb(one);
    one.clear();
  }

  if (planes.isEmpty) return frames.first;
  // 只剩一帧可用时不重编码：原图字节就是最好的结果，还省一次全尺寸编码。
  if (planes.length == 1) return frames.first;

  return _fusePlanes(planes, grays, targetW, targetH, req.jpegQuality);
}

/// 对已经"缩到统一尺寸 + 取好 RGBA 平面与灰度图"的若干帧做对齐、运动判定
/// 与抗离群平均，最后编成 JPEG。planes[0] / grays[0] 即参考帧。
///
/// 抽出来是为了让 [fuseFrames] 与 [fuseFramesWithPick] 共用**同一份融合
/// 数学**：两者只在"怎么准备 planes/grays"上不同（后者多做了一次选帧），
/// 融合本身必须逐字节一致——这是画质的核心，不允许存在第二份实现。
Uint8List _fusePlanes(
  List<Uint8List> planes,
  List<Uint8List> grays,
  int targetW,
  int targetH,
  int jpegQuality,
) {
  // 与准备 planes/grays 时同一套推导（见 absorb 里的 _graySmall）。
  final grayW = math.max(8, targetW ~/ 8);
  final grayH = math.max(8, targetH ~/ 8);

  // 对齐：每帧相对参考帧的平移量。灰度图已备好，不必再解位图。
  final refGray = grays.first;
  final shifts = <({int dx, int dy})>[const (dx: 0, dy: 0)];
  for (var i = 1; i < grays.length; i++) {
    shifts.add(_estimateShift(refGray, grays[i], grayW, grayH));
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
  return img.encodeJpg(merged, quality: jpegQuality);
}

// ───────────── 选帧 + 融合：单次解码（性能关键路径） ─────────────

/// 选帧 + 融合的合并任务（compute 要求可跨 isolate 传递，只用基本类型）。
typedef FusionPickRequest = ({
  List<Uint8List> frames,
  /// 输出长边上限。
  int maxSide,
  int jpegQuality,
  /// 清晰度评分抽样后的短边目标像素数。
  int sampleTarget,
});

/// 合并结果：成片 + 被选为参考帧的原下标 + 参与的总帧数。
typedef FusionPickResult = ({Uint8List bytes, int pickedIndex, int total});

/// **选帧 + 融合，每帧只解码一次。**
///
/// 旧流程是两步两条 compute：先 `runBurstSelection` 把每帧**全尺寸**解出来
/// 只为算一个 320px 的清晰度分数（算完整帧丢掉），紧接着 `fuseFrames` 再把
/// 每帧全尺寸解一遍。同一批字节被纯 Dart JPEG 解码 **2N 次**——12MP 单帧
/// 解码就是几百毫秒，5 连拍白做 5 次，这正是「连拍非常慢」的最大一笔开销。
///
/// 这里改成：解一帧 → 立刻缩到目标尺寸 → 在同一份 RGBA 平面上同时
/// ①打分 ②留作融合平面。解码次数 N，内存峰值不变。
///
/// 另外只保留最清晰的 [_maxFusionFrames] 帧：融合本来也只吃这么多，
/// 多留的平面每帧就是几十 MB 白占（10 连拍时旧实现会同时驻留 10 片）。
FusionPickResult fuseFramesWithPick(FusionPickRequest req) {
  final frames = req.frames;
  if (frames.isEmpty) {
    return (bytes: Uint8List(0), pickedIndex: 0, total: 0);
  }
  if (frames.length == 1) {
    return (bytes: frames.first, pickedIndex: 0, total: 1);
  }

  // **逐帧解码 → 提取平面/灰度 → 立刻释放**。不能"先全解码再统一尺寸"：
  // 相机原图 4000×3000 时单帧就占约 48MB，五帧 240MB——顶穿进程内存上限。
  img.Image? first;
  for (final bytes in frames) {
    try {
      first = img.decodeImage(bytes);
      if (first != null) break;
    } catch (_) {
      // 单帧解码失败就跳过它，其余帧照常融合。
    }
  }
  if (first == null) {
    return (bytes: frames.first, pickedIndex: 0, total: frames.length);
  }

  final longSide = math.max(first.width, first.height);
  final scale = req.maxSide > 0 && longSide > req.maxSide
      ? req.maxSide / longSide
      : 1.0;
  final targetW = (first.width * scale).round();
  final targetH = (first.height * scale).round();
  if (targetW < 8 || targetH < 8) {
    first.clear();
    return (bytes: frames.first, pickedIndex: 0, total: frames.length);
  }

  final grayW = math.max(8, targetW ~/ 8);
  final grayH = math.max(8, targetH ~/ 8);
  final planes = <Uint8List>[];
  final grays = <Uint8List>[];
  final scores = <double>[];
  final sources = <int>[];

  /// 收一帧：转尺寸 → 取 RGBA 平面 → 在同一份像素上打分 → 取灰度。
  void absorb(img.Image one, int sourceIndex) {
    final sized = (one.width == targetW && one.height == targetH)
        ? one
        : img.copyResize(
            one,
            width: targetW,
            height: targetH,
            interpolation: img.Interpolation.average,
          );
    final plane = sized.getBytes(order: img.ChannelOrder.rgba);
    // 分数在**缩放后**的平面上算：一是省掉一次全尺寸解码，二是
    // copyResize 已做过抗混叠，比在原图上跳采更不容易被摩尔纹带偏。
    final score = BurstSelector.scoreSharpness(
      plane,
      width: targetW,
      height: targetH,
      sampleTarget: req.sampleTarget,
    );

    if (planes.length < _maxFusionFrames) {
      planes.add(plane);
      grays.add(_graySmall(sized, grayW, grayH));
      scores.add(score);
      sources.add(sourceIndex);
      return;
    }
    // 已满：只有比手上最差的那帧更清晰才顶替它。
    var worst = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] < scores[worst]) worst = i;
    }
    if (score <= scores[worst]) return;
    planes[worst] = plane;
    grays[worst] = _graySmall(sized, grayW, grayH);
    scores[worst] = score;
    sources[worst] = sourceIndex;
  }

  absorb(first, 0);
  first.clear(); // 显式清掉像素，不等 GC——这里是内存峰值的关键路径。
  first = null;

  for (var i = 1; i < frames.length; i++) {
    img.Image? one;
    try {
      one = img.decodeImage(frames[i]);
    } catch (_) {
      one = null;
    }
    // 坏帧直接跳过：planes / grays / scores / sources 下标仍一一对应。
    if (one == null) continue;
    absorb(one, i);
    one.clear();
  }

  // 一帧可用（或全部解不开）时不重编码：原图字节就是最好的结果。
  if (planes.length < 2) {
    return (bytes: frames.first, pickedIndex: 0, total: frames.length);
  }

  // 把最清晰的一帧换到首位当参考帧——只换 List 引用，不做任何拷贝。
  var best = 0;
  for (var i = 1; i < scores.length; i++) {
    if (scores[i] > scores[best]) best = i;
  }
  if (best != 0) {
    void swapAt<T>(List<T> list) {
      final t = list[0];
      list[0] = list[best];
      list[best] = t;
    }

    swapAt(planes);
    swapAt(grays);
    swapAt(scores);
    swapAt(sources);
  }

  return (
    bytes: _fusePlanes(planes, grays, targetW, targetH, req.jpegQuality),
    pickedIndex: sources.first,
    total: frames.length,
  );
}
