import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as image_format;

Future<Uint8List> prepareLocalPhoto(Uint8List bytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    // Read encoded headers only; never allocate full-size Dart pixels.
    // ImageDescriptor.width/height are unsupported by Flutter Web.
    final info = image_format.findDecoderForData(bytes)?.startDecode(bytes);
    if (info != null && info.width > 0 && info.height > 0) {
      final longSide = info.width > info.height ? info.width : info.height;
      final scale = longSide > 960 ? 960 / longSide : 1.0;
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: (info.width * scale).round().clamp(1, 960),
        targetHeight: (info.height * scale).round().clamp(1, 960),
        allowUpscaling: false,
      );
    } else {
      // Native-only formats (e.g. HEIC) use the engine thumbnail decoder.
      codec = await ui.instantiateImageCodecWithSize(
        await ui.ImmutableBuffer.fromUint8List(bytes),
        getTargetSize: (width, height) {
          final longSide = width > height ? width : height;
          final scale = longSide > 960 ? 960 / longSide : 1.0;
          return ui.TargetImageSize(
            width: (width * scale).round().clamp(1, 960),
            height: (height * scale).round().clamp(1, 960),
          );
        },
      );
    }
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('照片解码失败');
    return data.buffer.asUint8List();
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
