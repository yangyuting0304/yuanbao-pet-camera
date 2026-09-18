import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'photo_storage.dart';

/// 用户拍摄的照片（切片2：拍照后存入应用内相册）。
class CapturedPhoto {
  const CapturedPhoto({
    required this.bytes,
    required this.takenAt,
    this.url,
    this.livePath,
  });

  final Uint8List bytes;
  final DateTime takenAt;

  /// COS 公网地址（可选）。保存时已上传到对象存储则带出。
  final String? url;

  /// 动态照片的短片**文件路径**（原生端拍摄且开启动态照片时才有）。
  ///
  /// 只存路径不存字节：短片体积是照片的 2~3 倍，全部常驻内存会拖垮 App。
  /// 播放时交给 video_player 直接读文件，零拷贝。
  final String? livePath;

  bool get hasLive => livePath != null;
}

/// 拍摄照片状态：最新拍摄排在列表最前。
///
/// 持久化策略：原生端每张成片同步落盘（应用文档目录，见 [PhotoStorage]），
/// 启动时回填——保证「上传失败 / 未配置代理」时照片重启也不丢；
/// Web 端 [PhotoStorage] 为空实现，行为同旧版（依赖云端 works.json 兜底）。
///
/// 照片与磁盘文件的对应关系靠 [CapturedPhoto.takenAt]（毫秒时间戳）：
/// 落盘文件名即由它生成，删除时按同一时间戳定位，无需额外索引。
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
        ...saved.map(
          (s) => CapturedPhoto(
            bytes: s.bytes,
            takenAt: s.takenAt,
            livePath: s.livePath,
          ),
        ),
      ];
    } catch (_) {
      // 回填失败只影响历史照片展示。
    }
  }

  /// 返回**新照片实例**：动态短片的录制是拍照之后异步进行的，录完要凭它
  /// 精确找回这张照片（见 [attachLive]）。
  ///
  /// 为什么用实例而不返回时间戳：`DateTime.now()` 只精确到毫秒，紧挨着的
  /// 两次拍摄可能撞在同一毫秒——那样就会把短片挂到相邻那张照片上。
  /// （这个边界由 test/live_photo_attach_test.dart 抓到过。）
  CapturedPhoto add(Uint8List bytes, {String? url}) {
    // 拍摄时间只在这里生成一次，并原样交给落盘：文件名与列表项的 time
    // 必须完全一致，否则删除时按时间戳找不到对应文件。
    final takenAt = DateTime.now();
    final photo = CapturedPhoto(bytes: bytes, takenAt: takenAt, url: url);
    state = [photo, ...state];
    // 原生端落盘（Web 为 no-op）。失败不影响本次会话的内存展示。
    unawaited(PhotoStorage.save(bytes, takenAt: takenAt));
    return photo;
  }

  /// 给刚拍的照片补上动态短片路径（录制完成后调用）。
  ///
  /// 按**实例身份**定位并替换：录制耗时 2 秒，期间用户可能又拍了新照片，
  /// 列表下标已经变了，不能用下标定位（同毫秒撞车的问题见 [add]）。
  void attachLive(CapturedPhoto target, String path) {
    // 先判断是否还在列表里：照片可能已被用户在录制那 2 秒里删掉，
    // 此时短片是永远访问不到的孤儿文件，直接清理。
    if (!state.any((p) => identical(p, target))) {
      unawaited(PhotoStorage.deleteLive(target.takenAt));
      return;
    }
    state = [
      for (final p in state)
        if (identical(p, target))
          CapturedPhoto(
            bytes: p.bytes,
            takenAt: p.takenAt,
            url: p.url,
            livePath: path,
          )
        else
          p,
    ];
  }

  /// 删除一张本地拍摄照片（内存 + 磁盘）。
  ///
  /// 用 `identical` 精确删除那一个实例，避免同一毫秒拍摄的极端情况下
  /// 误删相邻项。
  void remove(CapturedPhoto photo) {
    final before = state.length;
    state = state.where((p) => !identical(p, photo)).toList();
    if (state.length == before) return;
    unawaited(PhotoStorage.delete(photo.takenAt));
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

/// 已被用户删除的云端照片 URL 集合（本地屏蔽）。
///
/// 云端（COS + works.json）没有删除接口，所以用户删掉的云端照片记在这里，
/// 相册合并数据时过滤掉——在 App 内看不见即等于删掉。
/// 原生端持久化到磁盘（重启仍生效），Web 端仅当前会话有效。
class HiddenPhotoUrlsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _restore();
    return const {};
  }

  Future<void> _restore() async {
    try {
      final urls = await PhotoStorage.loadHiddenUrls();
      if (urls.isNotEmpty) state = {...state, ...urls};
    } catch (_) {
      // 读取失败最多让已删照片重新出现，不影响使用。
    }
  }

  Future<void> hide(String url) async {
    if (url.isEmpty || state.contains(url)) return;
    state = {...state, url};
    await PhotoStorage.hideUrl(url);
  }
}

final hiddenPhotoUrlsProvider =
    NotifierProvider<HiddenPhotoUrlsNotifier, Set<String>>(
      HiddenPhotoUrlsNotifier.new,
    );
