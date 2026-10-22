import 'movie_export.dart';
import 'dart:typed_data';

Future<MovieExportResult> exportMovie(MovieExportRequest request) async =>
    throw UnsupportedError('当前平台不支持视频导出，请使用手机或新版Chrome/Edge');

Future<List<MotionSample>> analyzeMovie(
  Uint8List bytes,
  String extension, {
  required int startMs,
  required int durationMs,
  double focusX = .5,
  double focusY = .5,
}) async => throw UnsupportedError('当前平台不能分析视频');
