import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// MingCute 图标名常量。
/// 统一收口到这里，页面层只引用语义名，不直接写文件名。
abstract final class MingCuteIcons {
  static const String addLine = 'add-line';
  static const String album = 'album';
  static const String back2 = 'back-2';
  static const String book = 'book';
  static const String bowknotFill = 'bowknot-fill';
  static const String camera = 'camera';
  static const String cameraFill = 'camera-fill';
  static const String calendar = 'calendar';
  static const String celebrateFill = 'celebrate-fill';
  static const String classify3AiFill = 'classify-3-ai-fill';
  static const String clapperboard = 'clapperboard';
  static const String flashFill = 'flash-fill';
  static const String flashLine = 'flash-line';
  static const String film = 'film';
  static const String clipboard = 'clipboard';
  static const String delete2 = 'delete-2';
  static const String download = 'download';
  static const String forbidCircle = 'forbid-circle';
  static const String backgroundLine = 'background';
  static const String foldingFanFill = 'folding-fan-fill';
  static const String flower2 = 'flower-2';
  static const String heart = 'heart';
  static const String home1 = 'home-1';
  static const String home4Fill = 'home-4-filled';
  static const String injectionFill = 'injection-fill';
  static const String instagramFill = 'instagram-filled';
  static const String instrumentFill = 'instrument-fill';
  static const String layoutGrid = 'layout-grid';
  static const String leaf2Line = 'leaf-2';
  // 单独补一份更接近设计稿的返回箭头资源，保证视觉尺寸符合 24x24。
  static const String leftLine = 'left-line';
  static const String magic1Fill = 'magic-1-fill';
  static const String magic3Line = 'magic-3';
  static const String magic2 = 'magic-2';
  static const String music = 'music';
  static const String loading = 'loading';
  static const String palette = 'palette';
  static const String paletteFill = 'palette-fill';
  static const String pasterLine = 'paster';
  static const String paw = 'paw';
  static const String pawFill = 'paw-fill';
  static const String pause = 'pause';
  static const String paintBrushFill = 'paint-brush-fill';
  static const String pic2Fill = 'pic-2-fill';
  static const String pic2Line = 'pic-2-line';
  static const String picLine = 'pic-line';
  static const String picFill = 'pic-fill';
  static const String photoAlbum = 'photo-album';
  static const String play = 'play';
  static const String playCircle = 'play-circle';
  static const String playlist = 'playlist';
  static const String plus = 'plus';
  static const String refresh2Line = 'refresh-2-line';
  static const String rightLine = 'right-line';
  static const String rightSmall = 'right-small';
  static const String settings2 = 'settings-2';
  static const String settings2Line = 'settings-2-line';
  static const String settings3Line = 'settings-3';
  static const String sparkles = 'sparkles';
  static const String borderRadiusLine = 'border-radius';
  static const String roundLine = 'round';
  static const String squareLine = 'square';
  static const String tongueFill = 'tongue-fill';
  static const String aiLine = 'ai';
  static const String user1 = 'user-1';
  static const String user3Fill = 'user-3-fill';
  static const String videoFill = 'video-fill';
  static const String videoLine = 'video';
  static const String clapperboardLine = 'clapperboard-line';
  static const String warning = 'warning';
}

/// 基础 SVG 图标组件。
/// 这里会把外部传入尺寸自动归一到 16/20/24，避免页面层再次写散。
class MingCuteIcon extends StatelessWidget {
  const MingCuteIcon(
    this.name, {
    super.key,
    required this.color,
    this.size = 20,
    this.semanticLabel,
    this.fit = BoxFit.contain,
  });

  final String name;
  final Color color;
  final double size;
  final String? semanticLabel;
  final BoxFit fit;

  static const String _basePath = 'assets/icons/mingcute';

  static double normalizeSize(double size) {
    const allowed = <double>[16, 20, 24];
    var result = allowed.first;
    var minGap = (size - result).abs();
    for (final item in allowed.skip(1)) {
      final gap = (size - item).abs();
      if (gap < minGap) {
        result = item;
        minGap = gap;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final normalizedSize = normalizeSize(size);
    return SizedBox(
      width: normalizedSize,
      height: normalizedSize,
      child: SvgPicture.asset(
        '$_basePath/$name.svg',
        width: normalizedSize,
        height: normalizedSize,
        fit: fit,
        semanticsLabel: semanticLabel,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }
}

/// 圆形底片专用图标。
/// 不同 SVG 的留白不同，这里用缩放表做视觉校准，保证看起来大小一致。
class CirclePlateIcon extends StatelessWidget {
  const CirclePlateIcon({
    super.key,
    required this.name,
    required this.iconColor,
    required this.backgroundColor,
    this.plateSize = 32,
    this.iconSize = 16,
  });

  final String name;
  final Color iconColor;
  final Color backgroundColor;
  final double plateSize;
  final double iconSize;

  static const Map<String, double> _circleVisualScale = <String, double>{
    MingCuteIcons.album: 0.9,
    MingCuteIcons.book: 0.92,
    MingCuteIcons.bowknotFill: 0.94,
    MingCuteIcons.camera: 0.96,
    MingCuteIcons.cameraFill: 0.96,
    MingCuteIcons.celebrateFill: 0.94,
    MingCuteIcons.classify3AiFill: 0.92,
    MingCuteIcons.clapperboard: 0.9,
    MingCuteIcons.clipboard: 0.9,
    MingCuteIcons.backgroundLine: 0.94,
    MingCuteIcons.delete2: 0.9,
    MingCuteIcons.download: 0.9,
    MingCuteIcons.flashFill: 0.92,
    MingCuteIcons.flashLine: 0.92,
    MingCuteIcons.film: 0.9,
    MingCuteIcons.forbidCircle: 0.9,
    MingCuteIcons.foldingFanFill: 0.94,
    MingCuteIcons.heart: 0.95,
    MingCuteIcons.home1: 0.94,
    MingCuteIcons.home4Fill: 0.96,
    MingCuteIcons.injectionFill: 0.94,
    MingCuteIcons.instagramFill: 0.9,
    MingCuteIcons.instrumentFill: 0.94,
    MingCuteIcons.layoutGrid: 0.9,
    MingCuteIcons.loading: 0.92,
    MingCuteIcons.magic1Fill: 0.94,
    MingCuteIcons.magic3Line: 0.94,
    MingCuteIcons.magic2: 0.94,
    MingCuteIcons.music: 0.9,
    MingCuteIcons.paw: 1.02,
    MingCuteIcons.pause: 0.9,
    MingCuteIcons.paletteFill: 0.94,
    MingCuteIcons.pasterLine: 0.94,
    MingCuteIcons.squareLine: 0.92,
    MingCuteIcons.borderRadiusLine: 0.94,
    MingCuteIcons.roundLine: 0.94,
    MingCuteIcons.tongueFill: 0.94,
    MingCuteIcons.aiLine: 0.94,
    MingCuteIcons.pawFill: 1.02,
    MingCuteIcons.pic2Fill: 0.92,
    MingCuteIcons.videoFill: 0.9,
    MingCuteIcons.videoLine: 0.9,
    MingCuteIcons.clapperboardLine: 0.9,
    MingCuteIcons.paintBrushFill: 0.94,
    MingCuteIcons.picFill: 0.92,
    MingCuteIcons.photoAlbum: 0.9,
    MingCuteIcons.play: 0.88,
    MingCuteIcons.playCircle: 0.88,
    MingCuteIcons.playlist: 0.9,
    MingCuteIcons.plus: 0.92,
    MingCuteIcons.refresh2Line: 0.92,
    MingCuteIcons.settings2: 0.9,
    MingCuteIcons.sparkles: 0.92,
    MingCuteIcons.user1: 0.92,
    MingCuteIcons.warning: 0.9,
  };

  @override
  Widget build(BuildContext context) {
    final visualScale = _circleVisualScale[name] ?? 1;
    return Container(
      width: plateSize,
      height: plateSize,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Transform.scale(
        scale: visualScale,
        child: MingCuteIcon(name, size: iconSize, color: iconColor),
      ),
    );
  }
}
