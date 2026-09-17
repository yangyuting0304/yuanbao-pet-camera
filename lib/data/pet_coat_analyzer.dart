/// 毛色自动识别。
///
/// ## 为什么这个不需要模型
///
/// 毛色不是"识别"问题，而是**颜色统计**问题——白毛就是画面主体亮、
/// 黑毛就是暗、蓝灰毛就是中灰且低饱和、虎斑橘猫就是中高明度且高饱和。
/// 采样主体区域算几个统计量就能稳定分类，比跑模型快几个数量级，
/// 而且**网页端也能用**（模型方案在网页端跑不了）。
///
/// ## 为什么毛色值得自动识别
///
/// 毛色决定了整个参数集里最关键的一项——**曝光补偿**。
/// 白毛被相机拍成灰毛、黑毛被拍成一团灰，是宠物摄影最高频的两个翻车点。
/// 把毛色自动判对，「减少用户选择」这件事就完成了一大半。
///
/// ## 两个被测试逼出来的设计决定
///
/// 1. **中心加权采样**，而不是中心区域等权平均。
///    等权平均时，只要背景在中心区域里占比够大就会把结果带偏
///    （黑背景里的白猫会被判成花色）。按到画面中心的距离加权后，
///    主体（几乎总在中间）自然占主导。
///
/// 2. **「花色」用亮部/暗部占比判断，而不是亮度离散度**。
///    离散度对背景同样敏感：黑背景 + 白猫的离散度可以比真正的黑白猫还大。
///    花色的本质是"**同时**存在大片深色和浅色毛"，直接量这两个占比才准确。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'pet_capture_profile.dart';

/// 毛色分析结果。
typedef PetCoatAnalysis = ({
  /// 判定出的毛色分组。
  PetCoat coat,

  /// 置信度 0.3~0.95。低于阈值时上层应提示用户确认。
  double confidence,

  /// 加权平均亮度 0..1。
  double meanLuma,

  /// 亮部像素占比（亮度 ≥ [PetCoatAnalyzer.lightLuma]）。
  double lightFraction,

  /// 暗部像素占比（亮度 ≤ [PetCoatAnalyzer.darkLuma]）。
  double darkFraction,

  /// 加权平均饱和度 0..1。
  double saturation,

  /// 一句人话解释，用于在界面上告诉用户"为什么判成这个"。
  String reason,
});

/// 毛色分析器。
class PetCoatAnalyzer {
  PetCoatAnalyzer._();

  /// 采样区域边长占画面的比例。
  ///
  /// 只取**画面正中心**：宠物拍摄几乎都会把主体放在中间，取大范围会被背景
  /// （草地、墙面、沙发）带偏。
  ///
  /// 取 40% 而不是更大，是被实测逼出来的：中心加权是"可分离"的
  /// （`wx * wy`），二维占比实际上是两个一维占比的**乘积**，所以权重比
  /// 直觉上更集中在正中心。62% 的 ROI 配加权后，一只占画面 40% 宽的白猫
  /// 只拿到 0.69 的二维占比，会被误判成花色。收到 40% 后同样场景稳定判白。
  ///
  /// **已知边界**：宠物在画面里小于约 25% 时判定会退化，此时置信度
  /// 会掉到阈值以下，[PetAutoProfiler] 会提示用户确认，而不是硬套错参数。
  static const double roiFraction = 0.40;

  /// 判定阈值。集中在这里，让测试与调参有唯一事实来源。
  static const double whiteLuma = 0.62;
  static const double blackLuma = 0.28;
  static const double greySaturation = 0.16;

  /// 亮度达到这个值算"亮部"。
  static const double lightLuma = 0.72;

  /// 亮度低于这个值算"暗部"。
  static const double darkLuma = 0.26;

  /// 亮部与暗部各自占比都超过这个值，才判为花色。
  static const double multiShare = 0.25;

  /// 分析一张 RGBA8 图，返回毛色判定。
  static PetCoatAnalysis analyze(
    Uint8List rgba, {
    required int width,
    required int height,
    int sampleTarget = 160,
  }) {
    if (width < 4 || height < 4) return _fallback('图像太小，无法分析');

    // 中心 ROI
    final roiW = (width * roiFraction).round().clamp(2, width);
    final roiH = (height * roiFraction).round().clamp(2, height);
    final roiX = (width - roiW) ~/ 2;
    final roiY = (height - roiH) ~/ 2;
    final centerX = roiX + roiW / 2.0;
    final centerY = roiY + roiH / 2.0;
    final halfW = roiW / 2.0;
    final halfH = roiH / 2.0;

    final step = math.max(1, (math.max(roiW, roiH) / sampleTarget).floor());

    var sumW = 0.0;
    var sumLuma = 0.0;
    var sumSat = 0.0;
    var lightW = 0.0;
    var darkW = 0.0;

    for (var y = roiY; y < roiY + roiH; y += step) {
      final ny = (y - centerY) / halfH;
      final wy = 1.0 - ny * ny;
      if (wy <= 0) continue;
      final rowOffset = y * width;
      for (var x = roiX; x < roiX + roiW; x += step) {
        final nx = (x - centerX) / halfW;
        final w = wy * (1.0 - nx * nx);
        if (w <= 0) continue;

        final o = (rowOffset + x) * 4;
        final r = rgba[o] / 255.0;
        final g = rgba[o + 1] / 255.0;
        final b = rgba[o + 2] / 255.0;

        final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        final sat = maxC <= 0 ? 0.0 : (maxC - minC) / maxC;

        sumW += w;
        sumLuma += luma * w;
        sumSat += sat * w;
        if (luma >= lightLuma) lightW += w;
        if (luma <= darkLuma) darkW += w;
      }
    }

    if (sumW <= 0) return _fallback('采样区域为空');

    return classify(
      meanLuma: sumLuma / sumW,
      saturation: sumSat / sumW,
      lightFraction: lightW / sumW,
      darkFraction: darkW / sumW,
    );
  }

  /// 由统计量分类。抽成独立方法，方便用构造数据直接测边界。
  static PetCoatAnalysis classify({
    required double meanLuma,
    required double saturation,
    required double lightFraction,
    required double darkFraction,
  }) {
    PetCoatAnalysis out({
      required PetCoat coat,
      required double margin,
      required String reason,
    }) => (
      coat: coat,
      confidence: _confidenceFromMargin(margin),
      meanLuma: meanLuma,
      lightFraction: lightFraction,
      darkFraction: darkFraction,
      saturation: saturation,
      reason: reason,
    );

    /// 离"花色"边界还有多远：已判为花色时为正，接近阈值时为负。
    final marginMulti =
        (math.min(lightFraction, darkFraction) - multiShare) / multiShare;

    /// 离白毛 / 黑毛边界的归一化距离。
    final marginWhite = (meanLuma - whiteLuma) / (1 - whiteLuma);
    final marginBlack = (blackLuma - meanLuma) / blackLuma;

    /// 中段离上下两条边界的距离（取更近的一侧）。
    final marginMid = math.min(
      (whiteLuma - meanLuma) / (whiteLuma - blackLuma),
      (meanLuma - blackLuma) / (whiteLuma - blackLuma),
    );

    /// 离"低饱和（灰）"边界的距离。
    final marginGrey = (saturation - greySaturation) / greySaturation;

    // ① 花色优先：主体同时有大片深色和浅色毛。这一条必须最先判，
    //    否则黑白猫会被"平均亮度居中"带走，判成蓝灰或虎斑。
    if (marginMulti >= 0) {
      return out(
        coat: PetCoat.multi,
        margin: marginMulti,
        reason: '主体同时存在大片深色与浅色毛，判为花色/双色',
      );
    }

    // ② 亮 → 白/奶油毛。白毛怕被相机拍暗，需要加曝光。
    if (marginWhite >= 0) {
      return out(
        coat: PetCoat.white,
        margin: math.min(marginWhite, -marginMulti),
        reason: '主体很亮，判为白/奶油毛——需要加曝光，否则会被拍成灰毛',
      );
    }

    // ③ 暗 → 黑/深毛。黑毛怕被相机提亮成一团灰，需要减曝光。
    if (marginBlack >= 0) {
      return out(
        coat: PetCoat.black,
        margin: math.min(marginBlack, -marginMulti),
        reason: '主体很暗，判为黑/深毛——需要减曝光并提亮暗部',
      );
    }

    // ④ 中灰且低饱和 → 蓝灰/纯色亮毛（英短这类最容易"发灰显脏"）。
    if (marginGrey <= 0) {
      return out(
        coat: PetCoat.blueGrey,
        margin: math.min(-marginGrey, marginMid),
        reason: '中灰且颜色很淡，判为蓝灰/纯色亮毛——重点是防止发灰显脏',
      );
    }

    // ⑤ 其余：中段亮度 + 有颜色 → 虎斑/橘/三花（基准参数即可）。
    return out(
      coat: PetCoat.tabby,
      margin: math.min(math.min(marginGrey, marginMid), -marginMulti),
      reason: '主体颜色饱满，判为虎斑/橘/三花——按基准参数处理',
    );
  }

  /// 置信度：离判定边界越远越可信，夹在 0.30~0.95。
  ///
  /// 不返回 1.0：再确定也只是统计推断，界面仍应允许用户改。
  static double _confidenceFromMargin(double margin) {
    final v = 0.3 + margin.clamp(0.0, 1.0) * 0.65;
    return double.parse(v.clamp(0.30, 0.95).toStringAsFixed(2));
  }

  static PetCoatAnalysis _fallback(String why) => (
    coat: PetCoat.tabby,
    confidence: 0.0,
    meanLuma: 0.5,
    lightFraction: 0.0,
    darkFraction: 0.0,
    saturation: 0.0,
    reason: '$why，已回退到通用参数',
  );
}
