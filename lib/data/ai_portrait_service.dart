import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:pet_camera/data/app_env.dart';

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
    prompt:
        'Oil portrait on linen canvas. Thick impasto brushstrokes, visible palette knife texture, Rembrandt-style chiaroscuro lighting from upper left, strong tonal contrast. Warm amber/golden hues with deep burnt umber shadows. Muted dark velvet backdrop with shallow bokeh. Strictly preserve the subject\'s original facial geometry, exact coat color, and physical posture \u2013 no anthropomorphism. Photorealistic rendering, canvas grain visible.',
  ),
  PortraitStyle(
    id: 'watercolor',
    name: '水彩',
    icon: LucideIcons.brush,
    prompt:
        'Watercolor painting on cold-pressed paper. Visible paper tooth, transparent washes with blooming edges. High-key pastel palette (pale blue, rose, mint), generous white negative space. Loose brushwork, wet-on-wet diffusion. Gentle morning light. The subject\'s unique facial markings, fur color zones, and original stance must be exactly replicated. Clean white border, minimal background.',
  ),
  PortraitStyle(
    id: 'anime',
    name: '动漫',
    icon: LucideIcons.sparkles,
    prompt:
        'Japanese anime cel-shaded illustration. Clean ink outlines, large expressive eyes with star-shaped highlights. Slightly chibi proportions, soft cel gradients on shadows. Vibrant pastel colors against a dreamy sky background. Maintain the subject\'s ear shape, muzzle length, and distinct color patches \u2013 stylize only rendering, never morphology.',
  ),
  PortraitStyle(
    id: 'vintage',
    name: '复古胶片',
    icon: LucideIcons.camera,
    prompt:
        '1980s analog film photography \u2013 Kodak Portra tone. Warm amber/yellow fade, organic film grain, subtle light leaks in corner, heavy vignette. Soft halation around highlights, low contrast, nostalgic atmosphere. The subject\'s facial structure, coat texture, and exact positioning must remain photorealistically intact \u2013 no artistic distortion.',
  ),
  PortraitStyle(
    id: 'royal',
    name: '国风',
    icon: LucideIcons.crown,
    prompt:
        'Traditional Chinese Gongbi fine-brush painting on silk. Iron-wire linework defining contours, natural mineral pigments (cinnabar, malachite). Decorative peony blossoms, Xiangyun clouds, Ming-style seal and calligraphy. Asymmetric balanced composition with negative space. The subject\'s muzzle proportion, ear set, and distinctive markings must be rendered with accuracy \u2013 only the medium changes.',
  ),
  PortraitStyle(
    id: 'festive',
    name: '节日',
    icon: LucideIcons.gift,
    prompt:
        'Cozy festive indoor scene with cinematic lighting. Warm Christmas tree fairy lights (bokeh in background), gift boxes in crimson, emerald, gold. Soft falling snowflakes, firelight warmth. Volumetric light rays. The subject\'s facial features, full coat color, and posture are non-negotiable \u2013 maintain realistic proportions amid the holiday setting.',
  ),
];

/// AI 写真生成请求。
class PortraitRequest {
  const PortraitRequest({
    required this.sourceBytes,
    required this.styleId,
    this.prompt = '',
  });

  final Uint8List sourceBytes;
  final String styleId;

  /// 自定义提示词（可编辑 / AI 优化后回填）。
  /// 为空时回退到所选风格的内置提示词（[PortraitStyle.prompt]）。
  final String prompt;
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

/// 云端写真服务（百炼 wan2.7-image-pro 图生图，异步任务 API）。
///
/// 真实接入只需在构建期注入 API Key / 代理地址：
///   flutter run --dart-define=DASHSCOPE_API_KEY=你的Key
///   flutter run --dart-define=MAAS_BASE_URL=https://ws-xxxx.cn-beijing.maas.aliyuncs.com/api/v1
///   flutter run --dart-define=AI_PROXY_URL=https://<你的代理>/api/beautify
/// 未配置 Key / 代理时自动进入「演示模式」回显源图，便于在 Web 端跑通完整交互流。
///
/// 写真 = 「照片 → 写真」图生图：wan2.7-image-pro 支持 base64 图片内联输入
/// （multimodal-generation 端点），直连路径与 ECS 代理行为一致。
class AiPortraitService {
  // 安全读取：编译期 --dart-define 注入，禁止硬编码到源码。
  static const String _apiKey = String.fromEnvironment(
    'DASHSCOPE_API_KEY',
    defaultValue: '',
  );

  // Web / iOS / Android 统一走云函数代理（避免 key 进客户端 + 绕过 CORS）。
  // 覆盖默认值：--dart-define=AI_PROXY_URL=https://<你的云函数URL>/api/beautify
  static const String _proxyUrl = AppEnv.aiProxyUrl;

  // 百炼 workspace 专属 base（直连路径用，与 .env 的 MAAS_BASE_URL 一致）。
  static const String _maasBase = String.fromEnvironment(
    'MAAS_BASE_URL',
    defaultValue: 'https://dashscope.aliyuncs.com/api/v1',
  );

  static const String _endpoint =
      '$_maasBase/services/aigc/multimodal-generation/generation';

  /// 生成宠物 AI 写真。
  Future<PortraitResult> generatePortrait(PortraitRequest req) async {
    if (_proxyUrl.isNotEmpty) {
      // Web / 云部署：服务端代理调 DashScope（图生图需源图），返回 base64 图。
      return _generateViaProxy(req);
    }
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
    final prompt = req.prompt.trim().isNotEmpty ? req.prompt.trim() : style.prompt;
    final taskId = await _submitTask(req, prompt);
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

  /// 经代理生成（Web 安全路径，图生图需上传源图字节）。
  Future<PortraitResult> _generateViaProxy(PortraitRequest req) async {
    final resp = await http.post(
      Uri.parse(_proxyUrl),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, String>{
        'styleId': req.styleId,
        'imageBase64': base64Encode(req.sourceBytes),
        // 自定义 / AI 优化后的提示词；缺省时服务端按 styleId 用内置提示词。
        if (req.prompt.trim().isNotEmpty) 'prompt': req.prompt.trim(),
      }),
    );
    if (resp.statusCode != 200) {
      throw AiPortraitException('代理返回错误：${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['error'] != null) {
      throw AiPortraitException('代理错误：${data['error']}');
    }
    final base64 = data['imageBase64'] as String;
    return PortraitResult(
      imageBytes: base64Decode(base64),
      styleId: req.styleId,
    );
  }

  /// 提交异步图生图任务（wan2.7-image-pro + base64 内联源图），返回 task_id。
  /// [prompt] 为用户自定义 / 优化后的提示词（已处理回退到风格默认）。
  Future<String> _submitTask(PortraitRequest req, String prompt) async {
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(req.sourceBytes)}';
    final resp = await http.post(
      Uri.parse(_endpoint),
      headers: <String, String>{
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'X-DashScope-Async': 'enable',
      },
      body: jsonEncode(<String, Object>{
        'model': 'wan2.7-image-pro',
        'input': <String, Object>{
          'messages': <Object>[
            <String, Object>{
              'role': 'user',
              'content': <Object>[
                <String, String>{'text': prompt},
                <String, String>{'image': dataUrl},
              ],
            },
          ],
        },
        'parameters': <String, Object>{'size': '1K', 'n': 1},
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
    final uri = Uri.parse('$_maasBase/tasks/$taskId');
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

  /// 代理根地址（去掉 /api/beautify 路径），供「提示词优化」等子接口拼 URL 用。
  static Uri? get _proxyRoot {
    final raw = _proxyUrl;
    if (raw.isEmpty) return null;
    try {
      final uri = Uri.parse(raw);
      if (!uri.hasScheme || uri.host.isEmpty) return null;
      return Uri.parse('${uri.scheme}://${uri.authority}');
    } catch (_) {
      return null;
    }
  }

  /// AI 优化提示词：发给服务端文本大模型，返回适合宠物写真的完整提示词。
  /// 链路：POST {代理根}/api/beautify/optimize-prompt { prompt } -> { optimizedPrompt }
  /// 未配置代理时走本地演示扩写（便于本地跑通交互）。
  Future<String> optimizePrompt(String userPrompt) async {
    final input = userPrompt.trim();
    if (input.isEmpty) {
      throw const AiPortraitException('请先输入要优化润色的提示词');
    }
    final root = _proxyRoot;
    if (root == null) return _optimizePromptDemo(input);
    final resp = await http
        .post(
          Uri.parse('$root/api/beautify/optimize-prompt'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{'prompt': input}),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw AiPortraitException('提示词优化失败：${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['error'] != null) {
      throw AiPortraitException('提示词优化失败：${data['error']}');
    }
    final optimized = data['optimizedPrompt'] as String?;
    if (optimized == null || optimized.trim().isEmpty) {
      throw const AiPortraitException('提示词优化失败：返回为空');
    }
    return optimized.trim();
  }

  /// 演示模式：未配置代理时的本地扩写模板（真实优化需配置 AI_PROXY_URL）。
  String _optimizePromptDemo(String input) {
    return 'AI 宠物写真，单幅画面：保留毛孩子原有五官结构、毛色分布与自然体态，不做拟人化或形变。主题/补充描述："$input"。在此基础上强化光影质感、背景氛围与细节层次，使画面精致耐看。';
  }
}

/// Riverpod Provider：AI 写真服务单例。
final aiPortraitServiceProvider = Provider<AiPortraitService>(
  (ref) => AiPortraitService(),
);

/// 源照片（拍摄字节流 或 种子远程图），统一为可选选择项。
class SourcePhoto {
  const SourcePhoto({this.url, this.bytes, required this.caption});

  /// 远程图片地址（种子图已外置到对象存储）。
  final String? url;

  /// 内存中的图片字节（用户拍摄 / AI 生成）。
  final Uint8List? bytes;

  final String caption;

  /// 解析为字节流：内存图直接返回，种子图从远程下载。
  Future<Uint8List> resolveBytes() async {
    if (bytes != null) return bytes!;
    final resp = await http.get(Uri.parse(url!));
    if (resp.statusCode != 200) {
      throw AiPortraitException('读取源图失败（${resp.statusCode}）');
    }
    return resp.bodyBytes;
  }
}
