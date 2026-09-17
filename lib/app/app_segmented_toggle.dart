import 'package:flutter/material.dart';
import 'package:pet_camera/app/tokens.dart';

/// 通用左右切换胶囊。
/// 用于“分类 / 时间”这类二选一切换，统一圆角、尺寸和选中样式。
class AppSegmentedToggle extends StatelessWidget {
  const AppSegmentedToggle({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.rightSelected,
    required this.onSelectLeft,
    required this.onSelectRight,
  });

  final String leftLabel;
  final String rightLabel;
  final bool rightSelected;
  final VoidCallback onSelectLeft;
  final VoidCallback onSelectRight;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SegmentedToggleItem(
            label: leftLabel,
            selected: !rightSelected,
            onTap: onSelectLeft,
          ),
          const SizedBox(width: 1),
          _SegmentedToggleItem(
            label: rightLabel,
            selected: rightSelected,
            onTap: onSelectRight,
          ),
        ],
      ),
    );
  }
}

/// 单个切换项。
/// 只负责展示文字与当前选中态，避免页面层重复拼样式。
class _SegmentedToggleItem extends StatelessWidget {
  const _SegmentedToggleItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFEE35) : const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppUi.fontCaption,
            height: 20 / AppUi.fontCaption,
            fontWeight: FontWeight.w600,
            color: selected ? const Color(0xFF000000) : const Color(0xFFB4B4B4),
          ),
        ),
      ),
    );
  }
}
