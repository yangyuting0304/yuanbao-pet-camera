import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 「动态照片」开关的持久化读写（对应 iOS：设置 → 相机 → 保留设置 → 实况照片）。
///
/// 复用 Hive 的 `appSettings` box 存一个 bool。读写都包在 try 里——
/// Hive 初始化失败时（见 main.dart 的降级）整体退化为内存态，不影响使用。
abstract final class LivePhotoPrefs {
  static const String boxName = 'appSettings';
  static const String _key = 'livePhotoEnabled';

  static bool get enabled {
    try {
      return Hive.box(boxName).get(_key, defaultValue: true) as bool;
    } catch (_) {
      // 读不到就当开着——与 iOS 默认开启实况照片的行为一致。
      return true;
    }
  }

  static Future<void> setEnabled(bool value) async {
    try {
      await Hive.box(boxName).put(_key, value);
    } catch (_) {
      // 写失败只影响下次启动的默认值，不影响本次会话。
    }
  }
}

/// 动态短片的时长（秒）。
///
/// 苹果 Live Photo 录的是按下快门**前后**各约 1.5 秒。本项目录的是
/// **拍照完成后**的 2 秒，原因是取舍：
/// 拍照走多帧融合（连拍期间独占相机会话，无法并行抓帧流），
/// 二者同时开启必然导致拍照失败。所以选择保画质，短片只覆盖"之后"。
const int liveClipSeconds = 2;

/// 动态照片开关：开启后每次拍照自动附带一小段短片，相册里长按即可播放。
class LivePhotoNotifier extends Notifier<bool> {
  @override
  bool build() => LivePhotoPrefs.enabled;

  Future<void> setEnabled(bool value) async {
    if (state == value) return;
    state = value;
    await LivePhotoPrefs.setEnabled(value);
  }
}

final livePhotoEnabledProvider = NotifierProvider<LivePhotoNotifier, bool>(
  LivePhotoNotifier.new,
);
