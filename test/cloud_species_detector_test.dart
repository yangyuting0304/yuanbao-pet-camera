// 云端物种识别客户端 —— 单元测试。
//
// 这里最要紧的一条是「**任何失败都必须返回 null**」：
// 识别是锦上添花，超时、断网、代理没配、返回格式变了……
// 全都不许影响用户进入相机拍照。所以异常路径测得比正常路径还多。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:pet_camera/data/cloud_species_detector.dart';
import 'package:pet_camera/data/pet_capture_profile.dart';

/// 造一张指定尺寸的 JPEG，用于验证"上传前缩图"。
Uint8List _jpeg(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, (x * 7) % 256, (y * 11) % 256, 128);
    }
  }
  return img.encodeJpg(image, quality: 90);
}

CloudSpeciesDetector _detectorWith(
  http.Client client, {
  String endpoint = 'https://example.test/api/pet-species',
}) => CloudSpeciesDetector(client: client, endpoint: endpoint);

/// 构造 JSON 响应。
///
/// **必须走 `Response.bytes` + `utf8.encode`**：`http.Response(String, ...)`
/// 在没有 charset 头时默认按 **latin1** 编码 body，中文会直接抛异常。
/// 真实服务器（Express `res.json`）发的是带 `charset=utf-8` 的 UTF-8 字节，
/// 客户端也用 `utf8.decode(bodyBytes)` 解析，所以测试必须还原成字节。
http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  group('可用性', () {
    test('未配置代理地址时不可用，且直接返回 null', () async {
      final d = CloudSpeciesDetector(
        client: MockClient((_) async => http.Response('{}', 200)),
        endpoint: '',
      );
      expect(d.isAvailable, isFalse);
      expect(
        await d.detect(_jpeg(32, 32), width: 32, height: 32),
        isNull,
      );
    });

    test('空图片不发起请求', () async {
      var called = false;
      final d = _detectorWith(
        MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      expect(await d.detect(Uint8List(0), width: 0, height: 0), isNull);
      expect(called, isFalse);
    });
  });

  group('正常路径', () {
    test('解析出物种与置信度', () async {
      final d = _detectorWith(
        MockClient(
          (_) async => _json({
            'species': 'cat',
            'confidence': 0.93,
            'matchedLabel': '猫',
            'provider': 'baidu',
            'available': true,
          }),
        ),
      );
      final guess = await d.detect(_jpeg(64, 64), width: 64, height: 64);
      expect(guess, isNotNull);
      expect(guess!.species, PetSpecies.cat);
      expect(guess.confidence, closeTo(0.93, 1e-9));
      expect(guess.matchedLabel, '猫');
    });

    test('四个物种编码都能映射', () async {
      for (final entry in {
        'cat': PetSpecies.cat,
        'dog': PetSpecies.dog,
        'rabbit': PetSpecies.rabbit,
        'chinchilla': PetSpecies.chinchilla,
      }.entries) {
        final d = _detectorWith(
          MockClient(
            (_) async => _json({'species': entry.key, 'confidence': 0.8}),
          ),
        );
        final guess = await d.detect(_jpeg(32, 32), width: 32, height: 32);
        expect(guess!.species, entry.value);
      }
    });

    test('服务端直接回中文标签时也能识别（换供应商不至于挂掉）', () async {
      final d = _detectorWith(
        MockClient(
          (_) async => _json({'species': '龙猫', 'confidence': 0.9}),
        ),
      );
      final guess = await d.detect(_jpeg(32, 32), width: 32, height: 32);
      expect(guess!.species, PetSpecies.chinchilla);
    });

    test('置信度被夹到 0..1', () async {
      final d = _detectorWith(
        MockClient(
          (_) async => _json({'species': 'dog', 'confidence': 3.5}),
        ),
      );
      final guess = await d.detect(_jpeg(32, 32), width: 32, height: 32);
      expect(guess!.confidence, 1.0);
    });

    test('缺置信度时按 0 处理，不抛异常', () async {
      final d = _detectorWith(
        MockClient((_) async => _json({'species': 'dog'})),
      );
      final guess = await d.detect(_jpeg(32, 32), width: 32, height: 32);
      expect(guess!.confidence, 0.0);
    });
  });

  group('失败路径：一律返回 null，绝不抛异常', () {
    test('available:false（服务端未配置供应商）→ null', () async {
      final d = _detectorWith(
        MockClient(
          (_) async => _json({
            'species': null,
            'confidence': 0,
            'available': false,
            'provider': 'off',
          }),
        ),
      );
      expect(await d.detect(_jpeg(32, 32), width: 32, height: 32), isNull);
    });

    test('species 为 null → null', () async {
      final d = _detectorWith(
        MockClient(
          (_) async => _json({
            'species': null,
            'confidence': 0,
            'available': true,
          }),
        ),
      );
      expect(await d.detect(_jpeg(32, 32), width: 32, height: 32), isNull);
    });

    test('未知物种编码 → null（不硬猜）', () async {
      final d = _detectorWith(
        MockClient((_) async => _json({'species': 'dragon'})),
      );
      expect(await d.detect(_jpeg(32, 32), width: 32, height: 32), isNull);
    });

    test('非 200 → null', () async {
      final d = _detectorWith(
        MockClient((_) async => http.Response('server error', 500)),
      );
      expect(await d.detect(_jpeg(32, 32), width: 32, height: 32), isNull);
    });

    test('返回不是 JSON → null', () async {
      final d = _detectorWith(
        MockClient((_) async => http.Response('<html>502</html>', 200)),
      );
      expect(await d.detect(_jpeg(32, 32), width: 32, height: 32), isNull);
    });

    test('返回 JSON 但不是对象 → null', () async {
      final d = _detectorWith(
        MockClient((_) async => http.Response('[1,2,3]', 200)),
      );
      expect(await d.detect(_jpeg(32, 32), width: 32, height: 32), isNull);
    });

    test('网络异常 → null', () async {
      final d = _detectorWith(
        MockClient((_) async => throw const SocketExceptionLike()),
      );
      expect(await d.detect(_jpeg(32, 32), width: 32, height: 32), isNull);
    });

    test('超时 → null', () async {
      final d = CloudSpeciesDetector(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return http.Response('{}', 200);
        }),
        endpoint: 'https://example.test/api/pet-species',
        timeout: const Duration(milliseconds: 30),
      );
      expect(await d.detect(_jpeg(32, 32), width: 32, height: 32), isNull);
    });

    test('图片解不开也能安全走完（缩图失败退回原图）', () async {
      var received = '';
      final d = _detectorWith(
        MockClient((req) async {
          received = req.body;
          return _json({'species': 'cat'});
        }),
      );
      // 一段不是图片的字节
      final junk = Uint8List.fromList(List.generate(64, (i) => i));
      final guess = await d.detect(junk, width: 8, height: 8);
      // 缩图失败退回原图，请求照发，识别照常
      expect(received, isNotEmpty);
      expect(guess!.species, PetSpecies.cat);
    });
  });

  group('上传前缩图', () {
    test('大图被显著缩小后再上传（否则 base64 会超供应商上限）', () async {
      String? posted;
      final d = _detectorWith(
        MockClient((req) async {
          posted = req.body;
          return _json({'species': 'cat'});
        }),
      );
      final big = _jpeg(1200, 1200);
      await d.detect(big, width: 1200, height: 1200);

      final body = jsonDecode(posted!) as Map<String, dynamic>;
      final uploaded = base64Decode(body['imageBase64'] as String);
      expect(
        uploaded.length,
        lessThan(big.length),
        reason: '上传的应该比原图小得多',
      );
      // 缩到长边 640
      final decoded = img.decodeImage(uploaded);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(640));
      expect(decoded.height, lessThanOrEqualTo(640));
    });

    test('小图不会被放大', () async {
      String? posted;
      final d = _detectorWith(
        MockClient((req) async {
          posted = req.body;
          return _json({'species': 'cat'});
        }),
      );
      await d.detect(_jpeg(200, 150), width: 200, height: 150);
      final body = jsonDecode(posted!) as Map<String, dynamic>;
      final decoded = img.decodeImage(
        base64Decode(body['imageBase64'] as String),
      );
      expect(decoded!.width, 200);
      expect(decoded.height, 150);
    });
  });
}

/// 用来模拟网络异常（避免直接依赖 dart:io 的 SocketException）。
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
  @override
  String toString() => 'SocketExceptionLike: 模拟网络不可用';
}
