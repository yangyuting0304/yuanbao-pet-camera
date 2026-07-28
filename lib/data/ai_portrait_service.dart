import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_flutter/lucide_flutter.dart';

/// AI 写真风格（设计风格网格）。icon 为 Lucide 图标，UI 层直接渲染。
class PortraitStyle {
  const PortraitStyle({
    required this.id,
    required this.name,
    required this.icon,
    required this.prompt,
  });
  final String id;
  final String name;
  final IconData icon;
  final String prompt;
}

/// 预置风格清单（后续可在后台扩展，前端按 id 取用）。
const List<PortraitStyle> kPortraitStyles = <PortraitStyle>[
  PortraitStyle(
    id: 'oil',
    name: '油画',
    icon: LucideIcons.palette,
    prompt: '一幅油画风格的宠物猫肖像，细腻笔触，暖色调，古典光影，背景虚化',
  ),
  PortraitStyle(
    id: 'watercolor',
    name: '水彩',
    icon: LucideIcons.brush,
    prompt: '水彩画风格的宠物猫，清新通透，留白意境，淡彩晕染',
  ),
  PortraitStyle(
    id: 'anime',
    name: '动漫',
    icon: LucideIcons.sparkles,
    prompt: '动漫二次元风格的宠物猫，大眼睛，可爱，赛璐璐上色',
  ),
  PortraitStyle(
    id: 'vintage',
    name: '复古胶片',
    icon: LucideIcons.camera,
    prompt: '复古胶片风格的宠物猫照片，颗粒感，暖黄褪色，柯达色调',
  ),
  PortraitStyle(
    id: 'royal',
    name: '国风',
    icon: LucideIcons.crown,
    prompt: '国风工笔画风格的宠物猫，典雅，牡丹与祥云背景，绢本设色',
  ),
  PortraitStyle(
    id: 'festive',
    name: '节日',
    icon: LucideIcons.gift,
    prompt: '节日主题的宠物猫，圣诞暖灯与礼物装饰，温馨欢乐氛围',
  ),
];

/// AI 写真生成请求。
class PortraitRequest {
  const PortraitRequest({required this.sourceBytes, required this.styleId});
  final Uint8List sourceBytes;
  final String styleId;
}

/// AI 写真生成结果。
class PortraitResult {
  const PortraitResult({
    required this.imageBytes,
    required this.styleId,
    this.imageUrl,
    this.demo = false,
  });
  final Uint8List imageBytes;
  final String styleId;
  final String? imageUrl;
  final bool demo; // 演示模式（未接入真实 API 时为真）
}

/// AI 写真服务异常（UI 层据此展示错误信息）。
class AiPortraitException implements Exception {
  const AiPortraitException(this.message);
  final String message;
  @override
  String toString() => 'AiPortraitException: $message';
}

/// 云端写真服务骨架（通义万相 DashScope 异步任务 API）。
///
/// 真实接入只需在构建期注入 API Key：
///   flutter run --dart-define=DASHSCOPE_API_KEY=你的Key
/// 未配置 Key 时自动进入「演示模式」回显源图，便于在 Web 端跑通完整交互流。
///
/// 注：当前骨架以文生图（wanx2.1-t2i）建模风格；
/// 若要「照片→写真」图生图，需先把源图上传到 OSS 取得可访问 URL，
/// 再在 input.image_url 中引用（DashScope 不支持直接传图字节）。
class AiPortraitService {
  // 安全读取：编译期 --dart-define 注入，禁止硬编码到源码。
  static const String _apiKey =
      String.fromEnvironment('DASHSCOPE_API_KEY', defaultValue: '');

  static const String _endpoint =
      'https://dashscope.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis';

  /// 生成宠物 AI 写真。
  Future<PortraitResult> generatePortrait(PortraitRequest req) async {
    if (_apiKey.isEmpty) {
      // 演示模式：未配置 API Key，模拟耗时后回显源图。
      await Future<void>.delayed(const Duration(seconds: 2));
      return PortraitResult(
        imageBytes: req.sourceBytes,
        styleId: req.styleId,
        demo: true,
      );
    }
    final style = kPortraitStyles.firstWhere(
      (s) => s.id == req.styleId,
      orElse: () => kPortraitStyles.first,
    );
    final taskId = await _submitTask(style);
    final url = await _pollTask(taskId);
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw const AiPortraitException('下载生成结果失败');
    }
    return PortraitResult(
      imageBytes: resp.bodyBytes,
      imageUrl: url,
      styleId: req.styleId,
    );
  }

  /// 提交异步生成任务，返回 task_id。
  Future<String> _submitTask(PortraitStyle style) async {
    final resp = await http.post(
      Uri.parse(_endpoint),
      headers: <String, String>{
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'X-DashScope-Async': 'enable',
      },
      body: jsonEncode(<String, Object>{
        'model': 'wanx2.1-t2i-image-synthesis',
        'input': <String, String>{'prompt': style.prompt},
        'parameters': <String, Object>{
          'size': '1024*1024',
          'n': 1,
        },
      }),
    );
    if (resp.statusCode != 200) {
      throw AiPortraitException('提交任务失败：${resp.statusCode} ${resp.body}');
    }
    final taskId = jsonDecode(resp.body)['output']['task_id'] as String;
    return taskId;
  }

  /// 轮询任务状态，成功后返回结果图 URL。
  Future<String> _pollTask(String taskId) async {
    final uri = Uri.parse('https://dashscope.aliyuncs.com/api/v1/tasks/$taskId');
    const maxAttempts = 30;
    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final resp = await http.get(
        uri,
        headers: <String, String>{'Authorization': 'Bearer $_apiKey'},
      );
      if (resp.statusCode != 200) continue;
      final data = jsonDecode(resp.body);
      final status = data['output']['task_status'] as String;
      if (status == 'SUCCEEDED') {
        return (data['output']['results'] as List)[0]['url'] as String;
      } else if (status == 'FAILED') {
        throw AiPortraitException('生成失败：${data['output']}');
      }
    }
    throw const AiPortraitException('生成超时，请稍后重试');
  }
}

/// Riverpod Provider：AI 写真服务单例。
final aiPortraitServiceProvider = Provider<AiPortraitService>(
  (ref) => AiPortraitService(),
);

/// 源照片（拍摄字节流 或 种子资源路径），统一为可选选择项。
class SourcePhoto {
  const SourcePhoto({this.assetPath, this.bytes, required this.caption});
  final String? assetPath;
  final Uint8List? bytes;
  final String caption;

  /// 解析为字节流（种子资源经 rootBundle 加载）。
  Future<Uint8List> resolveBytes() async {
    if (bytes != null) return bytes!;
    final data = await rootBundle.load(assetPath!);
    return data.buffer.asUint8List();
  }
}
