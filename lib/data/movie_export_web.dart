// Browser encodes an actual video locally with Canvas + MediaRecorder.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:js_interop';
import 'movie_export.dart';

@JS('yuanbaoExportMovie')
external JSPromise<_MovieJsResult> _encode(JSString request);

extension type _MovieJsResult(JSObject _) implements JSObject {
  external JSString get base64;
  external JSString get mimeType;
}

Future<MovieExportResult> exportMovie(MovieExportRequest request) async {
  final result = await _encode(jsonEncode({
    'slides': request.slides.map(base64Encode).toList(),
    'secondsPerSlide': request.secondsPerSlide,
    'video': request.videoBytes == null ? null : base64Encode(request.videoBytes!),
    'videoExtension': request.videoExtension,
    'trimStartMs': request.trimStartMs,
    'durationMs': request.durationMs,
    'overlay': request.overlay == null ? null : base64Encode(request.overlay!),
    'music': request.musicBytes == null ? null : base64Encode(request.musicBytes!),
    'muteOriginal': request.muteOriginal,
  }).toJS).toDart;
  return MovieExportResult(base64Decode(result.base64.toDart), result.mimeType.toDart, request.durationMs);
}
