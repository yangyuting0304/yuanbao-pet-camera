/// 云端物种识别（走自建代理，**Key 不在客户端**）。
///
/// ## 为什么是"云端"而不是端侧 ML Kit
///
/// 端侧 ML Kit 的体验更好（即时、离线、免流量），但有两个现实约束：
///  1. Web 端跑不了 —— 而 Web 正是当前唯一能演示/验证的环境
///  2. 其 Flutter 插件依赖 `dart:io`，直接 import 会让 Web 构建失败，
///     必须用条件导入隔离
///
/// 所以先上云端，把"自动识别"这条链路跑通、可验证；端侧实现作为
/// 后续的加速层接在同一个 [PetSpeciesDetector] 接口上即可，上层不用改。
///
/// ## 三条硬约束
///
///  1. **Key 不进客户端**：识别用的 Key 全部在服务端。
///     Flutter Web 产物里的字符串可以被直接解出来，Key 进包就等于公开。
///  2. **上传前必须缩图**：原图动辄几 MB，base64 后还要再涨约 1/3，
///     既慢又可能超过供应商的限制（百度动物识别要求 base64 ≤ 4MB）。
///     识别物种只需要一张小图。
///  3. **任何失败都返回 null**，绝不上抛：识别不成功只能降级为"用户手选"，
///     不能影响进入相机、更不能让取景界面崩掉。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'app_env.dart';
import 'pet_species_detector.dart';

class CloudSpeciesDetector implements PetSpeciesDetector {
  CloudSpeciesDetector({
    http.Client? client,
    String? endpoint,
    this.uploadMaxSide = 640,
    this.uploadQuality = 85,
    this.timeout = const Duration(seconds: 6),
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? AppEnv.petSpeciesProxyUrl;

  final http.Client _client;
  final String _endpoint;

  /// 上传前把长边缩到这个尺寸。识别物种不需要大图。
  final int uploadMaxSide;

  /// 上传用的 JPEG 质量。
  final int uploadQuality;

  /// 请求超时。识别是"锦上添花"，不能为了它把用户卡在取景界面等。
  final Duration timeout;

  @override
  bool get isAvailable => _endpoint.isNotEmpty;

  @override
  Future<PetSpeciesGuess?> detect(
    Uint8List image, {
    String? filePath,
    required int width,
    required int height,
  }) async {
    if (!isAvailable || image.isEmpty) return null;
    try {
      final payload = _shrinkForUpload(image);
      final resp = await _client
          .post(
            Uri.parse(_endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'imageBase64': base64Encode(payload)}),
          )
          .timeout(timeout);
      if (resp.statusCode != 200) {
        debugPrint('[物种识别] 代理返回 ${resp.statusCode}');
        return null;
      }
      return _parse(utf8.decode(resp.bodyBytes));
    } catch (e) {
      // 超时 / 断网 / 解析失败……一律视为"没识别出来"。
      debugPrint('[物种识别] 失败，降级为用户手选：$e');
      return null;
    }
  }

  /// 解析代理返回的 JSON。抽成独立方法，便于用离线样本做单测。
  static PetSpeciesGuess? _parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    // 服务端未配置识别能力：如实返回 null，由用户手选。
    if (decoded['available'] == false) return null;

    final rawSpecies = decoded['species'];
    if (rawSpecies is! String) return null;
    final species = PetLabelMapper.speciesOf(rawSpecies);
    if (species == null) return null;

    final rawConfidence = decoded['confidence'];
    final confidence = rawConfidence is num
        ? rawConfidence.toDouble().clamp(0.0, 1.0)
        : 0.0;

    final rawLabel = decoded['matchedLabel'];
    return (
      species: species,
      confidence: confidence,
      matchedLabel: rawLabel is String ? rawLabel : rawSpecies,
    );
  }

  /// 上传前缩图并转 JPEG。
  ///
  /// 缩图本身失败时退回原图——不能因为"省流量"没做成，就让识别整个失败。
  Uint8List _shrinkForUpload(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      var work = decoded;
      final longSide = math.max(decoded.width, decoded.height);
      if (longSide > uploadMaxSide) {
        final scale = uploadMaxSide / longSide;
        work = img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
          interpolation: img.Interpolation.average,
        );
      }
      return img.encodeJpg(work, quality: uploadQuality);
    } catch (_) {
      return bytes;
    }
  }
}
