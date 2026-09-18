/// 宠物引诱音效播放服务。
///
/// 音效引诱是零技术门槛、零 AI 成本却最直接提升出片率的功能——
/// 宠物不看镜头是废片的头号原因，而声音能把它们的注意力拉回来。
///
/// 播放策略：
///  - 单例播放器，切音效时先停再放，避免多路叠音
///  - 支持循环（拍动态时持续引诱）与音量调节（避免吓到宠物/扰民）
///  - 任何异常都静默吞掉：放不出声不该影响拍照主流程
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'pet_capture_profile.dart';

class LureSoundPlayer {
  AudioPlayer? _player;

  /// 当前正在播放的音效；null 表示空闲。
  LureSound? _current;

  /// 是否循环播放。
  bool _looping = false;

  double _volume = 0.7;

  LureSound? get current => _current;
  bool get isPlaying => _current != null;
  bool get looping => _looping;
  double get volume => _volume;

  /// 播放指定音效。[loop] 为 true 时循环，用于持续把宠物注意力拉住。
  Future<void> play(LureSound sound, {bool loop = false}) async {
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.setReleaseMode(
        loop ? ReleaseMode.loop : ReleaseMode.release,
      );
      await player.setVolume(_volume);
      await player.play(_sourceOf(sound));
      _current = sound;
      _looping = loop;
    } catch (e) {
      // 放不出声不是致命问题：拍照功能必须继续可用。
      debugPrint('[音效] 播放失败 ${sound.asset}：$e');
      _current = null;
    }
  }

  /// 同一个音效再次点击则停止，否则切到新音效。
  Future<void> toggle(LureSound sound) async {
    if (_current == sound) {
      await stop();
    } else {
      await play(sound);
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {
      // 忽略：停止失败不影响使用
    }
    _current = null;
  }

  /// 调整音量（0..1）。宠物躲避高频音，默认不要拉满。
  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    try {
      await _player?.setVolume(_volume);
    } catch (_) {}
  }

  /// audioplayers 的 [AssetSource] 默认以 `assets/` 为前缀，
  /// 这里把资源声明用的完整路径（`assets/sounds/x.wav`）转成相对路径。
  AssetSource _sourceOf(LureSound sound) {
    final path = sound.assetPath;
    return AssetSource(
      path.startsWith('assets/') ? path.substring('assets/'.length) : path,
    );
  }

  void dispose() {
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
    _current = null;
  }
}

/// 各物种推荐的默认音量。
///
/// 猫和龙猫听觉更敏感、也更易惊，默认给低一档。
double defaultVolumeFor(PetSpecies species) {
  switch (species) {
    case PetSpecies.cat:
      return 0.55;
    case PetSpecies.chinchilla:
      return 0.50;
    case PetSpecies.rabbit:
      return 0.60;
    case PetSpecies.dog:
      return 0.75;
    case PetSpecies.fish:
      // 鱼没有引诱音效（水下的声音对鱼意义不大且可能惊缸），
      // 这里只是把音量旋钮留在中位，等真的接音效时再调。
      return 0.60;
  }
}
