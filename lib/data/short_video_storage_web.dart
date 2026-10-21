import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';

Future<String> store(String name, Uint8List bytes) async {
  await Hive.box('shortVideoBytes').put(name, bytes);
  return name;
}

Future<Uint8List> read(String ref) async {
  final value = Hive.box('shortVideoBytes').get(ref);
  if (value == null) throw StateError('本地视频文件已被清理');
  return value is Uint8List
      ? value
      : Uint8List.fromList(List<int>.from(value as List));
}

Future<void> remove(String ref) => Hive.box('shortVideoBytes').delete(ref);
