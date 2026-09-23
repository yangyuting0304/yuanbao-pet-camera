// 设置页。拆分自原 pages.dart（8631 行）。
//
// part of pages.dart —— 切分理由见 camera_page.dart 顶部说明。

part of 'pages.dart';

/// 设置页：外观（浅色/深色/系统）+ 数据清除 + 关于。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final mode = ref.watch(themeModeProvider);
    final liveOn = ref.watch(livePhotoEnabledProvider);
    return _Shell(
      title: '设置',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        children: [
          const _SettingsSectionTitle(title: '外观'),
          const SizedBox(height: 12),
          _ThemeModeTabs(
            selectedMode: mode,
            onChanged: (value) =>
                ref.read(themeModeProvider.notifier).setMode(value),
          ),
          const SizedBox(height: 24),
          const _SettingsSectionTitle(title: '拍摄'),
          const SizedBox(height: 12),
          _SettingsSwitchRow(
            title: '动态照片',
            // 说清与苹果的差异，避免用户按"前后各 1.5 秒"的预期来期待。
            subtitle: '拍照后自动记录 2 秒动态，在相册里长按照片即可播放',
            value: liveOn,
            onChanged: (v) =>
                ref.read(livePhotoEnabledProvider.notifier).setEnabled(v),
          ),
          const SizedBox(height: 24),
          const _SettingsSectionTitle(title: '数据'),
          const SizedBox(height: 12),
          _ActionRow(
            // 设置页缓存清理图标统一切到 MingCute 版本。
            icon: MingCuteIcons.pic2Line,
            title: '清除相册缓存',
            subtitle: '删除应用内拍摄的照片（不可恢复）',
            onTap: () => _confirmClear(
              context,
              '相册',
              () => ref.read(capturedPhotosProvider.notifier).clear(),
            ),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            icon: MingCuteIcons.clapperboardLine,
            title: '清除短片缓存',
            subtitle: '删除已保存的萌宠短片（不可恢复）',
            onTap: () => _confirmClear(
              context,
              '短片',
              () => ref.read(shortVideosProvider.notifier).clear(),
            ),
          ),
          const SizedBox(height: 24),
          const _SettingsSectionTitle(title: '关于'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 28,
                      child: SvgPicture.asset(
                        'assets/brand/logo.svg',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '版本 1.0.0',
                  style: TextStyle(
                    fontSize: AppUi.fontBody,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '为毛孩子记录每一刻 · 毛孩写真 · 毛孩相册 · 一键成片',
                  style: TextStyle(
                    fontSize: AppUi.fontBody,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: t.textTertiary,
                ),
                const SizedBox(height: 12),
                _AboutBeianLink(
                  text: BeianFooter.beianNumber,
                  url: BeianFooter.beianUrl,
                ),
                const SizedBox(height: 4),
                _AboutBeianLink(
                  text: BeianFooter.gonganNumber,
                  url: BeianFooter.gonganUrl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置页的开关行：左侧标题 + 说明，右侧 Switch。
///
/// 与 [_ActionRow] 的区别是它表达"持续生效的状态"而不是"一次性的动作"，
/// 所以用 Switch 而不是箭头——用户一眼能看出当前是开还是关。
class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppUi.fontBody,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: AppUi.fontCaption,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: t.brand,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 「设置 → 关于」里的备案号链接行：点击跳转工信部 / 公安备案查询平台。
class _AboutBeianLink extends StatelessWidget {
  const _AboutBeianLink({required this.text, required this.url});

  final String text;
  final String url;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppUi.fontCaption,
          color: t.textSecondary,
          decoration: TextDecoration.underline,
          decorationColor: t.textTertiary,
        ),
      ),
    );
  }
}

/// 清除缓存二次确认。
Future<void> _confirmClear(
  BuildContext context,
  String label,
  VoidCallback clear,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '清除$label缓存',
                style: const TextStyle(
                  fontSize: AppUi.fontHeadline,
                  height: 28 / AppUi.fontHeadline,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF000000),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '确认删除所有$label吗？清除后将无法恢复。',
                style: TextStyle(
                  fontSize: AppUi.fontBody,
                  height: AppUi.lineHeight(AppUi.fontBody),
                  fontWeight: FontWeight.w400,
                  color: context.tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _AppSecondaryActionButton(
                      label: '取消',
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppPrimaryActionButton(
                      label: '清除',
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  if (ok == true) {
    clear();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已清除$label缓存')));
    }
  }
}

/// 设置分区标题。
class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w400,
        color: t.textPrimary,
      ),
    );
  }
}

/// 设置页主题切换改成统一胶囊分段按钮，避免继续使用默认平台控件外观。
class _ThemeModeTabs extends StatelessWidget {
  const _ThemeModeTabs({required this.selectedMode, required this.onChanged});

  final ThemeMode selectedMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ThemeModeTabItem(
              label: '浅色',
              selected: selectedMode == ThemeMode.light,
              onTap: () => onChanged(ThemeMode.light),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ThemeModeTabItem(
              label: '深色',
              selected: selectedMode == ThemeMode.dark,
              onTap: () => onChanged(ThemeMode.dark),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ThemeModeTabItem(
              label: '系统',
              selected: selectedMode == ThemeMode.system,
              onTap: () => onChanged(ThemeMode.system),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeTabItem extends StatelessWidget {
  const _ThemeModeTabItem({
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
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: selected ? context.tokens.brand : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? context.tokens.brand : const Color(0xFFE2E4E6),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            height: 22 / 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF000000),
          ),
        ),
      ),
    );
  }
}

/// 设置操作行（图标 + 标题 + 副标题 + 右箭头）。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppUi.radiusCard),
          ),
          child: Row(
            children: [
              MingCuteIcon(icon, size: 20, color: const Color(0xFF000000)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppUi.fontBody,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: AppUi.fontCaption,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const MingCuteIcon(
                MingCuteIcons.rightLine,
                size: 20,
                color: Color(0xFF999999),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「我的创作」视频回放弹窗：应用内生成的视频预览。
class _CreatedVideoDialog extends StatefulWidget {
  const _CreatedVideoDialog({required this.work});
  final LibraryItem work;

  @override
  State<_CreatedVideoDialog> createState() => _CreatedVideoDialogState();
}

class _CreatedVideoDialogState extends State<_CreatedVideoDialog> {
  /// 预览弹窗最大宽度（与 build 里 ConstrainedBox 保持一致）。
  static const double _dialogMaxWidth = 360;

  /// 弹窗内容内边距。
  static const double _dialogPadding = 12;

  VideoPlayerController? _c;

  /// 原生端把远程视频整包下载后的本地临时文件路径（dispose 时释放）。
  String? _localUrl;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = widget.work.url;
    try {
      VideoPlayerController c;
      if (kIsWeb) {
        // Web：直接播放远程地址（<video> 无需 CORS）。
        c = VideoPlayerController.networkUrl(Uri.parse(url));
      } else if (url.startsWith('http://') || url.startsWith('https://')) {
        // 原生端：video_player 的 file 源只接受本地路径，且万相成片 mp4 的
        // moov 在文件尾，直接 networkUrl 拉 COS 会长时间缓冲。这里先整包
        // 下载到临时文件再本地播放（稳定秒开）。
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 60));
        if (resp.statusCode != 200) {
          throw Exception('视频下载失败（HTTP ${resp.statusCode}）');
        }
        final path = await MediaPlatform.createMediaUrl(
          resp.bodyBytes,
          'video/mp4',
        );
        _localUrl = path;
        c = MediaPlatform.videoController(path);
      } else {
        c = MediaPlatform.videoController(url);
      }
      _c = c;
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _ready = true;
        _error = null;
      });
      await c.play();
    } catch (e) {
      // 给出可见错误 + 重试，而不是无限转圈。
      if (mounted) {
        setState(() => _error = '视频打开失败：$e');
      }
    }
  }

  Future<void> _retry() async {
    _c?.dispose();
    _c = null;
    if (_localUrl != null) {
      await MediaPlatform.releaseMediaUrl(_localUrl!);
      _localUrl = null;
    }
    if (!mounted) return;
    setState(() {
      _ready = false;
      _error = null;
    });
    _init();
  }

  @override
  void dispose() {
    _c?.dispose();
    if (_localUrl != null) {
      MediaPlatform.releaseMediaUrl(_localUrl!);
    }
    super.dispose();
  }

  Widget _buildPreview() {
    final err = _error;
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                err,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppUi.fontCaption,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _retry,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white24,
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return _ready && _c != null && _c!.value.isInitialized
        ? Center(child: VideoPlayer(_c!))
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(color: Colors.white70),
                SizedBox(height: 12),
                Text(
                  '加载中…',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          );
  }

  /// 构建播放区：按视频真实宽高比自适应尺寸（contain），
  /// 横屏/竖屏视频都不会被固定 9:16 竖框拉伸。
  Widget _buildPlayerBox(BuildContext context) {
    final c = _c;
    final bool initialized = _ready && c != null && c.value.isInitialized;
    // 已初始化用真实比例；未就绪（加载中 / 出错）沿用竖屏占位比例。
    final double aspect = initialized && c.value.aspectRatio > 0
        ? c.value.aspectRatio
        : 9 / 16;

    final double screenHeight = MediaQuery.sizeOf(context).height;
    // 可用宽：弹窗上限宽度 - 两侧内边距。
    final double maxW = _dialogMaxWidth - _dialogPadding * 2;
    // 可用高：屏幕高度扣除弹窗上下 inset(24×2) 与弹窗内其它内容
    // （内边距 12×2 + 间距 12 + 底部按钮约 48），并限幅防止极端情况溢出。
    const double chromeHeight = 24 * 2 + _dialogPadding * 2 + 12 + 48;
    final double maxH = (screenHeight - chromeHeight)
        .clamp(160.0, _dialogMaxWidth * 16 / 9)
        .toDouble();

    // contain 语义：先铺满可用宽，过高则改为按高度折算，始终不变形。
    double w = maxW;
    double h = w / aspect;
    if (h > maxH) {
      h = maxH;
      w = h * aspect;
    }

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildPreview(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Dialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(_dialogPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPlayerBox(context),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: t.brand,
                    foregroundColor: t.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
