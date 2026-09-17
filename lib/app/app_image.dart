import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'mingcute_icons.dart';
import 'tokens.dart';

/// 统一的远程图片组件。
///
/// 种子图已外置到对象存储（见 SeedConfig），全站图片统一经本组件加载：
/// - 加载中：显示与卡片同色系的占位底色，避免闪烁
/// - 失败：显示重试图标，点击即重新加载
///
/// 注意：不提供任何本地兜底资源，避免安装包体积回弹。
class AppImage extends StatefulWidget {
  const AppImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth,
    this.alignment = Alignment.center,
    this.placeholderColor = const Color(0xFFF8F6F3),
  });

  /// 图片远程地址。
  final String url;

  final BoxFit fit;
  final double? width;
  final double? height;

  /// 加载失败/加载中占位的对齐方式，也用于图片内容对齐。
  final Alignment alignment;

  /// 解码宽度限制，用于列表缩略图降低内存占用（不改变网络下载大小）。
  final int? memCacheWidth;

  /// 占位底色，默认与照片卡片同色系。
  final Color placeholderColor;

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  int _retryKey = 0;

  void _retry() => setState(() => _retryKey += 1);

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      // key 变化即触发重新加载，用于实现「重试」。
      key: ValueKey<int>(_retryKey),
      imageUrl: widget.url,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      memCacheWidth: widget.memCacheWidth,
      alignment: widget.alignment,
      placeholder: (_, __) => ColoredBox(color: widget.placeholderColor),
      errorWidget: (_, __, ___) => _RetryPlaceholder(
        onRetry: _retry,
        backgroundColor: widget.placeholderColor,
      ),
    );
  }
}

/// 加载失败占位：居中重试图标，点击整块区域即重试。
class _RetryPlaceholder extends StatelessWidget {
  const _RetryPlaceholder({
    required this.onRetry,
    required this.backgroundColor,
  });

  final VoidCallback onRetry;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRetry,
      child: ColoredBox(
        color: backgroundColor,
        child: Center(
          child: MingCuteIcon(
            MingCuteIcons.refresh2Line,
            color: context.tokens.textSecondary,
            size: AppUi.iconMedium,
            semanticLabel: '加载失败，点击重试',
          ),
        ),
      ),
    );
  }
}
