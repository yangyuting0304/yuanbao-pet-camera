// 原生端实现：应用文档目录 / captured_photos/。
//
// 文件名自带毫秒时间戳（cap_<millis>.jpg），拍摄时间从文件名反解，
// 不需要额外索引文件；时间戳字符串等长，字典序 = 时间序。
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'photo_storage.dart';

/// 最多回填的历史照片数。
///
/// 每张成片 1~3MB，全部读进内存会拖慢启动并放大占用；
/// 超出部分保留在磁盘上（云端 works.json 仍可展示）。
const int _maxRestore = 200;

Future<Directory> _photosDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}${Platform.pathSeparator}captured_photos');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

Future<String?> save(Uint8List bytes) async {
  try {
    final dir = await _photosDir();
    final name = 'cap_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return name;
  } catch (_) {
    return null;
  }
}

Future<List<SavedPhoto>> loadAll() async {
  try {
    final dir = await _photosDir();
    if (!dir.existsSync()) return const [];
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.jpg'))
            .toList()
          // 文件名等长毫秒时间戳：倒序即最新在前。
          ..sort((a, b) => b.path.compareTo(a.path));
    final taken = <SavedPhoto>[];
    for (final f in files.take(_maxRestore)) {
      try {
        taken.add(
          SavedPhoto(
            fileName: f.uri.pathSegments.last,
            bytes: await f.readAsBytes(),
            takenAt: _takenAtOf(f),
          ),
        );
      } catch (_) {
        // 单个文件损坏只跳过它自己，不中断其余照片的回填。
      }
    }
    return taken;
  } catch (_) {
    return const [];
  }
}

DateTime _takenAtOf(File f) {
  final name = f.uri.pathSegments.last; // cap_<millis>.jpg
  final millis = int.tryParse(name.substring(4, name.length - 4));
  if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
  return f.statSync().modified; // 非命名规范的文件退回文件修改时间。
}

Future<void> clearAll() async {
  try {
    final dir = await _photosDir();
    if (!dir.existsSync()) return;
    await for (final entity in dir.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {
          // 单个文件删除失败不中断清理。
        }
      }
    }
  } catch (_) {
    // 清理失败保持静默：与"失败不阻断主流程"的原则一致。
  }
}
