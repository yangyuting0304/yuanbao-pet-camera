/// 连拍最佳帧选择（切片G）。
///
/// 宠物最佳表情只有一帧，人工从十几张糊片里挑是纯粹浪费时间。
/// 这里用「拉普拉斯响应的方差」自动打分——这也是自动对焦里最常用的
/// 清晰度评价函数：清晰图边缘多、二阶差分能量高；糊片边缘被抹平、
/// 方差就低。
///
/// 打分前先在原图上按步长抽样成小灰度图，评价清晰度并不需要全分辨率，
/// 这样 5 张 2400px 的图也只需要几十毫秒。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 跨 isolate 传递的选帧任务（只用基本类型，保证可发送）。
typedef BurstRequest = ({List<Uint8List> shots, int sampleTarget});

/// 选帧结果：胜出的字节、下标与分数。
typedef BurstResult = ({Uint8List bytes, int index, double score});

/// 清晰度评分与选帧的纯算法层。
class BurstSelector {
  BurstSelector._();

  /// 计算清晰度分数，越大越清晰。
  ///
  /// [sampleTarget] 是抽样后短边的目标像素数，用来约束耗时。
  static double scoreSharpness(
    Uint8List rgba, {
    required int width,
    required int height,
    int sampleTarget = 320,
  }) {
    if (width < 3 || height < 3) return 0;
    final step = math.max(
      1,
      (math.max(width, height) / sampleTarget).floor(),
    );
    final sw = width ~/ step;
    final sh = height ~/ step;
    if (sw < 3 || sh < 3) return 0;

    // 抽样成小灰度图（Rec.709 亮度）。
    final gray = Float32List(sw * sh);
    for (var y = 0; y < sh; y++) {
      final sy = (y * step).clamp(0, height - 1);
      final rowOffset = sy * width;
      for (var x = 0; x < sw; x++) {
        final sx = (x * step).clamp(0, width - 1);
        final o = (rowOffset + sx) * 4;
        gray[y * sw + x] =
            0.2126 * rgba[o] + 0.7152 * rgba[o + 1] + 0.0722 * rgba[o + 2];
      }
    }

    // 4 邻域拉普拉斯响应的方差。
    var sum = 0.0;
    var sumSq = 0.0;
    var count = 0;
    for (var y = 1; y < sh - 1; y++) {
      final row = y * sw;
      for (var x = 1; x < sw - 1; x++) {
        final i = row + x;
        final lap =
            4 * gray[i] -
            gray[i - 1] -
            gray[i + 1] -
            gray[i - sw] -
            gray[i + sw];
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }
    if (count == 0) return 0;
    final mean = sum / count;
    final variance = sumSq / count - mean * mean;
    return variance.isFinite && variance > 0 ? variance : 0;
  }

  /// 在若干张里挑出最清晰的那张。全部解不开时退回最后一张
  /// （至少保证用户不会因为选帧失败而丢照片）。
  static BurstResult pickBest(BurstRequest request) {
    final shots = request.shots;
    if (shots.length == 1) {
      return (bytes: shots.first, index: 0, score: 0);
    }
    var bestIndex = -1;
    var bestScore = -1.0;
    for (var i = 0; i < shots.length; i++) {
      // 注意：`img.decodeImage` 遇到畸形数据会**抛异常**（不是返回 null），
      // 损坏的相机缓冲足以让整段选帧崩掉。必须自己兜住。
      final decoded = _tryDecode(shots[i]);
      if (decoded == null) continue;
      final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);
      final score = scoreSharpness(
        rgba,
        width: decoded.width,
        height: decoded.height,
        sampleTarget: request.sampleTarget,
      );
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    if (bestIndex < 0) {
      return (bytes: shots.last, index: shots.length - 1, score: 0);
    }
    return (bytes: shots[bestIndex], index: bestIndex, score: bestScore);
  }

  /// 安全解码：能解就返回图像，解不开返回 null。
  static img.Image? _tryDecode(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }
}

/// 顶层入口，供 `compute` 调用。
BurstResult runBurstSelection(BurstRequest request) =>
    BurstSelector.pickBest(request);

/// 连拍张数档位。
enum BurstCount {
  single('单张', 1),
  three('3 连拍', 3),
  five('5 连拍', 5),
  ten('10 连拍', 10);

  const BurstCount(this.label, this.count);
  final String label;
  final int count;
}
