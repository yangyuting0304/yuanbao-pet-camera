import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pet_camera/data/app_env.dart';

/// FireRed 图像编辑结果（毛孩 AI 创意编辑 / 换装 / 风格化）。
class FireRedResult {
  const FireRedResult({required this.imageBytes, this.demo = false});
  final Uint8List imageBytes;
  final bool demo; // 未接入代理时为真（回显源图）
}

/// FireRed 服务异常（UI 层据此展示错误信息）。
class FireRedException implements Exception {
  const FireRedException(this.message);
  final String message;
  @override
  String toString() => 'FireRedException: $message';
}

/// FireRed-Image-Edit（ModelScope）图像编辑服务。
///
/// 该模型**只接受公网 image_url**（不接受 base64），且 API Key 绝不能进前端，
/// 因此统一走 ECS 代理：前端只传 base64 源图 + prompt，代理负责上传 COS 拿 URL、
/// 调 ModelScope、轮询、返回结果图 base64。
///
/// 构建期注入代理地址：
///   flutter run --dart-define=FIERED_PROXY_URL=https://<你的域名>/api/v1/firered-edit
/// 该服务尚未部署，默认留空，未配置时进入「演示模式」回显源图，
/// 便于在 Web 端跑通完整交互流。
class FireRedService {
  // 服务端代理地址（编译期 --dart-define 注入，未注入时回落 [AppEnv] 默认值）。
  static const String _proxyUrl = AppEnv.fireredProxyUrl;

  /// 提交一次图像编辑（图生图）。
  Future<FireRedResult> edit({
    required Uint8List sourceBytes,
    required String prompt,
  }) async {
    if (_proxyUrl.isEmpty) {
      // 演示模式：未配置代理，模拟耗时后回显源图。
      await Future<void>.delayed(const Duration(seconds: 1));
      return FireRedResult(imageBytes: sourceBytes, demo: true);
    }
    final resp = await http
        .post(
          Uri.parse(_proxyUrl),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{
            'imageBase64': base64Encode(sourceBytes),
            'prompt': prompt,
          }),
        )
        .timeout(const Duration(seconds: 180));
    if (resp.statusCode != 200) {
      throw FireRedException('代理返回错误：${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['error'] != null) {
      throw FireRedException('编辑失败：${data['error']}');
    }
    final base64 = data['imageBase64'] as String;
    return FireRedResult(imageBytes: base64Decode(base64));
  }
}

/// Riverpod Provider：FireRed 服务单例。
final fireRedServiceProvider = Provider<FireRedService>(
  (ref) => FireRedService(),
);

/// 毛孩 AI 创意编辑快捷 prompt 清单（用户一键选用，也可自定义）。
const List<(String label, String prompt)> kFireRedPresets = <(String, String)>[
  (
    '戴蝴蝶结',
    'Add a cute pink bow on the cat\'s head, keep the same pose and background, keep the cat looking natural.',
  ),
  (
    '变成蓝猫',
    'Turn the cat into a blue-furred cat, keep the same pose, expression and background.',
  ),
  (
    '星空背景',
    'Place the cat on a starry night sky background with glowing stars and a dreamy galaxy, keep the cat unchanged.',
  ),
  (
    '卡通动漫风',
    'Restyle the cat photo into a cute anime / manga style with clean cel-shading and big sparkling eyes.',
  ),
  (
    '戴墨镜',
    'Put cool black sunglasses on the cat, keep the same pose and background.',
  ),
  (
    '生日帽',
    'Put a colorful party birthday hat on the cat\'s head, add a festive mood, keep the cat unchanged.',
  ),
];
