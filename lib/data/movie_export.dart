import 'dart:typed_data';
import 'pet_movie_edit.dart';
export 'pet_movie_edit.dart';

import 'movie_export_stub.dart'
    if (dart.library.io) 'movie_export_io.dart'
    if (dart.library.html) 'movie_export_web.dart'
    as platform;

/// Already rendered, bounded PNG slides; no generative service is involved.
class MovieExportRequest {
  const MovieExportRequest({
    this.slides = const [],
    this.secondsPerSlide = 3,
    this.videoBytes,
    this.videoExtension = 'mp4',
    this.trimStartMs = 0,
    this.videoDurationMs = 10000,
    this.overlay,
    this.musicBytes,
    this.musicExtension = 'mp3',
    this.muteOriginal = false,
    this.segments = const [],
    this.subjectFill = false,
    this.focusX = .5,
    this.focusY = .5,
    this.zoom = 1,
  });

  final List<Uint8List> slides;
  final int secondsPerSlide;
  final Uint8List? videoBytes;
  final String videoExtension;
  final int trimStartMs;
  final int videoDurationMs;
  final Uint8List? overlay;
  final Uint8List? musicBytes;
  final String musicExtension;
  final bool muteOriginal;
  final List<MovieSegment> segments;
  final bool subjectFill;
  final double focusX, focusY, zoom;
  int get durationMs => videoBytes == null
      ? slides.length * secondsPerSlide * 1000
      : segments.isEmpty
      ? videoDurationMs
      : segments.fold(0, (n, s) => n + s.outputMs);
  List<MovieSegment> get videoSegments => segments.isEmpty
      ? [MovieSegment(trimStartMs, trimStartMs + videoDurationMs)]
      : segments;

  void validate() {
    if ((videoBytes != null) == slides.isNotEmpty) {
      throw ArgumentError('请选择一组照片或一段视频');
    }
    if (slides.length > 8 ||
        durationMs <= 0 ||
        durationMs > 40000 ||
        secondsPerSlide < 2 ||
        secondsPerSlide > 4 ||
        trimStartMs < 0) {
      throw ArgumentError('最多8张照片，单张2～4秒；成片最长40秒，慢放时请缩短片段');
    }
    if (videoBytes != null && videoDurationMs > 30000) {
      throw ArgumentError('视频片段最长30秒');
    }
    if (!focusX.isFinite ||
        !focusY.isFinite ||
        !zoom.isFinite ||
        focusX < 0 ||
        focusX > 1 ||
        focusY < 0 ||
        focusY > 1 ||
        zoom < 1 ||
        zoom > 2) {
      throw ArgumentError('主体构图参数无效');
    }
    if (segments.length > 8 || (videoBytes == null && segments.isNotEmpty)) {
      throw ArgumentError('剪辑片段无效');
    }
    var lastEnd = 0;
    for (final s in segments) {
      if (s.startMs < trimStartMs ||
          s.startMs < lastEnd ||
          s.endMs <= s.startMs ||
          s.endMs > trimStartMs + videoDurationMs ||
          ![.25, .5, 1.0].contains(s.speed)) {
        throw ArgumentError('片段顺序、范围或速度无效');
      }
      lastEnd = s.endMs;
    }
  }
}

Future<List<MotionSample>> analyzeMovie(
  Uint8List bytes,
  String extension, {
  required int startMs,
  required int durationMs,
  double focusX = .5,
  double focusY = .5,
}) => platform.analyzeMovie(
  bytes,
  extension,
  startMs: startMs,
  durationMs: durationMs,
  focusX: focusX,
  focusY: focusY,
);

class MovieExportResult {
  const MovieExportResult(this.bytes, this.mimeType, this.durationMs);
  final Uint8List bytes;
  final String mimeType;
  final int durationMs;
  String get extension => mimeType.contains('mp4') ? 'mp4' : 'webm';
}

Future<MovieExportResult> exportMovie(MovieExportRequest request) {
  request.validate();
  return platform.exportMovie(request);
}
