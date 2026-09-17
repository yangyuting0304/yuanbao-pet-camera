import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'photo_storage.dart';

/// 用户拍摄的照片（切片2：拍照后存入应用内相册）。
class CapturedPhoto {
  const CapturedPhoto({required this.bytes, required this.takenAt, this.url});

  final Uint8List bytes;
  final DateTime takenAt;

  /// COS 公网地址（可选）。保存时已上传到对象存储则带出。
  final String? url;
}

/// 拍摄照片状态：最新拍摄排在列表最前。
///
/// 持久化策略：原生端每张成片同步落盘（应用文档目录，见 [PhotoStorage]），
/// 启动时回填——保证「上传失败 / 未配置代理」时照片重启也不丢；
/// Web 端 [PhotoStorage] 为空实现，行为同旧版（依赖云端 works.json 兜底）。
class CapturedPhotosNotifier extends Notifier<List<CapturedPhoto>> {
  @override
  List<CapturedPhoto> build() {
    // 回填不阻塞首帧：先给空列表，磁盘照片就绪后并入。
    _restoreFromDisk();
    return const [];
  }

  /// 启动回填。失败静默降级为空列表，绝不影响本次会话的新拍照片。
  Future<void> _restoreFromDisk() async {
    try {
      final saved = await PhotoStorage.loadAll();
      if (saved.isEmpty) return;
      // 回填是异步的：若期间用户已拍新照，跳过回填，避免覆盖最新状态。
      // （窗口仅启动后数十毫秒，实际竞态概率可忽略。）
      if (state.isNotEmpty) return;
      state = [
        ...saved.map((s) => CapturedPhoto(bytes: s.bytes, takenAt: s.takenAt)),
      ];
    } catch (_) {
      // 回填失败只影响历史照片展示。
    }
  }

  void add(Uint8List bytes, {String? url}) {
    state = [
      CapturedPhoto(bytes: bytes, takenAt: DateTime.now(), url: url),
      ...state,
    ];
    // 原生端落盘（Web 为 no-op）。失败不影响本次会话的内存展示。
    unawaited(PhotoStorage.save(bytes));
  }

  void clear() {
    state = const [];
    unawaited(PhotoStorage.clearAll());
  }
}

final capturedPhotosProvider =
    NotifierProvider<CapturedPhotosNotifier, List<CapturedPhoto>>(
      CapturedPhotosNotifier.new,
    );
