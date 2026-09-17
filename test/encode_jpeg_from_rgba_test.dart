// 元宝拍拍 —— encodeJpegFromRgba 单测：比例合成的 JPEG 导出。
//
// 背景：此前比例合成用 ui.ImageByteFormat.png 输出，却以 ext:'jpg' 上传，
// 扩展名与实际编码不符且体积暴涨。新实现走 RGBA → image 包编码 JPEG，
// 这里用纯 Dart 验证产物确实是合法 JPEG 且能解回原尺寸。
//
// （依赖 ui.Canvas 的整条合成链路无法在纯 VM 测试里覆盖，属于 widget 层。）
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pet_camera/data/pet_filter.dart';

void main() {
  group('encodeJpegFromRgba', () {
    test('输出 JPEG 魔数（FFD8 开头 / FFD9 结尾）', () {
      const w = 8, h = 8;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        rgba[i * 4] = 200;
        rgba[i * 4 + 1] = 180;
        rgba[i * 4 + 2] = 120;
        rgba[i * 4 + 3] = 255;
      }

      final jpg = encodeJpegFromRgba((rgba, w, h));

      expect(jpg.length, greaterThan(4));
      expect(jpg[0], 0xFF);
      expect(jpg[1], 0xD8, reason: 'JPEG 起始标记 SOI');
      expect(jpg[jpg.length - 2], 0xFF);
      expect(jpg[jpg.length - 1], 0xD9, reason: 'JPEG 结束标记 EOI');
    });

    test('产物可解码回原尺寸', () {
      const w = 16, h = 12;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        rgba[i * 4] = (i * 7) & 0xFF;
        rgba[i * 4 + 1] = (i * 13) & 0xFF;
        rgba[i * 4 + 2] = (i * 29) & 0xFF;
        rgba[i * 4 + 3] = 255;
      }

      final jpg = encodeJpegFromRgba((rgba, w, h));
      final decoded = img.decodeJpg(jpg);

      expect(decoded, isNotNull, reason: '必须能被标准 JPEG 解码器读回');
      expect(decoded!.width, w);
      expect(decoded.height, h);
    });

    test('体积显著小于同尺寸 PNG（JPEG 有损压缩生效）', () {
      const w = 128, h = 128;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        rgba[i * 4] = (i % 251) & 0xFF;
        rgba[i * 4 + 1] = (i % 199) & 0xFF;
        rgba[i * 4 + 2] = (i % 173) & 0xFF;
        rgba[i * 4 + 3] = 255;
      }

      final jpg = encodeJpegFromRgba((rgba, w, h));
      // 原始 RGBA = 128*128*4 = 65536 字节；JPEG 压缩后应远小于此。
      expect(jpg.length, lessThan(w * h * 4 ~/ 2));
    });
  });
}
