// 条件导入的兜底实现：io / web 条件都不满足时使用，行为同 Web。
import 'dart:typed_data';

import 'photo_storage.dart';

final Set<String> _hiddenUrls = <String>{};

Future<String?> save(Uint8List bytes, {DateTime? takenAt}) async => null;

Future<void> delete(DateTime takenAt) async {}

// 兜底实现同 Web：不支持动态照片，空实现让上层无需分支。
Future<String?> saveLive(Uint8List bytes, {required DateTime takenAt}) async =>
    null;

Future<void> deleteLive(DateTime takenAt) async {}

Future<List<SavedPhoto>> loadAll() async => const [];

Future<void> clearAll() async {}

Future<Set<String>> loadHiddenUrls() async => {..._hiddenUrls};

Future<void> hideUrl(String url) async {
  if (url.isNotEmpty) _hiddenUrls.add(url);
}
