/// 相机画质地基 & 平台能力探测。
///
/// 这里解决两个问题：
///
/// **1. 画质天花板**——`ResolutionPreset.medium` 只有约 480p，
///    是"拍得不如系统相机"最直接的原因。这里按平台给出更好的档位，
///    并提供**降级链**：高分辨率初始化失败时自动退到下一档，
///    而不是直接把「相机启动失败」甩给用户。
///
/// **2. 平台能力差异**——`camera_web` 官方未实现曝光模式/曝光点/曝光补偿、
///    对焦模式/对焦点、传感器方向、帧流。在网页端直接调用这些 API 会抛
///    `PlatformException`。这里用「先判断、再调用、失败即记住」的策略，
///    保证网页端不崩、原生端功能完整。
library;

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Offset;

/// 拍摄画质档位。
///
/// 网页端整体降一档：浏览器里高分辨率视频流的内存与带宽开销明显更敏感。
enum CaptureQuality {
  standard('标准', ResolutionPreset.high, ResolutionPreset.medium, '省内存，适合低配机 / 弱网'),
  high('高清', ResolutionPreset.veryHigh, ResolutionPreset.high, '日常推荐（约 1080p / 网页 720p）'),
  ultra('超清', ResolutionPreset.max, ResolutionPreset.veryHigh, '画质优先，占内存大');

  const CaptureQuality(this.label, this._nativePreset, this._webPreset, this.hint);

  final String label;
  final ResolutionPreset _nativePreset;
  final ResolutionPreset _webPreset;

  /// 给用户看的说明。
  final String hint;

  /// 当前平台的首选预设。
  ResolutionPreset get preset => kIsWeb ? _webPreset : _nativePreset;

  /// 真正交给 [CameraController] 的预设（按平台封顶）。
  ///
  /// 与 [preset] 的唯一差别是 iOS 上「超清」从 `max` 降到 `veryHigh`，
  /// 原因见 [_iosUltraPreset]。
  ResolutionPreset get effectivePreset {
    if (kIsWeb) return _webPreset;
    if (this == CaptureQuality.ultra &&
        defaultTargetPlatform == TargetPlatform.iOS) {
      return _iosUltraPreset;
    }
    return _nativePreset;
  }

  /// iOS 上「超清」实际使用的预设。
  ///
  /// **为什么 iOS 不用 `ResolutionPreset.max`**（实测「点快门闪退回桌面」）：
  ///
  /// camera_avfoundation 对 `.max` 的处理不是"提高一点"，而是把
  /// `AVCaptureDevice.activeFormat` 换成**像素最高的 format**，并让
  /// `AVCapturePhotoSettings.maxPhotoDimensions` 取该 format 支持的最大值。
  /// 在 iPhone 14 Pro Max / 15 这类机型上那就是**全尺寸 48MP**。
  /// 而本App 的出片链路是纯 Dart 逐像素处理：
  /// 连拍（多张 JPEG 字节同时在手）→ 融合（`img.decodeImage` 全尺寸解码，
  /// 48MP 单帧 RGBA ≈ 192MB）→ 滤镜 → 比例合成。三四张就会顶穿 iOS 的
  /// 进程内存上限，被系统**直接杀掉**（jetsam）——现象就是按快门瞬间退回桌面。
  ///
  /// `veryHigh` 对应 iPhone 系统相机默认的 12MP（4032×3024）量级，画质与
  /// 系统相机持平，而像素数只有全尺寸的 1/4、峰值内存降到 1/16。
  /// 「比系统相机好看」靠的是毛色自适应曝光、多帧融合降噪与毛发质感，
  /// 不靠堆像素——用命换像素不划算。
  static ResolutionPreset get _iosUltraPreset => ResolutionPreset.veryHigh;

  /// 降级链：从本档位往低尝试，最多 3 档。
  ///
  /// 用于初始化失败时逐级重试，避免一次失败就完全拍不了照。
  ///
  /// 起点必须是 [effectivePreset] 而不是 [preset]：iOS 上「超清」被封顶到
  /// `veryHigh`，若从 `max` 起步，第一档就是会被 jetsam 杀掉的全尺寸格式。
  List<ResolutionPreset> get fallbackChain {
    final all = ResolutionPreset.values; // low → max，画质递增
    final start = all.indexOf(effectivePreset);
    final end = (start - 2).clamp(0, all.length - 1);
    return [
      for (var i = start; i >= end; i--) all[i],
    ];
  }
}

/// 相机硬件参数能力：探测 + 安全应用。
///
/// 用法：所有硬件参数调用都走这里，返回 `bool` 表示是否真的生效。
/// 网页端会直接短路返回 `false`（不发原生调用、不抛异常）；
/// 原生端首次失败后会记住该能力不可用，后续跳过以免反复抛异常。
class CameraCapability {
  CameraCapability({this.verbose = false});

  /// 是否打印降级日志（排查用）。
  final bool verbose;

  // 三态能力缓存：null = 尚未探测，true/false = 已知。
  bool? _exposureOk;
  bool? _focusOk;
  bool? _zoomOk;
  bool? _flashOk;

  /// 曝光控制（测光点 / 曝光补偿 / 曝光模式）是否可用。
  bool get exposureSupported => _exposureOk ?? !kIsWeb;

  /// 对焦控制（对焦点 / 对焦模式）是否可用。
  bool get focusSupported => _focusOk ?? !kIsWeb;

  /// 缩放是否可用。
  bool get zoomSupported => _zoomOk ?? true;

  /// 闪光灯是否可用。
  bool get flashSupported => _flashOk ?? true;

  /// 设备支持的曝光补偿范围（仅在原生上尝试获取过一次后缓存）。
  double _minEv = -2.0;
  double _maxEv = 2.0;

  /// 把传入的 EV 夹到设备支持范围内。
  double clampEv(double ev) => ev.clamp(_minEv, _maxEv);

  /// 探测设备支持的曝光补偿范围。失败则保留保守默认值。
  Future<void> probeExposureRange(CameraController controller) async {
    if (kIsWeb) return;
    try {
      final min = await controller.getMinExposureOffset();
      final max = await controller.getMaxExposureOffset();
      if (min.isFinite && max.isFinite && max > min) {
        _minEv = min;
        _maxEv = max;
      }
    } catch (_) {
      // 保持默认范围即可
    }
  }

  /// 应用测光点 + 曝光补偿。
  ///
  /// [focusPoint] 为归一化坐标（0..1，相对预览画面）。
  /// 返回是否生效。
  Future<bool> applyExposure(
    CameraController controller, {
    Offset? point,
    double? ev,
  }) async {
    if (!exposureSupported) return false;
    try {
      if (point != null) {
        await controller.setExposurePoint(point);
      }
      if (ev != null) {
        // 先解锁曝光模式，否则部分机型上曝光补偿不生效。
        await controller.setExposureMode(ExposureMode.auto);
        await controller.setExposureOffset(clampEv(ev));
      }
      _exposureOk = true;
      return true;
    } catch (e) {
      _exposureOk = false;
      _log('曝光控制不可用，已降级：$e');
      return false;
    }
  }

  /// 应用对焦点。
  ///
  /// 注意：`camera` 插件的 `FocusMode` 只有 `auto` / `locked` 两个值，
  /// 没有独立的「连续对焦」档；绝大多数设备上 `auto` 本身就是连续对焦，
  /// 因此这里不再区分连续/单次——差异靠上层"是否持续重设对焦点"来实现。
  Future<bool> applyFocus(
    CameraController controller, {
    Offset? point,
  }) async {
    if (!focusSupported) return false;
    try {
      await controller.setFocusMode(FocusMode.auto);
      if (point != null) {
        await controller.setFocusPoint(point);
      }
      _focusOk = true;
      return true;
    } catch (e) {
      _focusOk = false;
      _log('对焦控制不可用，已降级：$e');
      return false;
    }
  }

  /// 设置缩放倍数，自动夹到设备范围。
  Future<bool> applyZoom(CameraController controller, double zoom) async {
    if (!zoomSupported) return false;
    try {
      final maxZoom = await controller.getMaxZoomLevel();
      final minZoom = await controller.getMinZoomLevel();
      await controller.setZoomLevel(zoom.clamp(minZoom, maxZoom));
      _zoomOk = true;
      return true;
    } catch (e) {
      _zoomOk = false;
      _log('缩放不可用：$e');
      return false;
    }
  }

  /// 设置闪光灯。注意：猫 / 兔 / 龙猫等物种应传入 [FlashMode.off]。
  Future<bool> applyFlash(CameraController controller, FlashMode mode) async {
    if (!flashSupported) return false;
    try {
      await controller.setFlashMode(mode);
      _flashOk = true;
      return true;
    } catch (e) {
      _flashOk = false;
      _log('闪光灯不可用：$e');
      return false;
    }
  }

  void _log(String message) {
    if (verbose) debugPrint('[相机能力] $message');
  }
}
