import 'dart:typed_data';

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
  int get durationMs => videoBytes == null
      ? slides.length * secondsPerSlide * 1000
      : videoDurationMs;

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
      throw ArgumentError('最多8张照片，单张2～4秒，视频最长30秒');
    }
    if (videoBytes != null && videoDurationMs > 30000) {
      throw ArgumentError('视频片段最长30秒');
    }
  }
}

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
