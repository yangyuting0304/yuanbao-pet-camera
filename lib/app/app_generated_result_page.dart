import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:pet_camera/app/app_back_button.dart';
import 'package:pet_camera/app/app_primary_action_button.dart';
import 'package:pet_camera/app/tokens.dart';

typedef AppResultSaveCallback = Future<void> Function();

/// 通用生成结果页。
/// 统一“毛孩写真”和“AI 编辑”的结果展示与底部保存按钮样式。
class AppGeneratedResultPage extends StatefulWidget {
  const AppGeneratedResultPage({
    super.key,
    required this.resultBytes,
    required this.onSave,
    this.demo = false,
    this.title = '生成结果',
    this.actionLabel = '保存到相册',
    this.actionIcon = LucideIcons.download,
    this.demoText = '演示模式 · 未接入真实 API',
  });

  final Uint8List resultBytes;
  final AppResultSaveCallback onSave;
  final bool demo;
  final String title;
  final String actionLabel;
  final IconData actionIcon;
  final String demoText;

  @override
  State<AppGeneratedResultPage> createState() => _AppGeneratedResultPageState();
}

class _AppGeneratedResultPageState extends State<AppGeneratedResultPage> {
  bool _saving = false;

  /// 保存成功后先提示，再自动返回上一页。
  Future<void> _handleSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存到相册')));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 44,
        leading: AppBackButton(onTap: () => Navigator.of(context).pop()),
        centerTitle: true,
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: AppUi.fontTitle,
            height: AppUi.lineHeight(AppUi.fontTitle),
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: t.surface,
        foregroundColor: t.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      bottomNavigationBar: AppPrimaryActionIconBottomBar(
        label: widget.actionLabel,
        icon: widget.actionIcon,
        onPressed: _handleSave,
        isLoading: _saving,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppUi.radiusCard),
            child: Image.memory(widget.resultBytes, fit: BoxFit.cover),
          ),
          if (widget.demo) ...[
            const SizedBox(height: 8),
            Text(
              widget.demoText,
              style: TextStyle(
                fontSize: AppUi.fontCaption,
                color: t.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
