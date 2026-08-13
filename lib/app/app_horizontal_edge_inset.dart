import 'package:flutter/material.dart';
import 'package:pet_camera/app/tokens.dart';

/// 横向内容首尾留白组件。
/// 用首尾占位的方式替代列表 padding，统一保留左右 16 的视觉留白。
class AppHorizontalEdgeInset extends StatelessWidget {
  const AppHorizontalEdgeInset({
    super.key,
    required this.child,
    this.edgeWidth = AppUi.pagePadding,
  });

  final Widget child;
  final double edgeWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: edgeWidth),
        child,
        SizedBox(width: edgeWidth),
      ],
    );
  }
}

/// 横向滚动容器。
/// 当它放在已有页面横向 padding 的区域里时，可通过 `parentHorizontalPadding`
/// 把滚动视口向外扩回整屏宽度，避免“页面 padding + 首尾占位”叠成双份边距。
class AppHorizontalEdgeScroll extends StatelessWidget {
  const AppHorizontalEdgeScroll({
    super.key,
    required this.child,
    this.edgeWidth = AppUi.pagePadding,
    this.parentHorizontalPadding = 0,
    this.physics = const BouncingScrollPhysics(),
    this.height,
  });

  final Widget child;
  final double edgeWidth;
  final double parentHorizontalPadding;
  final ScrollPhysics physics;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final scrollView = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: physics,
      child: AppHorizontalEdgeInset(edgeWidth: edgeWidth, child: child),
    );

    // 没有外层横向 padding 时，直接返回普通横向滚动即可。
    if (parentHorizontalPadding == 0) {
      return scrollView;
    }

    // 已有外层 padding 时，通过固定高度 + Stack 向两侧扩展滚动视口，
    // 避免横向内容被裁剪，同时保持组件自身高度稳定。
    if (height != null) {
      return SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -parentHorizontalPadding,
              right: -parentHorizontalPadding,
              top: 0,
              bottom: 0,
              child: scrollView,
            ),
          ],
        ),
      );
    }

    return Transform.translate(
      offset: Offset(-parentHorizontalPadding, 0),
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        child: scrollView,
      ),
    );
  }
}
