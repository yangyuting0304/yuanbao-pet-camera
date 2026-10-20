// 拍照流程的落盘诊断日志。
//
// ## 为什么需要它
//
// iOS 上的 native 崩溃（AVFoundation 崩在拍照里）**拿不到 Dart 侧的日志** ——
// 进程直接被系统杀掉，控制台里的 print 全部随进程一起没了。用户能看到的
// 只有「按快门就退回桌面」，没有任何线索是崩在哪一步：
// 是 takePicture？是融合？是滤镜？还是相机会话重建？
//
// 所以这里把拍照流程的**关键步骤**写进应用文档目录下的滚动文件：
// 崩溃发生时最后一条记录就是崩的位置，下次打开 App 就能看到。
//
// 特点：
//   · 纯追加、不依赖任何平台 API（dart:io + path_provider）→ 原生端可用；
//   · 滚动保留最近 N 行，文件不会无限增长；
//   · 每行带时间戳与毫秒级相对偏移，方便对齐各步骤耗时；
//   · 写入是**同步**的（IO 很小，几百字节），换来的是"崩了就一定写进去"
//     ——异步写会丢最后几行，而那几行恰恰最关键。
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 诊断日志文件名（放在应用文档目录，用户可用「文件」App 取走）。
const String _logFileName = 'shot_diagnostics.log';

/// 最多保留的行数。
const int _maxLines = 200;

/// 记录一条诊断信息。
///
/// [step] 用固定的小词，便于 grep 与阅读，例如：
/// `takePicture.start` / `takePicture.end` / `fuse.start` / `filter.end`。
Future<void> logShotStep(String step, {String? detail}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$_logFileName');
    final stamp = DateTime.now().toIso8601String();
    final line = '$stamp  $step${detail == null ? '' : '  $detail'}';
    await file.writeAsString(
      '$line\n',
      mode: FileMode.append,
      flush: true,
    );
    await _trim(file);
  } catch (_) {
    // 诊断日志写不进去绝不能影响拍照主流程。
  }
}

/// 读回最近的诊断日志（倒序，最新的在前）。
///
/// 供设置页展示；读不到返回空列表。
Future<List<String>> readShotDiagnostics({int limit = 60}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$_logFileName');
    if (!file.existsSync()) return const [];
    final lines = await file.readAsLines();
    return lines.reversed.take(limit).toList(growable: false);
  } catch (_) {
    return const [];
  }
}

/// 清空诊断日志。
Future<void> clearShotDiagnostics() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$_logFileName');
    if (file.existsSync()) await file.delete();
  } catch (_) {
    // 清空失败无所谓。
  }
}

/// 裁剪文件，只留最近 [_maxLines] 行。
Future<void> _trim(File file) async {
  try {
    final length = await file.length();
    // 每行约 80 字节，超过阈值才动手，避免每次都读文件。
    if (length < _maxLines * 80) return;
    final lines = await file.readAsLines();
    if (lines.length <= _maxLines) return;
    final kept = lines.sublist(lines.length - _maxLines);
    await file.writeAsString('${kept.join('\n')}\n', flush: true);
  } catch (_) {
    // 裁剪失败无所谓，文件顶多长一点。
  }
}
