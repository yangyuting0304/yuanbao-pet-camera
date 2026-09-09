import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pet_camera/data/app_env.dart';

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
    label: '三打白骨精',
    prompt:
        '第一幕（唐僧猫）：毛孩子身披红色袈裟（小毯子代替），头戴毗卢帽（纸折的），端坐在石头（沙发靠垫）上，双爪合十，闭眼念经，尾巴安静盘在身侧。第二幕（白骨精猫）：画面一转，同一只毛孩子换上白色纱巾，从树后（花盆）探出半个身子，前爪拎着一个竹篮（里面是玩具鱼干），歪头露出狡黠的眼神，耳朵向后压平，迈着轻佻的猫步缓缓靠近。第三幕（悟空猫）：毛孩子瞬间"变装"——头上戴一个金箍圈（铁丝拧的），前爪握着一根金箍棒（筷子/吸管），从高处（猫爬架顶端）一跃而下，落在白骨精猫面前，举起"金箍棒"作势要打。第四幕（三打交锋）：白骨精猫后腿蹬地向后弹跳躲避，悟空猫连续三次前扑追击，每次都扑空。最后一次悟空猫高高跳起，前爪拍地，白骨精猫顺势倒地翻滚一圈，四脚朝天露出肚皮，装死不动。悟空猫用爪子拨了拨它，见没反应，便得意地翘起尾巴，转身走到一旁坐下，爪子在嘴边舔了舔，像在说"搞定"。背景：山石布景、烟雾缭绕（加湿器雾气），暖黄夕阳光线。动作全程保持毛孩子原有外形和毛色不变，以自然匀速运动为主，避免扭曲变形。若动作过多，可适当放慢节奏，确保每步清晰可见。',
  ),
  AiVideoScene(
    label: '猫八戒抓媳妇',
    prompt:
        '第一幕（猪八戒猫）：毛孩子戴着一个猪鼻子头套，肚皮上绑着圆形抱枕（假装大肚子），肩扛一把钉耙（用拖把杆代替），晃着大屁股、迈着外八字步从画面左侧走来，尾巴调皮地翘成一个问号形状。第二幕（盯上媳妇）：它发现画面右侧站着一位"高小姐"——其实是同一只毛孩子换上红盖头（红手帕搭在头上），穿着小花袄（小背心），正背对着梳妆。猪八戒猫眼睛一亮，耳朵竖起，咧开嘴（露出小尖牙），蹑手蹑脚靠近，爪子轻轻搭在对方肩上。第三幕（回头惊吓）：高小姐猫猛地一回头——盖头下的脸竟然和猪八戒猫长得一模一样（其实就是它自己）。猪八戒猫吓得"嗷"一嗓子，向后弹开两步，钉耙都掉在地上，前爪捂住胸口做出夸张的惊吓状。第四幕（你追我赶）：猪八戒猫缓过神，又嬉皮笑脸地追上去，高小姐猫转身逃跑，绕着桌子（道具）转圈。猪八戒猫追了两圈后，假装体力不支，趴在地上吐舌头喘气，前爪无力地向前伸了伸，表示"不追了不追了"，高小姐猫则停在远处，歪头看着它，眼神既得意又好奇。背景：红绸布装饰，大红喜字剪纸，灯笼暖光，喜庆氛围。所有场景使用同一只毛孩子出镜，通过更换道具（头饰、披风、小衣服）和背景（不同颜色的布料/纸板）来实现角色切换。动作保持自然猫类习性（跳跃、扑抓、翻滚、用嘴衔物），避免过度拟人化导致失真。每个分幕之间可用黑屏淡入淡出做转场，总时长控制在12-15秒/场景。猫的特征（爪垫、尾巴、耳朵、胡须）始终保持清晰可见，不因服饰遮挡。',
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

/// 成片生成请求（分辨率由服务端按所选模型固定，默认 720P）。
/// [model] 为空表示走服务端默认首帧模型；可选 wan2.6-r2v / wan2.6-r2v-flash。
class AiVideoRequest {
  const AiVideoRequest({
    required this.imageBytes,
    required this.prompt,
    required this.negativePrompt,
    required this.duration,
    required this.watermark,
    this.model,
  });
  final Uint8List imageBytes;
  final String prompt;
  final String negativePrompt;
  final int duration; // 秒；首帧 2-15，参考生视频 2-10（服务端会按模型钳制）
  final bool watermark;
  final String? model; // 视频模型标识；null = 服务端默认（VIDEO_MODEL）
}

/// 单次状态查询结果（GET /api/ai-video/status）。
class AiVideoStatus {
  const AiVideoStatus({
    required this.status,
    this.videoUrl,
    this.error,
  });
  final AiVideoTaskStatus status;
  final String? videoUrl;
  final String? error;
}

/// 成片生成结果。
class AiVideoResult {
  const AiVideoResult({
    required this.videoBytes,
    required this.taskId,
    this.demo = false,
    this.sourceUrl,
    this.streamUrl,
  });
  final Uint8List videoBytes;
  final String taskId;
  final bool demo; // 演示模式（未配置代理/接入真实模型时为真）

  /// 服务端返回的远程视频直链（万相 OSS 地址，非 demo 模式时有值）。
  /// 仅作兜底/保存用；播放优先用 [streamUrl]。
  final String? sourceUrl;

  /// Web 端播放地址：本服务后端代理（faststart + Range），手机上秒开、
  /// 不受 OSS 防盗链/CORS/慢下载影响。原生端为 null（直接走本地字节）。
  final String? streamUrl;
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
/// 构建期注入代理地址（代理根域名，不含路径）覆盖默认值：
///   flutter build ios --release --dart-define=AI_VIDEO_PROXY_URL=https://<你的域名>
/// 未配置（含 Xcode 直接 Archive 漏传 dart-define）时使用 [AppEnv] 的生产默认值；
/// 只有在显式注入为空串时才进入「演示模式」：加载内置本地视频模拟完整交互流。
class AiVideoService {
  // 服务端代理根地址（编译期 --dart-define 注入，未注入时回落生产默认值）。
  static const String _proxyUrl = AppEnv.aiVideoProxyUrl;

  // 演示模式用的内置视频（已在 pubspec.yaml 声明为资源）。
  static const String _demoVideoAsset =
      'assets/seed/photos/feat_video_compressed.mp4';

  /// 去掉结尾斜杠的代理根地址。
  static String get _base => _proxyUrl.replaceAll(RegExp(r'/+$'), '');

  /// 演示模式（未配置代理）：本地模拟，不产生 taskId、不落缓存。
  static bool get isDemo => _proxyUrl.isEmpty;

  /// 生成一段 AI 视频。
  ///
  /// Web 端：任务成功后不整包下载，直接返回远程直链（sourceUrl）供
  /// `<video>` 流式播放 —— 手机上不依赖 blob 解码、不受 CORS 影响。
  /// 用户点「下载 / 保存到相册」时再经 [fetchVideoBytes] 按需取字节。
  /// 原生端：仍需字节落盘播放，保持整包下载。
  Future<AiVideoResult> generate(AiVideoRequest req) async {
    if (_proxyUrl.isEmpty) {
      return generateDemo(req);
    }
    final taskId = await submit(req);
    final videoUrl = await _poll(_base, taskId);
    final Uint8List videoBytes;
    if (kIsWeb) {
      videoBytes = Uint8List(0);
    } else {
      videoBytes = await _download(_base, taskId);
    }
    return buildResult(
      taskId: taskId,
      videoUrl: videoUrl,
      videoBytes: videoBytes,
    );
  }

  /// 步骤 1：只提交任务，返回 taskId（不轮询）。
  /// 轮询交给 [TaskCenter]，这样退出页面也不会丢结果。
  Future<String> submit(AiVideoRequest req) async {
    if (_proxyUrl.isEmpty) {
      throw const AiVideoException('演示模式不支持真实生成');
    }
    return _submit(_base, req);
  }

  /// 查询一次任务状态（只读接口，不计费）。
  Future<AiVideoStatus> fetchStatus(String taskId) async {
    if (_proxyUrl.isEmpty) {
      throw const AiVideoException('未配置服务端代理');
    }
    return _fetchStatus(_base, taskId);
  }

  /// 按 taskId 构造可播放结果：Web 走后端代理流，原生用字节。
  AiVideoResult buildResult({
    required String taskId,
    required String videoUrl,
    Uint8List? videoBytes,
  }) {
    if (kIsWeb) {
      // 播放地址用后端代理（faststart + Range），不要直连 OSS ——
      // 万相 mp4 的 moov 在文件尾，手机直连会因需整包下载而一直转圈。
      return AiVideoResult(
        videoBytes: Uint8List(0),
        taskId: taskId,
        sourceUrl: videoUrl,
        streamUrl:
            '$_base/api/ai-video/video?taskId=${Uri.encodeQueryComponent(taskId)}',
      );
    }
    return AiVideoResult(
      videoBytes: videoBytes ?? Uint8List(0),
      taskId: taskId,
      sourceUrl: videoUrl,
    );
  }

  /// 调试回放：用已成功的 taskId 直接取结果（不新建任务、零费用）。
  /// 首次立即查状态，之后每 20s 轮询直至 SUCCEEDED/FAILED。
  Future<AiVideoResult> replayTask(String taskId) async {
    if (_proxyUrl.isEmpty) {
      throw const AiVideoException('未配置服务端代理');
    }
    final videoUrl = await _poll(_base, taskId, immediate: true);
    final Uint8List videoBytes;
    if (kIsWeb) {
      videoBytes = Uint8List(0);
    } else {
      videoBytes = await _download(_base, taskId);
    }
    return buildResult(
      taskId: taskId,
      videoUrl: videoUrl,
      videoBytes: videoBytes,
    );
  }

  /// 演示模式：未配置代理，模拟耗时后返回内置本地视频，走通完整交互流。
  Future<AiVideoResult> generateDemo(AiVideoRequest req) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final data = await rootBundle.load(_demoVideoAsset);
    return AiVideoResult(
      videoBytes: data.buffer.asUint8List(),
      taskId: 'demo',
      demo: true,
    );
  }

  /// AI 优化：把用户输入的简短场景描述，扩写为详细的图生视频提示词。
  ///
  /// 链路：POST {proxy}/api/ai-video/optimize-prompt { prompt } -> { optimizedPrompt }
  /// 元提示词由服务端持有（prompts.js 的 PROMPT_OPTIMIZER），前端只传用户输入。
  /// 未配置代理时进入「演示模式」：用本地模板简单扩写，便于本地跑通交互。
  Future<String> optimizePrompt(String userPrompt) async {
    final input = userPrompt.trim();
    if (input.isEmpty) {
      throw const AiVideoException('请先输入要优化的场景描述');
    }
    if (_proxyUrl.isEmpty) {
      return _optimizePromptDemo(input);
    }
    final base = _proxyUrl.replaceAll(RegExp(r'/+$'), '');
    final resp = await http
        .post(
          Uri.parse('$base/api/ai-video/optimize-prompt'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object>{'prompt': input}),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw AiVideoException('提示词优化失败：${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['error'] != null) {
      throw AiVideoException('提示词优化失败：${data['error']}');
    }
    final optimized = data['optimizedPrompt'] as String?;
    if (optimized == null || optimized.trim().isEmpty) {
      throw const AiVideoException('提示词优化失败：返回为空');
    }
    return optimized.trim();
  }

  /// 演示模式：未配置代理时的本地扩写模板（真实优化需配置 AI_VIDEO_PROXY_URL）。
  String _optimizePromptDemo(String input) {
    return '固定机位，中景。毛孩子正在演绎"$input"：先用前爪试探性地拨弄场景中的道具，确认安全后展开动作，身体保持自然舒展，尾巴随动作轻轻摆动；过程中穿插一个抬头看向镜头的特写，眼神专注；最后以一个明确的收尾动作定格（如递出物品、坐下回望），让画面有完整感。暖色侧光营造氛围，背景虚化突出主体。动作全程保持毛孩子原有外形和毛色不变，以自然匀速运动为主，避免扭曲变形。';
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
            if (req.model != null && req.model!.isNotEmpty) 'model': req.model!,
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

  /// 单次状态查询：GET /api/ai-video/status?taskId=xxx。
  Future<AiVideoStatus> _fetchStatus(String base, String taskId) async {
    final uri = Uri.parse(
      '$base/api/ai-video/status?taskId=${Uri.encodeQueryComponent(taskId)}',
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw AiVideoException('查询状态失败：${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['error'] != null) {
      throw AiVideoException('查询状态失败：${data['error']}');
    }
    final status = switch (data['status'] as String? ?? 'UNKNOWN') {
      'SUCCEEDED' => AiVideoTaskStatus.succeeded,
      'FAILED' => AiVideoTaskStatus.failed,
      'CANCELED' => AiVideoTaskStatus.canceled,
      'UNKNOWN' => AiVideoTaskStatus.unknown,
      'PENDING' => AiVideoTaskStatus.pending,
      _ => AiVideoTaskStatus.running,
    };
    return AiVideoStatus(
      status: status,
      videoUrl: data['videoUrl'] as String?,
      error: data['error'] as String?,
    );
  }

  /// 步骤 2：轮询任务状态（20s 间隔），成功后返回视频 URL。
  /// [immediate] 为 true 时首查不等 20s（调试回放 / 冷启动恢复用）。
  Future<String> _poll(
    String base,
    String taskId, {
    bool immediate = false,
  }) async {
    // 万相任务通常 1-5 分钟；上限约 8 分钟（24 次轮询）。
    const maxAttempts = 24;
    for (var i = 0; i < maxAttempts; i++) {
      if (!immediate || i > 0) {
        await Future<void>.delayed(const Duration(seconds: 20));
      }
      final s = await _fetchStatus(base, taskId);
      switch (s.status) {
        case AiVideoTaskStatus.succeeded:
          final url = s.videoUrl;
          if (url == null) {
            throw const AiVideoException('任务成功但缺少视频地址');
          }
          return url;
        case AiVideoTaskStatus.failed:
          throw AiVideoException('生成失败：${s.error ?? '未知原因'}');
        case AiVideoTaskStatus.canceled:
          throw const AiVideoException('任务已取消，请重新生成');
        case AiVideoTaskStatus.unknown:
          throw const AiVideoException('任务不存在或已过期，请重新生成');
        case AiVideoTaskStatus.pending:
        case AiVideoTaskStatus.running:
          break; // 继续轮询。
      }
    }
    throw const AiVideoException('生成超时（约 8 分钟），请稍后重试');
  }

  /// 按需获取视频字节（下载 / 保存到相册时调用）。
  /// 走后端代理（GET /api/ai-video/video?taskId=xxx），避免 Web 端直接 fetch
  /// 万相 OSS 签名 URL（浏览器 CORS 拦截，会 Failed to fetch）。
  Future<Uint8List> fetchVideoBytes(String taskId) async {
    if (_proxyUrl.isEmpty) {
      throw const AiVideoException('未配置服务端代理');
    }
    final base = _proxyUrl.replaceAll(RegExp(r'/+$'), '');
    return _download(base, taskId);
  }

  /// 步骤 3：从代理下载视频字节（内部实现）。
  Future<Uint8List> _download(String base, String taskId) async {
    final uri = Uri.parse(
      '$base/api/ai-video/video?taskId=${Uri.encodeQueryComponent(taskId)}',
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 120));
    if (resp.statusCode != 200) {
      throw AiVideoException('下载视频失败：${resp.statusCode} ${resp.body}');
    }
    return resp.bodyBytes;
  }
}

/// Riverpod Provider：AI 成片服务单例。
final aiVideoServiceProvider = Provider<AiVideoService>(
  (ref) => AiVideoService(),
);
