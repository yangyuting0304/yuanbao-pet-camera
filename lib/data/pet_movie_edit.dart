import 'dart:math' as math;

/// A source interval with a real playback-speed change (no generated frames).
class MovieSegment {
  const MovieSegment(this.startMs, this.endMs, {this.speed = 1});
  final int startMs, endMs;
  final double speed;
  int get outputMs => ((endMs - startMs) / speed).round();
  Map<String, Object> toMap() => {
    'start_ms': startMs,
    'end_ms': endMs,
    'speed': speed,
  };
}

/// Keep context, slow the marked expression, return to normal speed.
List<MovieSegment> momentRecipe(
  int cueMs,
  int sourceStart,
  int sourceEnd, {
  double speed = .5,
}) {
  final cue = cueMs.clamp(sourceStart, sourceEnd);
  final start = math.max(sourceStart, cue - 1800);
  final end = math.min(sourceEnd, cue + 2200);
  final slowStart = math.max(start, cue - 450);
  final slowEnd = math.min(end, cue + 750);
  return [
    if (slowStart > start) MovieSegment(start, slowStart),
    if (slowEnd > slowStart) MovieSegment(slowStart, slowEnd, speed: speed),
    if (end > slowEnd) MovieSegment(slowEnd, end),
  ];
}

/// Normalized crop in the already oriented source image.
({double x, double y, double width, double height}) subjectCrop(
  double width,
  double height,
  double focusX,
  double focusY,
  double zoom,
) {
  final aspect = 9 / 16;
  final w = math.min(width, height * aspect) / zoom;
  final h = w / aspect;
  return (
    x: (focusX * width - w / 2).clamp(0, width - w) / width,
    y: (focusY * height - h / 2).clamp(0, height - h) / height,
    width: w / width,
    height: h / height,
  );
}

class MotionSample {
  const MotionSample(this.timeMs, this.motion, this.sharpness, this.brightness);
  final int timeMs;
  final double motion, sharpness, brightness;
  factory MotionSample.fromMap(Map m) => MotionSample(
    (m['time_ms'] as num).round(),
    (m['motion'] as num).toDouble(),
    (m['sharpness'] as num).toDouble(),
    (m['brightness'] as num).toDouble(),
  );
}

/// A heuristic candidate, never a claim of feline blink recognition.
MotionSample? bestActionMoment(List<MotionSample> samples) {
  final usable = samples
      .where((s) => s.brightness > 18 && s.brightness < 238 && s.sharpness > 2)
      .toList();
  if (usable.isEmpty) return null;
  final maxMotion = usable.map((s) => s.motion).reduce(math.max);
  if (maxMotion < 1.5) return null;
  final maxSharp = usable.map((s) => s.sharpness).reduce(math.max);
  usable.sort((a, b) {
    double score(MotionSample s) =>
        .65 * (s.motion / maxMotion) + .35 * (s.sharpness / maxSharp);
    return score(b).compareTo(score(a));
  });
  return usable.first;
}
