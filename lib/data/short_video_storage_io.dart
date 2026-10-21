import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<String> store(String name, Uint8List bytes) async {
  final root = await getApplicationDocumentsDirectory();
  final dir = await Directory(
    '${root.path}/short_videos',
  ).create(recursive: true);
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}

Future<Uint8List> read(String ref) => File(ref).readAsBytes();
Future<void> remove(String ref) async {
  final f = File(ref);
  if (await f.exists()) await f.delete();
}
