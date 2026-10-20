// 离线滤镜实验台（本地工具，不进 App）。
// 用法：dart run tools/filter_lab/preview.dart <in.jpg> <outDir> [variant...]
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:pet_camera/data/pet_capture_profile.dart';
import 'package:pet_camera/data/pet_filter.dart';

class Variant {
  const Variant(this.name, this.label, this.overrides, this.useSubject);
  final String name;
  final String label;
  final Map<String, double> overrides;
  final bool useSubject;
}

const List<Variant> variants = [
  Variant('current', '当前默认（无主体框）', {}, false),
  Variant('subject', '当前默认 + 主体框', {}, true),
  Variant('soft', '收敛锐化', {'clarity': 0.03, 'textureStrength': 0.06}, true),
  Variant('flat', '不锐化只降噪', {
    'clarity': 0.0,
    'textureStrength': 0.0,
    'noiseReduction': 0.5,
  }, true),
  Variant('noclarity', '只关 clarity', {'clarity': 0.0}, true),
  Variant('notex', '只关毛发质感', {'textureStrength': 0.0}, true),
];

({double left, double top, double right, double bottom})? subjectBox(
  String which,
) {
  if (which == 'cat1') {
    return (left: 0.30, top: 0.33, right: 0.97, bottom: 0.70);
  }
  if (which == 'cat2') {
    return (left: 0.20, top: 0.18, right: 0.80, bottom: 0.86);
  }
  return null;
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('用法: preview.dart <in.jpg> <outDir> [variant...]');
    exit(1);
  }
  final input = File(args[0]);
  final outDir = Directory(args[1])..createSync(recursive: true);
  final wanted = args.length > 2 ? args.sublist(2) : <String>['current'];
  final base = PetCaptureProfile.resolve(
    species: PetSpecies.cat,
    coat: PetCoat.tabby,
    scene: PetScene.portrait,
    look: PetLook.natural,
  );
  final stem = input.path.split(RegExp(r'[/\\]')).last.replaceAll('.jpg', '');
  final bytes = input.readAsBytesSync();
  final src = img.decodeImage(bytes)!;
  final srcRgba = src.getBytes(order: img.ChannelOrder.rgba);
  final baseLap = lapVar(src);
  stdout.writeln('原图 ${src.width}x${src.height} 锐度=$baseLap');

  for (final v in variants.where((v) => wanted.contains(v.name))) {
    final o = v.overrides;
    final noise = o['noiseReduction'] ?? base.noiseReduction;
    final req = (
      bytes: bytes,
      exposure: 0.0,
      tempShift: base.tempShift,
      shadowLift: base.shadowLift,
      highlightRolloff: base.highlightRolloff,
      clarity: o['clarity'] ?? base.clarity,
      noiseReduction: noise,
      chromaDenoise: noise * PetFilterKernel.chromaDenoiseScale,
      vignette: base.vignette,
      saturation: base.saturation,
      vibrance: base.vibrance,
      grain: base.grain,
      texture: o['textureStrength'] ?? PetCaptureProfile.furTextureStrength,
      eyeEnhance: base.eyeEnhance ? PetCaptureProfile.eyeEnhanceStrength : 0.0,
      tearStain: base.tearStainFix ? PetCaptureProfile.tearStainStrength : 0.0,
      maxSide: PetFilter.defaultMaxSide,
      jpegQuality: PetFilter.defaultJpegQuality,
      subjectRect: v.useSubject ? subjectBox(stem) : null,
    );
    final out = runPetFilter(req);
    File('${outDir.path}/$stem-${v.name}.jpg').writeAsBytesSync(out);
    final dec = img.decodeImage(out)!;
    final outRgba = dec.getBytes(order: img.ChannelOrder.rgba);
    final outLap = lapVar(dec);
    final d = deltaStats(src, dec);
    stdout.writeln('${v.name}  ${v.label}');
    stdout.writeln(
      '   全图锐度比=${(outLap / baseLap).toStringAsFixed(3)} '
      '改动=${(d.changed * 100).toStringAsFixed(1)}% '
      '过冲=${(d.big * 100).toStringAsFixed(2)}% '
      '最大=${d.max.toStringAsFixed(0)}',
    );
    final box = subjectBox(stem);
    if (box != null) {
      final sIn = lapVar(
        src,
        l: box.left,
        t: box.top,
        r: box.right,
        b: box.bottom,
      );
      final sOut = lapVar(
        dec,
        l: box.left,
        t: box.top,
        r: box.right,
        b: box.bottom,
      );
      final bIn = lapVar(src, excludeBox: box);
      final bOut = lapVar(dec, excludeBox: box);
      stdout.writeln(
        '   主体区锐度比=${(sOut / sIn).toStringAsFixed(3)} '
        '背景区锐度比=${(bOut / bIn).toStringAsFixed(3)}',
      );
    }
  }
}

/// 拉普拉斯方差，可限定在归一化矩形内；[outside] 为 true 时取框外区域。
double lapVar(
  img.Image src, {
  double l = 0,
  double t = 0,
  double r = 1,
  double b = 1,
  ({double left, double top, double right, double bottom})? excludeBox,
}) {
  final w = src.width;
  final h = src.height;
  final rgba = src.getBytes(order: img.ChannelOrder.rgba);
  final x0 = (l * w).floor().clamp(1, w - 2);
  final x1 = (r * w).ceil().clamp(x0 + 1, w - 1);
  final y0 = (t * h).floor().clamp(1, h - 2);
  final y1 = (b * h).ceil().clamp(y0 + 1, h - 1);
  final box = excludeBox;
  var sum = 0.0;
  var sq = 0.0;
  var n = 0;
  for (var y = y0; y < y1; y += 2) {
    for (var x = x0; x < x1; x += 2) {
      if (box != null) {
        final nx = x / w;
        final ny = y / h;
        final inBox =
            nx >= box.left &&
            nx <= box.right &&
            ny >= box.top &&
            ny <= box.bottom;
        if (inBox) continue; // excludeBox：只统计框外区域
      }
      final o = (y * w + x) * 4;
      double lum(int p) =>
          0.2126 * rgba[p] + 0.7152 * rgba[p + 1] + 0.0722 * rgba[p + 2];
      final lap =
          4 * lum(o) -
          lum(o - 4) -
          lum(o + 4) -
          lum(o - w * 4) -
          lum(o + w * 4);
      sum += lap;
      sq += lap * lap;
      n++;
    }
  }
  if (n == 0) return 1;
  final mean = sum / n;
  return math.max(1e-6, sq / n - mean * mean);
}

({double changed, double big, double max}) deltaStats(
  img.Image a,
  img.Image b,
) {
  final ra = a.getBytes(order: img.ChannelOrder.rgba);
  final rb = b.getBytes(order: img.ChannelOrder.rgba);
  final n = math.min(ra.length, rb.length) ~/ 4;
  var changed = 0;
  var big = 0;
  var max = 0.0;
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    final d =
        ((ra[o] - rb[o]).abs() +
                (ra[o + 1] - rb[o + 1]).abs() +
                (ra[o + 2] - rb[o + 2]).abs()) /
            3;
    if (d > 1) changed++;
    if (d > 12) big++;
    if (d > max) max = d.toDouble();
  }
  return (changed: changed / n, big: big / n, max: max);
}
