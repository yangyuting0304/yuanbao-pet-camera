// Web 端实现：无 dart:io，落盘能力不可用，全部 no-op。
//
// Web 端照片仍靠云端 works.json 兜底（上传成功后刷新可从服务端拉回）；
// 上传失败时照片仅在当前会话内存中可见——这是 Web 平台的固有限制。
import 'dart:typed_data';

import 'photo_storage.dart';

Future<String?> save(Uint8List bytes) async => null;

Future<List<SavedPhoto>> loadAll() async => const [];

Future<void> clearAll() async {}
