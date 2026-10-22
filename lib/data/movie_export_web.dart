// Browser encodes an actual video locally with Canvas + MediaRecorder.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'movie_export.dart';

@JS('yuanbaoExportMovie')
external JSPromise<_MovieJsResult> _encode(JSString request);
@JS('yuanbaoAnalyzeMovie')
external JSPromise<JSString> _analyze(JSString request);

extension type _MovieJsResult(JSObject _) implements JSObject {
  external JSString get base64;
  external JSString get mimeType;
}

Future<MovieExportResult> exportMovie(MovieExportRequest request) async {
  final result = await _encode(
    jsonEncode({
      'slides': request.slides.map(base64Encode).toList(),
      'secondsPerSlide': request.secondsPerSlide,
      'video': request.videoBytes == null
          ? null
          : base64Encode(request.videoBytes!),
      'videoExtension': request.videoExtension,
      'trimStartMs': request.trimStartMs,
      'durationMs': request.durationMs,
      'segments': request.videoSegments.map((s) => s.toMap()).toList(),
      'subjectFill': request.subjectFill,
      'focusX': request.focusX,
      'focusY': request.focusY,
      'zoom': request.zoom,
      'overlay': request.overlay == null
          ? null
          : base64Encode(request.overlay!),
      'music': request.musicBytes == null
          ? null
          : base64Encode(request.musicBytes!),
      'muteOriginal': request.muteOriginal,
    }).toJS,
  ).toDart;
  return MovieExportResult(
    base64Decode(result.base64.toDart),
    result.mimeType.toDart,
    request.durationMs,
  );
}

Future<List<MotionSample>> analyzeMovie(
  Uint8List bytes,
  String extension, {
  required int startMs,
  required int durationMs,
  double focusX = .5,
  double focusY = .5,
}) async {
  final result = await _analyze(
    jsonEncode({
      'video': base64Encode(bytes),
      'videoExtension': extension,
      'startMs': startMs,
      'durationMs': durationMs,
      'focusX': focusX,
      'focusY': focusY,
    }).toJS,
  ).toDart;
  return (jsonDecode(result.toDart) as List)
      .map((m) => MotionSample.fromMap(m as Map))
      .toList();
}
