import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// AI 一键成片：内置「宠物场景」选项卡（点选填充提示词）。
/// 每个场景一段中文 prompt，面向万相图生视频，描述动作与氛围。
class AiVideoScene {
  const AiVideoScene({required this.label, required this.prompt});
  final String label;
  final String prompt;
}

const List<AiVideoScene> kAiVideoScenes = <AiVideoScene>[
  AiVideoScene(
    label: '摇奶茶',
    prompt:
        '固定机位，吧台前中景。毛孩子两只前爪紧紧环抱不锈钢雪克杯，手肘带动前臂高频震动，冰块与茶汤碰撞出清脆响声，耳朵随节奏抖动。持续摇晃约3秒后，它停止动作，将雪克杯稳稳放回吧台，用爪尖掀开杯盖，随即侧头从旁边的吸管盒中用嘴叼出一根吸管，精准对准杯口插入，爪垫轻压吸管顶端将其固定。接着，它两只前爪捧起奶茶杯，身体微微前倾，将杯子缓缓递向镜头方向，眼神期待地看向镜头外的顾客，尾巴轻轻左右摆动，保持递出姿势等待对方接取，头顶暖黄灯光映在杯身水珠上。动作全程保持毛孩子原有外形和毛色不变，以自然匀速运动为主，避免扭曲变形。若动作过多，可适当放慢节奏，确保每步清晰可见。',
  ),
  AiVideoScene(
    label: '摊煎饼',
    prompt:
        '正前方平视视角，铁板热气升腾。毛孩子先用右爪握刮板将面糊摊成圆饼，随即左爪磕蛋撒葱花。稍等片刻（饼底定型），它用右爪拿起小铲子从边缘伸入，手腕一翻将煎饼利落翻面，焦黄的饼面冒着香气。紧接着它用刷子蘸取甜面酱，均匀涂抹在饼面上，再用爪尖夹起一根火腿肠横放在饼中央，随后用爪指将饼的两侧向内折叠，轻轻按压卷紧。最后它取过一个纸袋，用嘴衔开袋口，用爪子将卷好的煎饼推入袋中，叼起袋子递向镜头，歪着头等待顾客接过，身后市集的嘈杂声隐约可感。动作全程保持毛孩子原有外形和毛色不变，以自然匀速运动为主，避免扭曲变形。若动作过多，可适当放慢节奏，确保每步清晰可见。',
  ),
  AiVideoScene(
    label: '做咖啡',
    prompt:
        '镜头随毛孩子横向平移。它先从画面右侧走到咖啡机旁，用爪尖抓取一把咖啡豆放入研磨机，按下启动键研磨，随后将手柄扣入咖啡机，按下萃取键，注视深棕色咖啡液缓缓流入杯中。萃取完成后，它用爪子端起杯子，转身走回柜台前放稳，再拿起拉花杯，倾斜杯嘴，以手腕细腻的摆动注入奶泡，在液面上拉出一颗爱心。最后它用两只爪子捧起咖啡杯，轻轻推向镜头方向，微微点头，示意顾客享用，背景中咖啡机蒸汽嘶嘶作响。动作全程保持毛孩子原有外形和毛色不变，以自然匀速运动为主，避免扭曲变形。若动作过多，可适当放慢节奏，确保每步清晰可见。',
  ),
  AiVideoScene(
    label: '弹钢琴',
    prompt:
        '毛孩子坐在钢琴前，前爪在琴键上流畅弹奏，身体随旋律微微晃动。弹完一段后，它突然停下，后腿发力站起，两只前爪搭上琴谱架，快速翻过一页乐谱，随即落座继续弹奏。此时窗外飞进两只小鸟，落在窗台上歪头聆听。毛孩子被鸟鸣声吸引，琴声渐缓，它转头望向小鸟，目光好奇。片刻后它猛地跳下琴凳，扑向窗台，小鸟受惊飞起，它前爪扒住窗沿，抬头望着飞走的小鸟，露出既困惑又失落的表情，尾巴慢慢垂下，琴谱被微风撩动。动作全程保持毛孩子原有外形和毛色不变，以自然匀速运动为主，避免扭曲变形。若动作过多，可适当放慢节奏，确保每步清晰可见。',
  ),
  AiVideoScene(
    label: '踢足球',
    prompt:
        '绿茵场上，毛孩子从画面左侧快速追球跑来，用前爪交替推球前进。遇到两个训练桩时，它先向右虚晃，随即向左急停变向，轻松绕过障碍。接着它带球直奔球门，面对空门，抬起右后腿全力抽射，足球划出弧线飞入网窝。进球后，它兴奋地原地跳起，在空中转体半圈，落地后绕着球场小跑，尾巴高高翘起，耳朵向后飞扬，嘴巴微张像在欢呼，阳光在它身后投下跃动的影子。动作全程保持毛孩子原有外形和毛色不变，以自然匀速运动为主，避免扭曲变形。若动作过多，可适当放慢节奏，确保每步清晰可见。',
  ),
  AiVideoScene(
    label: '开小卖部',
    prompt:
        '毛孩子站在小卖部柜台后，正用前爪将货架上散落的零食摆齐。这时镜头外顾客走近，它立刻转身，两只前爪撑在柜台上，歪头微笑。顾客指向柜台上的棒棒糖，它用嘴叼起一根，轻轻放在台面上，再用爪子比划价格（比如拍两下柜台表示两块）。顾客递过纸币，它用爪子接过，转身从钱箱里翻出硬币，用嘴衔着零钱递给顾客。最后它用爪子将棒棒糖向前推了推，目送顾客离开，尾巴悠闲地左右摆动，身后冰柜的嗡鸣声持续不断。动作全程保持毛孩子原有外形和毛色不变，以自然匀速运动为主，避免扭曲变形。若动作过多，可适当放慢节奏，确保每步清晰可见。',
  ),
];

/// 反向提示词（宠物优化版）：在通用负面词基础上，加了宠物视频常见雷点。
const String kAiVideoNegativePrompt =
    '低分辨率、模糊、最差质量、低质量、残缺、比例不良、畸形肢体、多余腿爪、面部变形、五官扭曲、多只宠物、背景穿帮、文字、水印';

/// 万相异步任务状态（映射代理返回的 task_status）。
enum AiVideoTaskStatus {
  pending,
  running,
  succeeded,
  failed,
  canceled,
  unknown,
}

/// 成片生成请求（首帧成片，分辨率固定 720P，由服务端写死）。
class AiVideoRequest {
  const AiVideoRequest({
    required this.imageBytes,
    required this.prompt,
    required this.negativePrompt,
    required this.duration,
    required this.watermark,
  });
  final Uint8List imageBytes;
  final String prompt;
  final String negativePrompt;
  final int duration; // 2-15 秒
  final bool watermark;
}

/// 成片生成结果。
class AiVideoResult {
  const AiVideoResult({
    required this.videoBytes,
    required this.taskId,
    this.demo = false,
  });
  final Uint8List videoBytes;
  final String taskId;
  final bool demo; // 演示模式（未配置代理/接入真实模型时为真）
}

/// 成片服务异常（UI 层据此展示错误信息）。
class AiVideoException implements Exception {
  const AiVideoException(this.message);
  final String message;
  @override
  String toString() => 'AiVideoException: $message';
}

/// AI 一键成片服务（万相2.7 图生视频，异步任务：提交 -> 轮询 -> 下载）。
///
/// 链路（与代理协议严格对齐，见 cloud_functions/ai_portrait/index.js）：
///   1. POST {proxy}/api/ai-video      { imageBase64, prompt, negativePrompt, duration, watermark }
///      -> { taskId }
///   2. GET  {proxy}/api/ai-video/status?taskId=xxx  （每 15s 轮询）
///      -> { status, videoUrl?, error? }，SUCCEEDED 后取 videoUrl 下载
///   3. 下载 MP4 字节 -> 存入短片库
///
/// 构建期注入代理地址（代理根域名，不含路径）：
///   flutter run --dart-define=AI_VIDEO_PROXY_URL=https://<你的域名>
/// 未配置时进入「演示模式」：加载内置本地视频模拟完整交互流。
class AiVideoService {
  // Web / 云部署：服务端代理根地址（编译期 --dart-define 注入，禁止硬编码）。
  static const String _proxyUrl = String.fromEnvironment(
    'AI_VIDEO_PROXY_URL',
    defaultValue: '',
  );

  // 演示模式用的内置视频（已在 pubspec.yaml 声明为资源）。
  static const String _demoVideoAsset =
      'assets/seed/photos/feat_video_compressed.mp4';

  /// 生成一段 AI 视频。
  Future<AiVideoResult> generate(AiVideoRequest req) async {
    if (_proxyUrl.isEmpty) {
      return _generateDemo(req);
    }
    final base = _proxyUrl.replaceAll(RegExp(r'/+$'), '');
    final taskId = await _submit(base, req);
    final videoUrl = await _poll(base, taskId);
    final videoBytes = await _download(videoUrl);
    return AiVideoResult(videoBytes: videoBytes, taskId: taskId);
  }

  /// 演示模式：未配置代理，模拟耗时后返回内置本地视频，走通完整交互流。
  Future<AiVideoResult> _generateDemo(AiVideoRequest req) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final data = await rootBundle.load(_demoVideoAsset);
    return AiVideoResult(
      videoBytes: data.buffer.asUint8List(),
      taskId: 'demo',
      demo: true,
    );
  }

  /// 步骤 1：创建异步任务，返回 task_id。
  Future<String> _submit(String base, AiVideoRequest req) async {
    final resp = await http
        .post(
          Uri.parse('$base/api/ai-video'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object>{
            'imageBase64': base64Encode(req.imageBytes),
            'prompt': req.prompt,
            'negativePrompt': req.negativePrompt,
            'duration': req.duration.clamp(2, 15),
            'watermark': req.watermark,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw AiVideoException('提交失败：${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['error'] != null) {
      throw AiVideoException('提交失败：${data['error']}');
    }
    return data['taskId'] as String;
  }

  /// 步骤 2：轮询任务状态（15s 间隔），成功后返回视频 URL。
  Future<String> _poll(String base, String taskId) async {
    final uri = Uri.parse('$base/api/ai-video/status?taskId=$taskId');
    // 万相任务通常 1-5 分钟；上限 6 分钟（24 次轮询）。
    const maxAttempts = 24;
    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(const Duration(seconds: 15));
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) continue;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? 'UNKNOWN';
      switch (status) {
        case 'SUCCEEDED':
          final url = data['videoUrl'] as String?;
          if (url == null) {
            throw const AiVideoException('任务成功但缺少视频地址');
          }
          return url;
        case 'FAILED':
          throw AiVideoException('生成失败：${data['error'] ?? '未知原因'}');
        case 'CANCELED':
          throw const AiVideoException('任务已取消，请重新生成');
        case 'UNKNOWN':
          throw const AiVideoException('任务不存在或已过期，请重新生成');
      }
      // PENDING / RUNNING：继续轮询。
    }
    throw const AiVideoException('生成超时（约 6 分钟），请稍后重试');
  }

  /// 步骤 3：下载视频字节。
  Future<Uint8List> _download(String videoUrl) async {
    final resp = await http
        .get(Uri.parse(videoUrl))
        .timeout(const Duration(seconds: 120));
    if (resp.statusCode != 200) {
      throw const AiVideoException('下载视频失败');
    }
    return resp.bodyBytes;
  }
}

/// Riverpod Provider：AI 成片服务单例。
final aiVideoServiceProvider = Provider<AiVideoService>(
  (ref) => AiVideoService(),
);
