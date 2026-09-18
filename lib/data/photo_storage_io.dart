// 原生端实现：应用文档目录 / captured_photos/。
//
// 文件名自带毫秒时间戳（cap_<millis>.jpg），拍摄时间从文件名反解，
// 不需要额外索引文件；时间戳字符串等长，字典序 = 时间序。
// 已删除的云端照片 URL 记在 hidden_urls.txt（每行一个）。
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'photo_storage.dart';

/// 最多回填的历史照片数。
///
/// 每张成片 1~3MB，全部读进内存会拖慢启动并放大占用；
/// 超出部分保留在磁盘上（云端 works.json 仍可展示）。
const int _maxRestore = 200;

/// 云端照片屏蔽表文件名。
const String _hiddenFile = 'hidden_urls.txt';

Future<Directory> _photosDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}${Platform.pathSeparator}captured_photos');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

File _photoFile(Directory dir, DateTime takenAt) => File(
  '${dir.path}${Platform.pathSeparator}'
  'cap_${takenAt.millisecondsSinceEpoch}.jpg',
);

/// 动态照片短片文件（同一毫秒时间戳，扩展名 mp4）。
///
/// 扩展名不同是关键：[loadAll] 只挑 `.jpg`，短片不会被误当成照片回填。
File _liveFile(Directory dir, DateTime takenAt) => File(
  '${dir.path}${Platform.pathSeparator}'
  'live_${takenAt.millisecondsSinceEpoch}.mp4',
);

Future<String?> save(Uint8List bytes, {DateTime? takenAt}) async {
  try {
    final dir = await _photosDir();
    final at = takenAt ?? DateTime.now();
    final file = _photoFile(dir, at);
    await file.writeAsBytes(bytes, flush: true);
    return file.uri.pathSegments.last;
  } catch (_) {
    return null;
  }
}

Future<void> delete(DateTime takenAt) async {
  try {
    final dir = await _photosDir();
    final file = _photoFile(dir, takenAt);
    if (file.existsSync()) await file.delete();
    // 动态短片随照片一起删，避免留下永远访问不到的孤儿文件占空间。
    await deleteLive(takenAt);
  } catch (_) {
    // 删除失败静默：照片可能本就没落盘（如 Web 端或权限异常）。
  }
}

Future<String?> saveLive(Uint8List bytes, {required DateTime takenAt}) async {
  try {
    final dir = await _photosDir();
    final file = _liveFile(dir, takenAt);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<void> deleteLive(DateTime takenAt) async {
  try {
    final dir = await _photosDir();
    final file = _liveFile(dir, takenAt);
    if (file.existsSync()) await file.delete();
  } catch (_) {
    // 同上：清理失败不影响主流程。
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
        final at = _takenAtOf(f);
        final live = _liveFile(dir, at);
        taken.add(
          SavedPhoto(
            fileName: f.uri.pathSegments.last,
            bytes: await f.readAsBytes(),
            takenAt: at,
            // 只记路径、不读字节：短片体积可达照片的 2~3 倍，
            // 回填时把 200 段都读进内存会明显拖慢启动。
            livePath: live.existsSync() ? live.path : null,
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

Future<Set<String>> loadHiddenUrls() async {
  try {
    final dir = await _photosDir();
    final file = File('${dir.path}${Platform.pathSeparator}$_hiddenFile');
    if (!file.existsSync()) return const {};
    final lines = await file.readAsLines();
    return lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toSet();
  } catch (_) {
    return const {};
  }
}

Future<void> hideUrl(String url) async {
  if (url.isEmpty) return;
  try {
    final dir = await _photosDir();
    final file = File('${dir.path}${Platform.pathSeparator}$_hiddenFile');
    if (file.existsSync()) {
      final existing = await file.readAsLines();
      if (existing.any((l) => l.trim() == url)) return; // 已记录，避免重复行
    }
    await file.writeAsString('$url\n', mode: FileMode.append, flush: true);
  } catch (_) {
    // 记录失败时该照片会在下次启动"复活"，但不影响本次会话的删除体验。
  }
}
