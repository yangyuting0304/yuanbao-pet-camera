// 条件导入的兜底实现：io / web 条件都不满足时使用，行为同 Web（全 no-op）。
import 'dart:typed_data';

import 'photo_storage.dart';

Future<String?> save(Uint8List bytes) async => null;

Future<List<SavedPhoto>> loadAll() async => const [];

Future<void> clearAll() async {}
