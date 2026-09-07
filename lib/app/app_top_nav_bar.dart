import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pet_camera/app/mingcute_icons.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/task_center.dart';
import 'package:pet_camera/data/task_store.dart';

/// 通用顶部导航栏。
/// 统一首页和相册页的品牌 Logo、返回按钮和“我的”入口布局；
/// 在“我的”入口左侧按需展示「当前任务」入口（生成中 / 已生成未处理）。
class AppTopNavBar extends ConsumerWidget {
  const AppTopNavBar({super.key, required this.onOpenMine});

  final VoidCallback onOpenMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final task = ref.watch(taskCenterProvider).task;
    final entry = (task != null && task.stage.visibleInNav) ? task : null;
    return SizedBox(
      // 一级页面导航栏本体为 44，但内容区保持 36，避免视觉上显得更厚。
      height: 36,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              // 顶部品牌区统一使用 SVG Logo，保持首页和相册页一致。
              child: SizedBox(
                width: 96,
                height: 28,
                child: SvgPicture.asset(
                  'assets/brand/logo.svg',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          if (entry != null) ...[
            const SizedBox(width: AppUi.space12),
            _TaskEntryButton(
              task: entry,
              onTap: () => Navigator.pushNamed(context, '/ai-video-result'),
            ),
          ],
          const SizedBox(width: AppUi.space12),
          _MineEntryButton(onTap: onOpenMine, backgroundColor: t.brand),
        ],
      ),
    );
  }
}

/// 顶部“当前任务”入口。
/// - generating：下载图标 + 细圆环（轮询中）；
/// - succeeded：品牌黄底对勾 + 红点（生成成功未查看）；
/// - viewed：灰底对勾（已查看未保存，入口保留直到保存/下载/丢弃）。
class _TaskEntryButton extends StatelessWidget {
  const _TaskEntryButton({required this.task, required this.onTap});

  final PendingTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final generating = task.stage == TaskStage.generating;
    final succeeded = task.stage == TaskStage.succeeded;
    final containerColor = succeeded
        ? context.tokens.brand
        : (generating ? const Color(0xFFEFF1F4) : const Color(0xFFEFF1F4));
    final iconColor = succeeded
        ? Colors.black
        : (generating ? Colors.black : const Color(0xFF666666));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: containerColor,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (generating)
              // 生成中：下载图标外层套细圆环，表达「还在进行」。
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.tokens.textSecondary.withValues(alpha: 0.35),
                ),
              ),
            if (generating)
              const MingCuteIcon(
                MingCuteIcons.download,
                size: 16,
                color: Colors.black,
              )
            else
              Icon(
                Icons.check_circle,
                size: 20,
                color: iconColor,
              ),
            if (succeeded)
              // 未查看红点。
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF4E62),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 顶部“我的”入口。
/// 保持 36x36 黄色圆形按钮，放进 44 高度导航里做垂直居中。
class _MineEntryButton extends StatelessWidget {
  const _MineEntryButton({required this.onTap, required this.backgroundColor});

  final VoidCallback onTap;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const MingCuteIcon(
          MingCuteIcons.user3Fill,
          size: 24,
          color: Colors.black,
        ),
      ),
    );
  }
}
