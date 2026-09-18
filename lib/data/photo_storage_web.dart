// Web 端实现：无 dart:io，落盘能力不可用，全部 no-op。
//
// Web 端照片仍靠云端 works.json 兜底（上传成功后刷新可从服务端拉回）；
// 上传失败时照片仅在当前会话内存中可见——这是 Web 平台的固有限制。
// 「已删除的云端照片」用内存集合记录，刷新页面后失效（Web 无本地文件）。
import 'dart:typed_data';

import 'photo_storage.dart';

final Set<String> _hiddenUrls = <String>{};

Future<String?> save(Uint8List bytes, {DateTime? takenAt}) async => null;

Future<void> delete(DateTime takenAt) async {}

// 动态照片：camera_web 的视频录制能力受浏览器限制，Web 端不提供
// （相册里也不会出现 LIVE 角标），空实现让上层代码无需分支。
Future<String?> saveLive(Uint8List bytes, {required DateTime takenAt}) async =>
    null;

Future<void> deleteLive(DateTime takenAt) async {}

Future<List<SavedPhoto>> loadAll() async => const [];

Future<void> clearAll() async {}

Future<Set<String>> loadHiddenUrls() async => {..._hiddenUrls};

Future<void> hideUrl(String url) async {
  if (url.isNotEmpty) _hiddenUrls.add(url);
}
