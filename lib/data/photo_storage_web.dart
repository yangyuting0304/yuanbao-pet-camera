import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';
import 'photo_storage.dart';

Future<String?> save(Uint8List bytes, {DateTime? takenAt}) async {
  final key = (takenAt ?? DateTime.now()).millisecondsSinceEpoch.toString();
  await Hive.box('capturedPhotoBytes').put(key, bytes);
  return key;
}

Future<void> delete(DateTime takenAt) => Hive.box(
  'capturedPhotoBytes',
).delete(takenAt.millisecondsSinceEpoch.toString());
Future<String?> saveLive(Uint8List bytes, {required DateTime takenAt}) async =>
    null;
Future<void> deleteLive(DateTime takenAt) async {}
Future<List<SavedPhoto>> loadAll() async {
  final box = Hive.box('capturedPhotoBytes');
  final keys =
      box.keys
          .where((k) => int.tryParse('$k') != null)
          .map((e) => '$e')
          .toList()
        ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
  return keys
      .take(24)
      .map(
        (k) => SavedPhoto(
          fileName: k,
          bytes: Uint8List.fromList(List<int>.from(box.get(k) as List)),
          takenAt: DateTime.fromMillisecondsSinceEpoch(int.parse(k)),
        ),
      )
      .toList();
}

Future<void> clearAll() async {
  await Hive.box('capturedPhotoBytes').clear();
}

Future<Set<String>> loadHiddenUrls() async => Set<String>.from(
  Hive.box('capturedPhotoBytes').get('hidden', defaultValue: <String>[]),
);
Future<void> hideUrl(String url) async {
  final urls = await loadHiddenUrls();
  urls.add(url);
  await Hive.box('capturedPhotoBytes').put('hidden', urls.toList());
}
