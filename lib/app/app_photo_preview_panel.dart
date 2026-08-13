import 'package:flutter/material.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/ai_portrait_service.dart';

/// 公共图片预览区。
/// 统一处理空状态、已选图片显示、点击选图入口，供 AI 写真和宠物 P 图共用。
class AppPhotoPreviewPanel extends StatelessWidget {
  const AppPhotoPreviewPanel({
    super.key,
    required this.source,
    required this.onTap,
    this.width,
    this.height,
    this.aspectRatio = 1,
    this.filledChild,
    this.emptyIcon = Icons.image_outlined,
    this.emptyIconName,
    this.emptyText = '请先选择照片',
    this.emptyBackgroundColor = const Color(0xFFF6F8FA),
    this.filledBackgroundColor = const Color(0xFFF6F8FA),
    this.clickableWhenFilled = true,
  });

  /// 当前选中的照片源。
  final SourcePhoto? source;

  /// 点击预览区后的回调。
  final VoidCallback onTap;

  /// 固定宽度；不传时按可用宽度铺开。
  final double? width;

  /// 固定高度；不传时用 aspectRatio 计算。
  final double? height;

  /// 未传 width/height 时使用的比例。
  final double aspectRatio;

  /// 已选照片后的自定义内容。
  /// 不传时默认直接显示选中的照片。
  final Widget? filledChild;

  /// 空状态图标。
  final IconData emptyIcon;

  /// 空状态 MingCute 图标名。
  /// 传入后优先使用，便于和全局 SVG 图标体系保持一致。
  final String? emptyIconName;

  /// 空状态文案。
  final String emptyText;

  /// 空状态背景色。
  final Color emptyBackgroundColor;

  /// 已选中时的背景色。
  final Color filledBackgroundColor;

  /// 选中后是否仍允许点击整块区域。
  final bool clickableWhenFilled;

  @override
  Widget build(BuildContext context) {
    final canTap = source == null || clickableWhenFilled;
    final panel = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: source == null ? emptyBackgroundColor : filledBackgroundColor,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
      ),
      clipBehavior: Clip.antiAlias,
      child: source == null ? _buildEmptyState(context) : _buildFilledState(),
    );

    final content = width != null && height != null
        ? panel
        : AspectRatio(aspectRatio: aspectRatio, child: panel);

    if (!canTap) {
      return content;
    }

    return GestureDetector(onTap: onTap, child: content);
  }

  /// 构建空状态展示。
  Widget _buildEmptyState(BuildContext context) {
    final t = context.tokens;
    final iconWidget = emptyIconName != null
        ? MingCuteIcon(emptyIconName!, size: 24, color: t.textSecondary)
        : Icon(emptyIcon, size: 32, color: t.textSecondary);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          const SizedBox(height: AppUi.space8),
          Text(
            emptyText,
            style: TextStyle(
              fontSize: AppUi.fontBody,
              height: AppUi.lineHeight(AppUi.fontBody),
              fontWeight: FontWeight.w400,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建已选中状态展示。
  Widget _buildFilledState() {
    if (filledChild != null) {
      return filledChild!;
    }

    if (source?.bytes != null) {
      return Image.memory(source!.bytes!, fit: BoxFit.cover);
    }

    return Image.asset(source!.assetPath!, fit: BoxFit.cover);
  }
}
