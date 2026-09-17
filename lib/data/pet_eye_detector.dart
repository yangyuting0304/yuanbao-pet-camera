/// 宠物眼睛定位 —— 切片F 的接入层。
///
/// ## 为什么单独抽一层
///
/// 「眼睛在哪」和「拿眼睛做什么」是两件独立的事：
///  - **在哪**：需要一个关键点模型（还没就位）
///  - **做什么**：锁眼对焦（[Offset] 送给相机）、眼睛增强（后处理提亮瞳色）
///
/// 把前者抽成接口，后者就能先写完并测好。模型到位时只需实现这个接口，
/// 上层一行都不用改。
///
/// ## 眼睛坐标的两个可选来源
///
/// | 来源 | 优点 | 代价 |
/// |---|---|---|
/// | 端侧关键点模型<br>`DogFaceRecognition-PoseDetection`（YOLOv8-pose，输出左耳/右耳/左眼/右眼/鼻子）| 实时、免流量、可跟焦 | 需转 TFLite 并打包进 App |
/// | 云端宠物面部识别（快瞳）| 免训练 | 有网络往返，只适合拍后处理，不能用于实时对焦 |
///
/// ## 还缺的两块（接入前必须补）
///
/// 1. **模型文件**：把 YOLOv8-pose 导出为 `.tflite` 并在 `pubspec.yaml` 声明
/// 2. **帧来源**：每帧拿到预览图。`camera` 插件只在原生支持
///    `startImageStream`，**网页端不支持**；且 Android 上开图像流会与
///    录像互斥。现实做法是「低频抓帧」（例如取景时每 500ms 抓一张）
///    而不是逐帧推理。
library;

import 'dart:typed_data';
import 'dart:ui' show Offset;

/// 眼睛定位结果。坐标一律**归一化到 0..1**（左上为原点），
/// 这样与预览分辨率解耦。
typedef PetEyeResult = ({
  /// 左眼中心（画面坐标）。
  Offset left,

  /// 右眼中心（画面坐标）。
  Offset right,

  /// 置信度 0..1。低于阈值时上层应当忽略本次结果。
  double confidence,
});

/// 宠物眼睛定位器。
///
/// 实现方需保证：**任何异常都不得向外抛**——取景界面不能因为
/// 一次检测失败而中断。
abstract class PetEyeDetector {
  /// 是否已就绪（模型已加载）。未就绪时上层会跳过调用。
  bool get isAvailable;

  /// 从一帧图像里定位宠物眼睛；定位不到返回 null。
  ///
  /// [frame] 为 RGBA8 缓冲区。
  Future<PetEyeResult?> detect(
    Uint8List frame, {
    required int width,
    required int height,
  });
}

/// 模型未就位时的空实现。
///
/// 行为等价于"没有眼睛坐标"，上层会自然退回「用户点选位置 / 画面中心」。
/// 用空对象而不是 nullable，是为了让上层不用到处写 `if (detector != null)`。
class NoPetEyeDetector implements PetEyeDetector {
  const NoPetEyeDetector();

  @override
  bool get isAvailable => false;

  @override
  Future<PetEyeResult?> detect(
    Uint8List frame, {
    required int width,
    required int height,
  }) async => null;
}

/// 眼睛的选择策略（纯逻辑，可单测）。
class PetEyeTargeting {
  PetEyeTargeting._();

  /// 置信度低于此值时视为不可用——宁可退回画面中心，
  /// 也不要对焦到一个"猜"出来的点上。
  static const double minConfidence = 0.35;

  /// 选出应当对焦的那只眼睛。
  ///
  /// 没有深度信息可用时的通行启发：宠物低头看向镜头时，
  /// **离镜头更近的那只眼在画面里位置更低（y 更大）**。
  /// 宠物摄影的第一原则是「眼神 > 构图」，所以必须锁定一只明确的眼睛，
  /// 而不是把对焦点放在两眼中间——中间通常是鼻梁，最容易跑焦。
  static Offset? nearestEye(PetEyeResult? result) {
    if (result == null) return null;
    if (result.confidence < minConfidence) return null;
    return result.left.dy >= result.right.dy ? result.left : result.right;
  }

  /// 两只眼睛的外接矩形（归一化），供"眼睛增强"限定作用范围。
  ///
  /// 向外扩 [pad] 是为了把眼周也包进去——只提亮瞳点会显得很假。
  static RectLike? eyeRegion(PetEyeResult? result, {double pad = 0.10}) {
    if (result == null || result.confidence < minConfidence) return null;
    final minX = (result.left.dx < result.right.dx
            ? result.left.dx
            : result.right.dx) -
        pad;
    final maxX = (result.left.dx > result.right.dx
            ? result.left.dx
            : result.right.dx) +
        pad;
    final minY = (result.left.dy < result.right.dy
            ? result.left.dy
            : result.right.dy) -
        pad;
    final maxY = (result.left.dy > result.right.dy
            ? result.left.dy
            : result.right.dy) +
        pad;
    return RectLike(minX.clamp(0.0, 1.0), minY.clamp(0.0, 1.0),
        maxX.clamp(0.0, 1.0), maxY.clamp(0.0, 1.0));
  }
}

/// 一个不依赖 Flutter 的最小矩形（归一化坐标），
/// 便于在纯逻辑测试里断言，也方便后续跨 isolate 传递。
class RectLike {
  const RectLike(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  @override
  bool operator ==(Object other) =>
      other is RectLike &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'RectLike(${left.toStringAsFixed(2)}, ${top.toStringAsFixed(2)}, '
      '${right.toStringAsFixed(2)}, ${bottom.toStringAsFixed(2)})';
}
