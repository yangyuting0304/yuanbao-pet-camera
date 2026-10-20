// 限尺寸解码 —— 把 JPEG 缩到目标长边再取像素，别在全尺寸上耗内存。
//
// ## 为什么需要它
//
// iOS 上 takePicture 输出的照片尺寸由 AVCaptureDevice 的 **activeFormat**
// 决定：camera_avfoundation 无论用哪个 ResolutionPreset 都只改 session
// preset（.veryHigh → .hd1920x1080），**不会**改 activeFormat，而它的
// configureMaxPhotoDimensions() 又会无条件把输出上限设成该 format 支持的
// 最大值 —— 于是 iPhone 14 Pro Max 上拍出来就是 **48MP**。
//
// 48MP 的代价是致命的：出片链路上有五个消费点，每个都曾用
// `img.decodeImage` 全尺寸解码，而纯 Dart 的 JPEG 解码会把 48MP 铺成
// **192MB 的 RGBA**：
//
//   峰值 = 192MB（解码） + 24MB（缩放副本） + 滤镜的 5 张平面…
//
// 连拍 3 张时这些会叠在一起，600MB 起跳 —— iOS 直接 jetsam 杀进程，
// 也就是用户说的「闪退」；而纯 Dart 解码 48MP 要 3~8 秒，
// 也就是用户说的「拍照模式很卡」。
//
// 这里用 Flutter 引擎的**原生解码器**（dart:ui 的 instantiateImageCodec），
// 它支持 targetWidth/targetHeight：iOS 走 ImageIO 的缩略解码路径，
// 直接产出目标尺寸的像素，内存与耗时只跟目标尺寸相关，和原图多大无关。
//
// ## 用法约束
//
// dart:ui 的解码 API **只能在 root isolate 调用**（不能跨 isolate 传递
// Codec/Image）。所以调用方要在主 isolate 解码，再把 RGBA 交给 isolate
// 去跑滤镜。
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// 解码 JPEG 并把长边限制到 [maxSide]，返回 RGBA 像素与尺寸。
///
/// [maxSide] ≤ 0 表示不限制（仍走原生解码器，只是全尺寸）。
/// 解码失败返回 null —— 调用方要能接受「拿不到像素」这种情况
/// （例如畸形 JPEG），而不是崩掉。
Future<({Uint8List rgba, int width, int height})?> decodeRgbaLimited(
  Uint8List jpeg,
  int maxSide,
) async {
  if (jpeg.isEmpty) return null;

  final size = _jpegSize(jpeg);
  if (size == null) return _decodeFallback(jpeg, maxSide);

  var targetWidth = size.$1;
  var targetHeight = size.$2;
  final longSide = math.max(targetWidth, targetHeight);
  if (maxSide > 0 && longSide > maxSide) {
    final scale = maxSide / longSide;
    targetWidth = math.max(1, (targetWidth * scale).round());
    targetHeight = math.max(1, (targetHeight * scale).round());
  }

  try {
    final codec = await ui.instantiateImageCodec(
      jpeg,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    // 尺寸必须在 dispose 之前取。
    final width = image.width;
    final height = image.height;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    // 及时释放：原生解码器持有的是系统内存，不 dispose 会一直占着
    // （这正是「拍几张之后内存越来越高」的常见来源）。
    image.dispose();
    codec.dispose();
    final rgba = data?.buffer.asUint8List();
    if (rgba == null) return null;
    return (rgba: rgba, width: width, height: height);
  } catch (_) {
    return _decodeFallback(jpeg, maxSide);
  }
}

/// 兜底：纯 Dart 解码 + 缩放。
///
/// 只在原生解码器不可用（个别 Web 环境）或抛异常时才会走到。
/// 慢且占内存，但至少能出结果。
({Uint8List rgba, int width, int height})? _decodeFallback(
  Uint8List jpeg,
  int maxSide,
) {
  try {
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) return null;
    final longSide = math.max(decoded.width, decoded.height);
    if (maxSide > 0 && longSide > maxSide) {
      final scale = maxSide / longSide;
      final resized = img.copyResize(
        decoded,
        width: math.max(1, (decoded.width * scale).round()),
        height: math.max(1, (decoded.height * scale).round()),
        interpolation: img.Interpolation.average,
      );
      return (
        rgba: resized.getBytes(order: img.ChannelOrder.rgba),
        width: resized.width,
        height: resized.height,
      );
    }
    return (
      rgba: decoded.getBytes(order: img.ChannelOrder.rgba),
      width: decoded.width,
      height: decoded.height,
    );
  } catch (_) {
    return null;
  }
}

/// 从 JPEG 文件头解析宽高（**只读 marker，不解像素**）。
///
/// 之所以自己扫而不依赖 image 包的 header API：这一层要被反复调用
/// （每张照片好几次），自己扫没有依赖风险，也省掉一次包内解码器的开销。
///
/// 返回 (width, height)；不是合法 JPEG 时返回 null。
(int, int)? _jpegSize(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    // 填充字节与无长度标记的字节
    if (marker == 0xFF || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      i += 2;
      continue;
    }
    final length = (b[i + 2] << 8) | b[i + 3];
    // SOF0..SOF15 里挑真正带帧尺寸的（排除 DHT/JPG/DAC）
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      final height = (b[i + 5] << 8) | b[i + 6];
      final width = (b[i + 7] << 8) | b[i + 8];
      if (width > 0 && height > 0) return (width, height);
      return null;
    }
    if (length < 2) return null;
    i += 2 + length;
  }
  return null;
}
