import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/movie_export.dart';

void main() {
  test('marked expression keeps context and really expands slow interval', () {
    final segments = momentRecipe(2500, 0, 5000);
    expect(segments.map((s) => s.startMs), [700, 2050, 3250]);
    expect(segments.map((s) => s.endMs), [2050, 3250, 4700]);
    expect(segments.map((s) => s.speed), [1, .5, 1]);
    expect(segments.fold<int>(0, (n, s) => n + s.outputMs), 5200);
    expect(
      momentRecipe(0, 0, 1000).every((s) => s.startMs >= 0 && s.endMs <= 1000),
      isTrue,
    );
  });
  test('source duration and encoded duration cannot be confused', () {
    final r = MovieExportRequest(
      videoBytes: Uint8List(1),
      videoDurationMs: 1000,
      segments: const [MovieSegment(0, 1000, speed: .25)],
    );
    expect(r.durationMs, 4000);
    expect(r.validate, returnsNormally);
    expect(
      () => MovieExportRequest(
        videoBytes: Uint8List(1),
        videoDurationMs: 30000,
        segments: const [MovieSegment(0, 30000, speed: .25)],
      ).validate(),
      throwsArgumentError,
    );
    expect(
      () => MovieExportRequest(
        videoBytes: Uint8List(1),
        videoDurationMs: 3000,
        segments: const [MovieSegment(1000, 2000), MovieSegment(500, 1000)],
      ).validate(),
      throwsArgumentError,
    );
  });
  test('subject crop respects orientation, framing and image edges', () {
    final crop = subjectCrop(1920, 1080, 1, 0, 1);
    expect(crop.width / crop.height, closeTo((9 / 16) / (1920 / 1080), .0001));
    expect(crop.x + crop.width, closeTo(1, .0001));
    expect(crop.y, 0);
    final zoom = subjectCrop(1080, 1920, .5, .5, 2);
    expect(zoom.width, .5);
    expect(zoom.height, .5);
    expect(zoom.x, .25);
    expect(zoom.y, .25);
  });
  test(
    'motion heuristic rejects dark blur and still clips, never labels blinks',
    () {
      expect(bestActionMoment([const MotionSample(0, 0, 20, 100)]), isNull);
      expect(bestActionMoment([const MotionSample(0, 50, 30, 5)]), isNull);
      final choice = bestActionMoment([
        const MotionSample(1000, 10, 1, 100),
        const MotionSample(2000, 9, 30, 100),
        const MotionSample(3000, 2, 5, 100),
      ]);
      expect(choice?.timeMs, 2000);
    },
  );
}
