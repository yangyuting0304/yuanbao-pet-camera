/// 物种自动识别 —— 让用户"不用选"，而不是"选得更快"。
///
/// ## 两条现成路径（都不需要自己训练模型）
///
/// | 路径 | 覆盖 | 平台 | 代价 |
/// |---|---|---|---|
/// | **Google ML Kit 基础图像标注**<br>`google_mlkit_image_labeling` | 基础模型自带 `cat` / `dog` / `kitten` / `puppy` / `rabbit` / `rodent` 等标签 | 仅 iOS / Android | 端侧、免费、离线；需加依赖 |
/// | **云端宠物品种识别**（快瞳科技等）| 猫狗品种级 + 面部/鼻纹 | 全平台（含网页）| 需 API Key 与网络往返 |
///
/// **注意跨平台的坑**：ML Kit 的 Flutter 插件依赖 `dart:io`，
/// 直接 import 会**让 Web 构建失败**。所以本文件只定义接口与纯逻辑映射，
/// 真正的 ML Kit 实现要放到用条件导入隔离的文件里
/// （参考项目里 `media_platform_*.dart` 的既有做法）。
///
/// ## 兜底原则
///
/// 识别只是"替用户先猜一次"。任何不确定都要退回到
/// [NoSpeciesDetector] 的语义——即"没猜出来，请用户选"，
/// 而不是硬套一个错的物种参数。
library;

import 'dart:typed_data';

import 'pet_capture_profile.dart';

/// 物种识别结果。
typedef PetSpeciesGuess = ({
  /// 判定的物种。
  PetSpecies species,

  /// 置信度 0..1。
  double confidence,

  /// 命中的原始标签（便于排查与展示）。
  String matchedLabel,
});

/// 单条图像标签。
typedef ImageLabelLike = ({String label, double confidence});

/// 物种识别器。
abstract class PetSpeciesDetector {
  /// 是否已就绪（模型可用 / 平台支持）。未就绪时上层直接跳过。
  bool get isAvailable;

  /// 识别图中宠物的物种；识别不出返回 null。
  ///
  /// [filePath] 供 ML Kit 之类的实现直接用文件路径构造入参，
  /// 避免多一次内存拷贝。
  Future<PetSpeciesGuess?> detect(
    Uint8List image, {
    String? filePath,
    required int width,
    required int height,
  });
}

/// 未接入识别能力时的空实现。
///
/// 用空对象而不是 nullable，是为了让上层不必到处写
/// `if (detector != null)`；行为等价于"没识别出来，请用户选"。
class NoSpeciesDetector implements PetSpeciesDetector {
  const NoSpeciesDetector();

  @override
  bool get isAvailable => false;

  @override
  Future<PetSpeciesGuess?> detect(
    Uint8List image, {
    String? filePath,
    required int width,
    required int height,
  }) async => null;
}

/// 图像标签 → 物种 的映射（纯逻辑，可直接单测）。
class PetLabelMapper {
  PetLabelMapper._();

  /// 低于此置信度的标签直接丢弃。
  static const double minConfidence = 0.5;

  /// 关键词 contains 匹配的**误伤排除表**。
  ///
  /// ImageNet 里大量类名含 'cat'/'dog' 字样但不是宠物：
  /// 'caterpillar'（毛虫）、'catfish'（鲶鱼）、'catamaran'（双体船）、
  /// 'hot dog'（热狗）…… 单标签场景误伤概率低，但端侧**全类聚合**时
  /// 这些类的概率会被计入对应物种，足以翻转判定，必须先排除。
  static const List<String> exclusions = [
    'caterpillar',
    'catfish',
    'catkin',
    'catamaran',
    'hot dog',
    'hotdog',
    'dogfish',
    'dogwood',
    'madagascar cat',
  ];

  /// 各物种的匹配关键字。
  ///
  /// 顺序即优先级：越"小众"的越先匹配。否则 `guinea pig` 会先命中
  /// 含有 `pig` 的关键字，`chinchilla` 会先被当成普通啮齿类。
  static const Map<PetSpecies, List<String>> keywords = {
    // 鱼类放在最前：云端供应商若真返回了鱼的标签，先归到这里。
    // （端侧 EfficientDet 训练在 COCO 上，COCO 无鱼类，识别不出来；
    //   鱼缸场景目前靠用户在「拍谁」里手动选，见 PetSpecies.fish 注释。）
    PetSpecies.fish: [
      'goldfish',
      'koi',
      'betta',
      'guppy',
      'angelfish',
      'cichlid',
      'tetra',
      'aquarium',
      'fish',
      '金鱼',
      '锦鲤',
      '斗鱼',
      '孔雀鱼',
      '神仙鱼',
      '热带鱼',
      '观赏鱼',
      '鱼',
    ],
    PetSpecies.chinchilla: [
      'chinchilla',
      'guinea pig',
      'hamster',
      'gerbil',
      'rodent',
      'squirrel',
      // 中文必须收全：「龙猫」里含「猫」、「豚鼠」里含「鼠」，
      // 少一个就会被后面的猫科/啮齿类先匹配走。
      '龙猫',
      '毛丝鼠',
      '豚鼠',
      '荷兰猪',
      '仓鼠',
      '啮齿',
    ],
    PetSpecies.rabbit: [
      'rabbit',
      'bunny',
      'hare',
      'cottontail',
      'lop',
      // 中文
      '兔',
      '穴兔',
      '垂耳兔',
    ],
    PetSpecies.cat: [
      'cat',
      'kitten',
      'kitty',
      'tabby',
      'siamese',
      'persian',
      'ragdoll',
      'bengal',
      'shorthair',
      'sphynx',
      'maine coon',
      // 中文
      '猫',
      '英短',
      '美短',
      '布偶',
      '狸花',
      '缅因',
      '暹罗',
      '蓝猫',
    ],
    PetSpecies.dog: [
      'dog',
      'puppy',
      'pup',
      'retriever',
      'labrador',
      'poodle',
      'corgi',
      'husky',
      'beagle',
      'bulldog',
      'shepherd',
      'terrier',
      'chihuahua',
      'dachshund',
      'pug',
      'shiba',
      'akita',
      'collie',
      'spaniel',
      'schnauzer',
      // 中文
      '犬',
      '狗',
      '柯基',
      '柴犬',
      '金毛',
      '拉布拉多',
      '萨摩',
      '泰迪',
      '贵宾',
      '边牧',
      '哈士奇',
      '比熊',
      '博美',
    ],
  };

  /// 把一条标签映射成物种；无法映射返回 null。
  static PetSpecies? speciesOf(String label) {
    final normalized = label.toLowerCase().trim();
    if (normalized.isEmpty) return null;
    for (final ex in exclusions) {
      if (normalized.contains(ex)) return null;
    }
    for (final entry in keywords.entries) {
      for (final keyword in entry.value) {
        if (normalized.contains(keyword)) return entry.key;
      }
    }
    return null;
  }

  /// 从一组标签里选出最可信的物种。
  ///
  /// 只接受置信度达标的标签；同一物种命中多次时取最高分。
  static PetSpeciesGuess? fromLabels(List<ImageLabelLike> labels) {
    PetSpeciesGuess? best;
    for (final item in labels) {
      if (item.confidence < minConfidence) continue;
      final species = speciesOf(item.label);
      if (species == null) continue;
      if (best == null || item.confidence > best.confidence) {
        best = (
          species: species,
          confidence: item.confidence,
          matchedLabel: item.label,
        );
      }
    }
    return best;
  }

  /// 超类聚合：把**全部**带分标签按物种求和，取总分最高的物种。
  ///
  /// 与 [fromLabels] 的区别：fromLabels 是"单标签最高分"（适合 ML Kit
  /// 这类只吐少量标签的识别器）；aggregate 是"同类合并"——ImageNet 有
  /// 一百多个犬种、十几个猫种，把它们各自的概率加总后置信度远高于任何
  /// 单类，判定也稳得多（单类误判会被同类其他项稀释）。
  ///
  /// [minConfidence] 是**单条标签**的进入门槛（远低于物种判定阈值），
  /// 聚合本身会自然把噪声类压低。
  static PetSpeciesGuess? aggregate(
    Iterable<ImageLabelLike> scored, {
    double minConfidence = 0.02,
  }) {
    final sums = <PetSpecies, double>{};
    final topLabels = <PetSpecies, ImageLabelLike>{};
    for (final item in scored) {
      if (item.confidence < minConfidence) continue;
      final species = speciesOf(item.label);
      if (species == null) continue;
      sums[species] = (sums[species] ?? 0) + item.confidence;
      final top = topLabels[species];
      if (top == null || item.confidence > top.confidence) {
        topLabels[species] = item;
      }
    }
    PetSpecies? best;
    var bestScore = 0.0;
    for (final entry in sums.entries) {
      if (entry.value > bestScore) {
        best = entry.key;
        bestScore = entry.value;
      }
    }
    if (best == null) return null;
    final species = best; // 局部非空别名，record 字段要求非空。
    final top = topLabels[species]!;
    return (
      species: species,
      confidence: bestScore.clamp(0.0, 1.0),
      matchedLabel: top.label,
    );
  }
}

/// 级联识别器：先试主识别器（端侧），拿不到结果再退备用（云端）。
///
/// 任何一侧抛异常都视为"没识别出来"，绝不向上传播——识别是锦上添花，
/// 不能影响拍照主流程（与项目既有降级原则一致）。
class TieredSpeciesDetector implements PetSpeciesDetector {
  TieredSpeciesDetector(this._primary, this._fallback);

  final PetSpeciesDetector _primary;
  final PetSpeciesDetector _fallback;

  @override
  bool get isAvailable => _primary.isAvailable || _fallback.isAvailable;

  @override
  Future<PetSpeciesGuess?> detect(
    Uint8List image, {
    String? filePath,
    required int width,
    required int height,
  }) async {
    if (_primary.isAvailable) {
      try {
        final primary = await _primary.detect(
          image,
          filePath: filePath,
          width: width,
          height: height,
        );
        if (primary != null) return primary;
      } catch (_) {
        // 主识别器异常 → 直接走备用，不中断。
      }
    }
    if (_fallback.isAvailable) {
      return _fallback.detect(
        image,
        filePath: filePath,
        width: width,
        height: height,
      );
    }
    return null;
  }
}
