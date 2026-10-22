import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'movie_export.dart';

const _channel = MethodChannel('yuanbao/movie_export');

Future<MovieExportResult> exportMovie(MovieExportRequest request) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    throw UnsupportedError('桌面端请在浏览器预览并导出，手机端支持MP4导出');
  }
  final root = await getTemporaryDirectory();
  final dir = await Directory('${root.path}/movie_').createTemp();
  Future<String> put(String name, Uint8List data) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(data, flush: true);
    return f.path;
  }

  try {
    final slides = <String>[];
    for (var i = 0; i < request.slides.length; i++) {
      slides.add(await put('slide_$i.png', request.slides[i]));
    }
    final output = '${dir.path}/movie.mp4';
    final result = await _channel
        .invokeMethod<String>('export', {
          'slides': slides,
          'seconds_per_slide': request.secondsPerSlide,
          'video_path': request.videoBytes == null
              ? null
              : await put(
                  'input.${request.videoExtension}',
                  request.videoBytes!,
                ),
          'trim_start_ms': request.trimStartMs,
          'duration_ms': request.durationMs,
          'segments': request.videoSegments.map((s) => s.toMap()).toList(),
          'subject_fill': request.subjectFill,
          'focus_x': request.focusX,
          'focus_y': request.focusY,
          'zoom': request.zoom,
          'overlay_path': request.overlay == null
              ? null
              : await put('overlay.png', request.overlay!),
          'music_path': request.musicBytes == null
              ? null
              : await put(
                  'music.${request.musicExtension}',
                  request.musicBytes!,
                ),
          'mute_original': request.muteOriginal,
          'output_path': output,
        })
        .timeout(const Duration(minutes: 3));
    if (result != output) throw StateError('导出未返回有效文件');
    final f = File(output);
    if (!await f.exists() || await f.length() == 0) {
      throw StateError('视频文件为空，请重试');
    }
    return MovieExportResult(
      await f.readAsBytes(),
      'video/mp4',
      request.durationMs,
    );
  } on TimeoutException {
    await _channel.invokeMethod<void>('cancel');
    throw StateError('导出超时，请缩短片段后重试');
  } on MissingPluginException {
    throw UnsupportedError('此安装包尚不含视频导出组件，请安装更新后的版本');
  } finally {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

Future<List<MotionSample>> analyzeMovie(
  Uint8List bytes,
  String extension, {
  required int startMs,
  required int durationMs,
  double focusX = .5,
  double focusY = .5,
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    throw UnsupportedError('请在浏览器或手机分析视频');
  }
  final root = await getTemporaryDirectory();
  final dir = await Directory('${root.path}/motion_').createTemp();
  try {
    final f = File('${dir.path}/input.$extension');
    await f.writeAsBytes(bytes, flush: true);
    final samples = await _channel
        .invokeListMethod<dynamic>('analyze', {
          'video_path': f.path,
          'start_ms': startMs,
          'duration_ms': durationMs,
          'focus_x': focusX,
          'focus_y': focusY,
        })
        .timeout(const Duration(seconds: 60));
    return (samples ?? []).map((m) => MotionSample.fromMap(m as Map)).toList();
  } finally {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
