import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

/// 滤镜预设：ColorFilter.matrix 需要 20 个 double（4x5，末列是偏移）。
/// 全部为马卡龙友好色调，不碰紫粉渐变。
class _Filter {
  const _Filter(this.name, this.matrix);
  final String name;
  final List<double> matrix;
}

const kFilters = <_Filter>[
  _Filter('原图', [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]),
  _Filter('暖阳', [
    1.10,
    0,
    0,
    0,
    0.05,
    0,
    1.00,
    0,
    0,
    0,
    0,
    0,
    0.90,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
  _Filter('冷调', [
    0.90,
    0,
    0,
    0,
    0,
    0,
    1.00,
    0,
    0,
    0,
    0,
    0,
    1.10,
    0,
    0.05,
    0,
    0,
    0,
    1,
    0,
  ]),
  _Filter('复古', [
    0.393,
    0.769,
    0.189,
    0,
    0,
    0.349,
    0.686,
    0.168,
    0,
    0,
    0.272,
    0.534,
    0.131,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
  _Filter('清新', [
    1.08,
    0,
    0,
    0,
    0.02,
    0,
    1.08,
    0,
    0,
    0.02,
    0,
    0,
    1.08,
    0,
    0.02,
    0,
    0,
    0,
    1,
    0,
  ]),
  _Filter('黑白', [
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
];

/// 背景预设：马卡龙单色，不用渐变（规避 P0-2 紫粉渐变）。
class _Bg {
  const _Bg(this.name, this.color);
  final String name;
  final Color? color; // null = 透明（画布显示白底）
}

const kBgs = <_Bg>[
  _Bg('无', null),
  _Bg('薰衣草', Color(0xFFF0EBFA)),
  _Bg('薄荷', Color(0xFFD6EEF5)),
  _Bg('蜜桃', Color(0xFFFFE4DD)),
  _Bg('奶油', Color(0xFFF5F0E0)),
];

/// 贴纸：用 Lucide 图标（禁 emoji），可拖动、长按删除。
class Sticker {
  Sticker(this.icon, this.x, this.y, this.size, this.color);
  final IconData icon;
  double x;
  double y;
  final double size;
  final Color color;
}

/// 贴纸面板可选图标 + 默认色（均为 Lucide，非 emoji）。
const kStickerIcons = <(IconData, Color)>[
  (LucideIcons.heart, Color(0xFFE8607D)),
  (LucideIcons.star, Color(0xFFF2B705)),
  (LucideIcons.pawPrint, Color(0xFF9B8AC4)),
  (LucideIcons.bone, Color(0xFFB0A88F)),
  (LucideIcons.flower2, Color(0xFFE58FA8)),
  (LucideIcons.crown, Color(0xFFE0B341)),
  (LucideIcons.sparkles, Color(0xFF7FC4C4)),
  (LucideIcons.smile, Color(0xFFF2A65A)),
];
