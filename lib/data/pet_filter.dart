/// 宠物滤镜 —— 把 [PetCaptureProfile] 算出的后处理参数真正作用到照片上。
///
/// 分成两层，是有意为之：
///
///  - [PetFilterKernel]：**纯像素运算**，只碰 RGBA8 缓冲区，不依赖 Flutter 引擎。
///    滤镜是本产品最核心的差异点（毛色保护），必须能在普通单测里用合成像素验证。
///  - [PetFilter]：编解码层，负责 JPEG 解 → 内核 → JPEG 编。
///
/// 设计原则（来自调研）：
///  - 色温**只偏暖不偏冷**（偏冷会让猫狗毛色发灰）
///  - 用 clarity（微对比）而非锐度——锐度拉满会让毛发变糙、出现伪轮廓、显脏
///  - 降噪要**按局部高频门控**，只压平坦区域的噪点，不把绒毛抹平
///  - 网页端没有硬件曝光补偿，这里用数字增益兜底，白毛照样提亮、黑毛照样压暗
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'pet_capture_profile.dart';

/// 宠物滤镜的纯像素内核。
class PetFilterKernel {
  PetFilterKernel._();

  /// 高光滚降的膝盖位置：0.70 以上开始往下压，保住毛发高光层次。
  static const double _rolloffKnee = 0.70;

  /// 微对比强度系数。把 profile 里的 `clarity`（0.12~0.28）映射成
  /// unsharp mask 的合理 amount（约 0.5~1.1）——宠物毛发要的是"根根分明"，
  /// 不是"刀锋般锐利"，所以上限刻意压得低。
  static const double _clarityScale = 4.0;

  /// 毛发质感（texture）的两个频带半径（像素，**与图片尺寸无关**）。
  ///
  /// 频带划分与既有参数互补，三层各管一段：
  ///   - clarity：大半径（短边 1.2%）→ 低频"局部对比"，管立体感
  ///   - texture：半径 [_textureMidRadius] → 中频，管"每一根毛分开"
  ///   - 遮罩锐化：半径 [_textureSharpRadius] → 高频，管毛尖的"脆"
  /// 固定小半径是因为毛发的物理尺度不随成片分辨率变化。
  static const int _textureMidRadius = 3;
  static const int _textureSharpRadius = 1;

  /// 遮罩锐化相对中频增强的比例（Lightroom 宠物配方的常见配比）。
  static const double _sharpRatio = 0.6;

  /// 门控阈值（8bit 亮度幅度）：幅度在此区间内平滑过渡。
  ///
  /// 与降噪 coring 的 cut 同一量级、方向相反——降噪削掉小振幅高频，
  /// texture 只放大超过阈值的振幅。中间带不动，于是噪点不放大、
  /// 毛发边缘被增强，这正是"边缘遮罩（masking）"的含义。
  static const double _midGateLo = 6.0, _midGateHi = 22.0;
  static const double _sharpGateLo = 8.0, _sharpGateHi = 26.0;

  /// 眼睛增强：区域内暗部提亮上限（/255）与眼神光锐化系数。
  /// 提亮走 (1−l)^1.5 曲线：瞳孔提得最多，白毛高光几乎不动。
  static const double _eyeLiftMax = 14.0;
  static const double _eyeSharp = 0.35;

  /// 泪痕检测门控：偏红程度（r−b）在 12→36 之间平滑启动；
  /// 暗度门控（l<140 起步）把亮橙/棕毛发挡在外面，防止橘猫棕犬被误"去红"。
  static const double _tearRedLo = 12.0, _tearRedHi = 36.0;

  /// smoothstep 门控：幅度 ≤lo 不增强、≥hi 全额增强，之间平滑过渡。
  /// 平滑而非硬切换，避免门控边界出现振铃。
  static double _gate(double amplitude, double lo, double hi) {
    if (amplitude <= lo) return 0.0;
    if (amplitude >= hi) return 1.0;
    final t = (amplitude - lo) / (hi - lo);
    return t * t * (3.0 - 2.0 * t);
  }

  /// 椭圆区域权重：内部 70% 平台期全额，边缘 0.7→1.0 平滑衰减到 0。
  /// d 是相对椭圆边界的归一化距离（中心 0、边界 1）。
  static double _zoneWeight(double dx, double dy, double rx, double ry) {
    final d = math.sqrt((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry));
    if (d >= 1.0) return 0.0;
    if (d <= 0.7) return 1.0;
    final t = (1.0 - d) / 0.3;
    return t * t * (3.0 - 2.0 * t);
  }

  /// 构建单通道的 256 项色调曲线（0..1）。
  ///
  /// 顺序：**曝光增益 → 色温通道增益 → 阴影提亮 → 高光滚降**。
  /// 公开出来是为了让测试能直接校验曲线形状，而不是只测最终像素。
  static List<double> buildChannelLut({
    required double exposureGain,
    required double channelGain,
    required double shadowLift,
    required double highlightRolloff,
  }) {
    // gamma < 1 会抬起中低调，即"阴影提亮"。
    final gamma = 1.0 / (1.0 + shadowLift.clamp(0.0, 1.0) * 0.8);
    final roll = highlightRolloff.clamp(0.0, 1.0);
    final lut = List<double>.filled(256, 0.0);
    for (var i = 0; i < 256; i++) {
      var v = (i / 255.0) * exposureGain * channelGain;
      v = v.clamp(0.0, 1.0);
      if (gamma != 1.0) {
        v = math.pow(v, gamma).toDouble();
      }
      // 二次项 t² 保证在膝盖处斜率连续，不会出现肉眼可见的硬折点。
      if (roll > 0 && v > _rolloffKnee) {
        final t = (v - _rolloffKnee) / (1 - _rolloffKnee);
        v -= roll * t * t * (1 - _rolloffKnee) * 0.55;
      }
      lut[i] = v.clamp(0.0, 1.0);
    }
    return lut;
  }

  /// 把 0..1 的曲线量化成 0..255 的查表，逐像素查表比逐像素算幂快得多。
  static Uint8List _quantize(List<double> curve) {
    final out = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      out[i] = (curve[i] * 255).round().clamp(0, 255);
    }
    return out;
  }

  /// 对 RGBA8 缓冲区套用滤镜，返回新的缓冲区。
  ///
  /// [src] 长度必须是 `width * height * 4`，行优先。
  static Uint8List apply(
    Uint8List src, {
    required int width,
    required int height,
    double exposure = 0,
    double tempShift = 0,
    double shadowLift = 0,
    double highlightRolloff = 0,
    double clarity = 0,
    double noiseReduction = 0,
    double vignette = 0,
    double saturation = 1.0,
    double vibrance = 0,
    double grain = 0,
    double texture = 0,
    double eyeEnhance = 0,
    double tearStain = 0,
  }) {
    final n = width * height;
    if (src.length < n * 4) {
      throw ArgumentError(
        'RGBA 缓冲区长度 ${src.length} 小于 ${width}x$height 所需 ${n * 4}',
      );
    }
    final out = Uint8List(n * 4);

    // 曝光：EV → 线性倍数。夹到 ±3EV，避免用户/参数异常时把画面拉爆。
    final ev = exposure.clamp(-3.0, 3.0);
    final exposureGain = ev == 0 ? 1.0 : math.pow(2.0, ev).toDouble();

    // 色温：暖调抬红压蓝，且红的增益**略小于**蓝的衰减，
    // 保证整体亮度不至于明显漂移。
    final rGain = 1.0 + tempShift * 0.00018;
    final bGain = 1.0 - tempShift * 0.00022;

    final lutR = _quantize(
      buildChannelLut(
        exposureGain: exposureGain,
        channelGain: rGain,
        shadowLift: shadowLift,
        highlightRolloff: highlightRolloff,
      ),
    );
    final lutG = _quantize(
      buildChannelLut(
        exposureGain: exposureGain,
        channelGain: 1.0,
        shadowLift: shadowLift,
        highlightRolloff: highlightRolloff,
      ),
    );
    final lutB = _quantize(
      buildChannelLut(
        exposureGain: exposureGain,
        channelGain: bGain,
        shadowLift: shadowLift,
        highlightRolloff: highlightRolloff,
      ),
    );

    // 微对比与降噪都作用在"亮度的高频分量"上，共用一个模糊结果。
    // texture（毛发质感）也需要亮度低频参考（小半径模糊差），三者共用 luma。
    // 没有任何一项需求时整段跳过，省一次 O(n) 遍历。
    final useTexture = texture > 0.001;
    final useEye = eyeEnhance > 0.001;
    final useTear = tearStain > 0.001;
    final needLuma = clarity.abs() > 0.001 ||
        noiseReduction > 0.001 ||
        useTexture ||
        useEye;
    final needBlur = clarity.abs() > 0.001 || noiseReduction > 0.001;
    Float32List? luma;
    if (needLuma) {
      luma = Float32List(n);
      for (var i = 0; i < n; i++) {
        final o = i * 4;
        // 用查表**之后**的亮度，保证清晰度作用在成片观感上。
        luma[i] =
            0.2126 * lutR[src[o]] +
            0.7152 * lutG[src[o + 1]] +
            0.0722 * lutB[src[o + 2]];
      }
    }
    Float32List? blurred;
    if (needBlur) {
      // 半径取短边的 1.2%（至少 2px）：这是"局部对比"而不是"整体对比"。
      final radius = math.max(2, (math.min(width, height) * 0.012).round());
      blurred = _boxBlur(luma!, width, height, radius);
    }
    // texture 的两个频带参考（半径固定、与尺寸无关，见常量注释）；
    // 眼睛增强的眼神光锐化复用高频参考 blurSharp。
    Float32List? blurSharp;
    Float32List? blurMid;
    if (useTexture || useEye) {
      blurSharp = _boxBlur(luma!, width, height, _textureSharpRadius);
    }
    if (useTexture) {
      blurMid = _boxBlur(luma!, width, height, _textureMidRadius);
    }
    final textureMid = texture;
    final textureSharp = texture * _sharpRatio;

    // 眼区 / 泪痕区椭圆几何（比例坐标，与分辨率无关）。
    // 位置是廉价近似的核心假设：正脸特写构图下双眼约在 0.40h，
    // 泪痕在其正下方约 0.50h；宠物不在该区域时权重自然为 0，不误伤。
    final eyeCx = width * 0.50, eyeCy = height * 0.40;
    final eyeRx = width * 0.22, eyeRy = height * 0.10;
    final tearCx = width * 0.50, tearCy = height * 0.50;
    final tearRx = width * 0.20, tearRy = height * 0.10;
    Float32List? eyeLiftLut;
    if (useEye) {
      eyeLiftLut = Float32List(256);
      for (var i = 0; i < 256; i++) {
        // 只提暗部：瞳孔/虹膜提得最多，眼神光与白毛高光几乎不动。
        eyeLiftLut[i] =
            _eyeLiftMax * math.pow(1.0 - i / 255.0, 1.5).toDouble();
      }
    }

    final cx = (width - 1) / 2.0;
    final cy = (height - 1) / 2.0;
    final invMaxDist = 1.0 / math.sqrt(cx * cx + cy * cy);
    final clarityWeight = clarity * _clarityScale;
    final sat = saturation;
    final vib = vibrance;
    final useVibrance = vib.abs() > 0.001;
    final useGrain = grain > 0.001;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final o = i * 4;

        var r = lutR[src[o]].toDouble();
        var g = lutG[src[o + 1]].toDouble();
        var b = lutB[src[o + 2]].toDouble();

        // 饱和度：围绕亮度缩放，1.0 为不变。
        // 只调浓度、不动色相，避免把品种固有色"染色"。
        if (sat != 1.0) {
          final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          r = l + (r - l) * sat;
          g = l + (g - l) * sat;
          b = l + (b - l) * sat;
        }

        // 自然饱和度（vibrance）：只提"还不够鲜艳"的像素，已经饱和的几乎不动。
        //
        // 它和「饱和度」是两个不同的滑杆——社区配方（VSCO / 醒图等）普遍分开给，
        // 原因就在这里：直接拉饱和度会把品种固有色"染色"，
        // 而 vibrance 对已经饱和的毛发几乎无影响，更安全。
        if (useVibrance) {
          final maxC = math.max(r, math.max(g, b));
          final minC = math.min(r, math.min(g, b));
          final curSat = maxC <= 0 ? 0.0 : (maxC - minC) / maxC;
          final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final k = 1.0 + vib * (1.0 - curSat);
          r = l + (r - l) * k;
          g = l + (g - l) * k;
          b = l + (b - l) * k;
        }

        // 微对比（+）与降噪（−）都作用在亮度高频分量上，方向相反。
        if (needLuma) {
          final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          var delta = 0.0;
          if (needBlur) {
            final hf = l - blurred![i];
            // 降噪用「软阈值削波（coring）」而**不是**整体模糊：
            // 只削掉小振幅的高频（=噪点），大振幅的（=毛发边缘）原样保留。
            //
            // 早先版本按"幅度大小做门控"，结果噪点和边缘幅度都很高，
            // 门控把降噪整个关掉了（测试抓到的）。正确的区分维度是**振幅绝对值**：
            // 传感器的噪点幅度小，绒毛边缘的落差大。
            final cut = 6.0 + noiseReduction * 12.0;
            final coring = hf.abs() <= cut ? hf : cut * hf.sign;
            delta += clarityWeight * hf - noiseReduction * coring;
          }
          // 毛发质感：中频带通增强 + 边缘遮罩锐化。
          // 与降噪的门控同一维度（振幅绝对值）但方向相反：
          // 只放大超过门控阈值的高频（=毛发边缘），噪点幅度小被挡在外面，
          // 所以"质感增强"不会把背景虚化区的噪点一起放大。
          if (useTexture) {
            final hfS = l - blurSharp![i];
            final hfM = l - blurMid![i];
            delta += textureMid * hfM * _gate(hfM.abs(), _midGateLo, _midGateHi);
            delta +=
                textureSharp *
                hfS *
                _gate(hfS.abs(), _sharpGateLo, _sharpGateHi);
          }
          r += delta;
          g += delta;
          b += delta;
        }

        // 眼睛增强 / 泪痕淡化：「画面中上部椭圆区」加权 —— 不依赖眼睛检测
        // 模型（模型未接入）。最坏情况只是轻微提亮该区域的毛发，
        // 不会产生可感知亮斑；配合特征门控把误伤面压到最小。
        if (useEye || useTear) {
          // 这里的 l 基于叠加 clarity/texture 增量后的当前值，
          // 保证提亮与泪痕检测作用在成片观感上（与 needLuma 块内的 l 同语义）。
          final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          var eyeW = 0.0;
          if (useEye) {
            eyeW = _zoneWeight(x - eyeCx, y - eyeCy, eyeRx, eyeRy);
          }
          var tearW = 0.0;
          if (useTear) {
            tearW = _zoneWeight(x - tearCx, y - tearCy, tearRx, tearRy);
          }
          if (eyeW > 0) {
            final lift =
                eyeEnhance * eyeW * eyeLiftLut![l.round().clamp(0, 255)];
            r += lift;
            g += lift;
            b += lift;
            // 眼神光：区域内叠加一层门控锐化（复用高频参考与阈值），
            // 让瞳孔边缘和 catchlight 的对比更"脆"。
            if (blurSharp != null) {
              final hfS = l - blurSharp[i];
              final s =
                  eyeEnhance * eyeW * _eyeSharp * hfS *
                  _gate(hfS.abs(), _sharpGateLo, _sharpGateHi);
              r += s;
              g += s;
              b += s;
            }
          }
          if (tearW > 0) {
            // 泪痕特征 = 偏红（r−b 大）+ 偏暗。暗度门控把亮橙毛挡在外面，
            // 防止橘猫 / 棕犬的脸部毛被误"去红"。
            final m =
                tearW *
                _gate(r - b, _tearRedLo, _tearRedHi) *
                _gate(140.0 - l, 0.0, 50.0);
            if (m > 0) {
              final k = tearStain * m;
              // 去红：把 r 拉向 g；补蓝：把 b 抬向 g —— 棕红向中性收敛。
              r -= (r - g) * k * 0.40;
              b += (g - b) * k * 0.30;
              // 提亮暗部：泪痕比周围毛暗，提亮后与毛发过渡更自然。
              final lift = k * 12.0 * (1.0 - l / 255.0);
              r += lift;
              g += lift;
              b += lift;
            }
          }
        }

        // 暗角：把视线收拢到画面中心（宠物眼睛通常在中部）。
        if (vignette > 0) {
          final dx = x - cx;
          final dy = y - cy;
          final d = math.sqrt(dx * dx + dy * dy) * invMaxDist;
          final k = 1.0 - vignette * d * d;
          r *= k;
          g *= k;
          b *= k;
        }

        // 胶片颗粒。放在最后一步（降噪之后），否则会被降噪削掉。
        //
        // 它不只是氛围道具：弱光下高感噪点很难完全去掉，
        // 铺一层颗粒能把"脏噪点"变成"有意的质感"，比一味磨平更耐看。
        if (useGrain) {
          final gn = _grainNoise(x, y) * grain * 26.0;
          r += gn;
          g += gn;
          b += gn;
        }

        out[o] = r.clamp(0.0, 255.0).round();
        out[o + 1] = g.clamp(0.0, 255.0).round();
        out[o + 2] = b.clamp(0.0, 255.0).round();
        out[o + 3] = src[o + 3]; // 保留 alpha
      }
    }
    return out;
  }

  /// 确定性的颗粒噪点，返回 -1..1。
  ///
  /// 刻意只用 16 位种子 + 一次小系数乘法：Dart VM 是 64 位整数，而 Web 端是
  /// 53 位 double + 32 位位运算，用大数相乘会让两个平台产生不同的颗粒纹理。
  /// 控制在这个范围内，两端结果完全一致，单元测试也才能断言确定的像素值。
  static double _grainNoise(int x, int y) {
    var h = (x * 31 + y * 17) & 0xFFFF;
    h = (h * 1103515245 + 12345) & 0x7FFFFFFF;
    h = ((h >> 11) ^ (h >> 19)) & 0x3FF;
    return h / 511.5 - 1.0;
  }

  /// 可分离盒式模糊（O(n)，与半径无关）。用于微对比与降噪的高频参考。
  static Float32List _boxBlur(
    Float32List src,
    int width,
    int height,
    int radius,
  ) {
    final r = radius.clamp(1, math.min(width, height) ~/ 2);
    final window = 2 * r + 1;
    final tmp = Float32List(src.length);
    final out = Float32List(src.length);

    // 横向
    for (var y = 0; y < height; y++) {
      final row = y * width;
      var sum = 0.0;
      for (var k = -r; k <= r; k++) {
        sum += src[row + k.clamp(0, width - 1)];
      }
      for (var x = 0; x < width; x++) {
        tmp[row + x] = sum / window;
        sum += src[row + (x + r + 1).clamp(0, width - 1)];
        sum -= src[row + (x - r).clamp(0, width - 1)];
      }
    }

    // 纵向
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      for (var k = -r; k <= r; k++) {
        sum += tmp[k.clamp(0, height - 1) * width + x];
      }
      for (var y = 0; y < height; y++) {
        out[y * width + x] = sum / window;
        sum += tmp[(y + r + 1).clamp(0, height - 1) * width + x];
        sum -= tmp[(y - r).clamp(0, height - 1) * width + x];
      }
    }
    return out;
  }
}

/// 跨 isolate 传递的滤镜任务。
///
/// 刻意只用基本类型 + record：`compute` 需要参数可跨 isolate 传递，
/// 直接传 [PetCaptureProfile] 会因为不是可发送类型而在原生端抛异常。
typedef PetFilterRequest = ({
  Uint8List bytes,
  double exposure,
  double tempShift,
  double shadowLift,
  double highlightRolloff,
  double clarity,
  double noiseReduction,
  double vignette,
  double saturation,
  double vibrance,
  double grain,
  double texture,
  double eyeEnhance,
  double tearStain,
  int maxSide,
  int jpegQuality,
});

/// RGBA 像素 → JPEG 字节（供拍照页 Canvas 比例合成后的导出使用）。
///
/// `ui.Image.toByteData` 只提供 rawRgba / png 两种格式：png 无损，
/// 一张 12MP 成片会到十几 MB，且此前一直被误当作 `ext:'jpg'` 上传。
/// 这里用 image 包统一编回 JPEG（质量与滤镜出口一致），体积与扩展名才对得上。
/// 顶层函数 + record 参数：`compute` 需要，与 [runPetFilter] 同一套约定。
Uint8List encodeJpegFromRgba((Uint8List, int, int) args) {
  final (rgba, width, height) = args;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: PetFilter.defaultJpegQuality);
}

/// 滤镜的顶层执行入口，供 `compute` 调用。
///
/// Web 上 `compute` 会退化为同步执行，所以这里不依赖任何 isolate 特性。
Uint8List runPetFilter(PetFilterRequest req) {
  // 注意：`img.decodeImage` 遇到畸形数据会**抛异常**而不是返回 null
  // （实测会被 PSD 解码器的头部探测带崩）。必须自己兜住，
  // 否则一张损坏的照片就能让滤镜整段挂掉。
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(req.bytes);
  } catch (_) {
    return req.bytes;
  }
  // 解不开就原样返回：滤镜失败不该让用户丢掉这张照片。
  if (decoded == null) return req.bytes;

  var work = decoded;
  final longSide = math.max(decoded.width, decoded.height);
  if (req.maxSide > 0 && longSide > req.maxSide) {
    final scale = req.maxSide / longSide;
    work = img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  final rgba = work.getBytes(order: img.ChannelOrder.rgba);
  final filtered = PetFilterKernel.apply(
    rgba,
    width: work.width,
    height: work.height,
    exposure: req.exposure,
    tempShift: req.tempShift,
    shadowLift: req.shadowLift,
    highlightRolloff: req.highlightRolloff,
    clarity: req.clarity,
    noiseReduction: req.noiseReduction,
    vignette: req.vignette,
    saturation: req.saturation,
    vibrance: req.vibrance,
    grain: req.grain,
    texture: req.texture,
    eyeEnhance: req.eyeEnhance,
    tearStain: req.tearStain,
  );

  final outImage = img.Image.fromBytes(
    width: work.width,
    height: work.height,
    bytes: filtered.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(outImage, quality: req.jpegQuality);
}

/// 宠物滤镜的编解码层（对外入口）。
class PetFilter {
  PetFilter._();

  /// 输出长边的默认上限。
  ///
  /// 相机原图可能到 4000px+，纯 Dart 逐像素处理在网页端会明显卡顿；
  /// 超过这个尺寸先等比缩下来再处理。2400px 对手机分享/打印都够用。
  static const int defaultMaxSide = 2400;

  /// 默认导出画质。92 是"肉眼无明显损失、体积可控"的常用档。
  static const int defaultJpegQuality = 92;

  /// 由参数集构造跨 isolate 的任务。
  ///
  /// [exposureAlreadyApplied] 为 true 时跳过数字曝光补偿——原生端相机
  /// 已经通过硬件加过 EV，这里再加一次就会过曝。
  static PetFilterRequest buildRequest(
    Uint8List encoded,
    PetCaptureProfile profile, {
    bool exposureAlreadyApplied = false,
    int maxSide = defaultMaxSide,
    int jpegQuality = defaultJpegQuality,
  }) => (
    bytes: encoded,
    exposure: exposureAlreadyApplied ? 0 : profile.exposureCompensation,
    tempShift: profile.tempShift,
    shadowLift: profile.shadowLift,
    highlightRolloff: profile.highlightRolloff,
    clarity: profile.clarity,
    noiseReduction: profile.noiseReduction,
    vignette: profile.vignette,
    saturation: profile.saturation,
    vibrance: profile.vibrance,
    grain: profile.grain,
    // 毛发质感增强：bool 开关 → 固定强度。中频增强 + 遮罩锐化都在内核里
    // 由这一个值驱动（锐化按 _sharpRatio 派生）。
    texture: profile.furTextureBoost
        ? PetCaptureProfile.furTextureStrength
        : 0.0,
    eyeEnhance: profile.eyeEnhance ? PetCaptureProfile.eyeEnhanceStrength : 0.0,
    tearStain: profile.tearStainFix ? PetCaptureProfile.tearStainStrength : 0.0,
    maxSide: maxSide,
    jpegQuality: jpegQuality,
  );

  /// 同步套用滤镜（测试与简单场景用）。
  static Uint8List applyToEncoded(
    Uint8List encoded,
    PetCaptureProfile profile, {
    bool exposureAlreadyApplied = false,
    int maxSide = defaultMaxSide,
    int jpegQuality = defaultJpegQuality,
  }) => runPetFilter(
    buildRequest(
      encoded,
      profile,
      exposureAlreadyApplied: exposureAlreadyApplied,
      maxSide: maxSide,
      jpegQuality: jpegQuality,
    ),
  );
}
