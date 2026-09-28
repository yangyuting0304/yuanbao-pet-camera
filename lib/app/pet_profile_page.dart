// 宠物档案 / 成长手记页。拆分自原 pages.dart（8631 行）。
//
// part of pages.dart —— 切分理由见 camera_page.dart 顶部说明。

part of 'pages.dart';

/// 宠物档案页：金元宝档案卡 + 统计。
/// 成长手记页：宠物切换 + 档案卡 + 录入（体重/疫苗/趣事）+ 时间线。
/// 记录本地持久化（Hive），按宠物隔离。
class PetProfilePage extends ConsumerStatefulWidget {
  const PetProfilePage({super.key});
  @override
  ConsumerState<PetProfilePage> createState() => _PetProfilePageState();
}

class _PetProfilePageState extends ConsumerState<PetProfilePage> {
  String? _selectedPetId;
  bool _isPetListExpanded = true;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final petsAsync = ref.watch(petsProvider);
    return _Shell(
      title: '成长手记',
      appBarBackgroundColor: const Color(0xFFF6F8FA),
      body: petsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (pets) {
          if (pets.isEmpty) return const Center(child: Text('暂无宠物档案'));
          _selectedPetId ??= pets.first.id;
          final pet = pets.firstWhere(
            (p) => p.id == _selectedPetId,
            orElse: () => pets.first,
          );
          final photosAsync = ref.watch(photosProvider);
          final recordsAsync = ref.watch(growthRecordsProvider(pet.id));
          return recordsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('记录加载失败')),
            data: (records) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              children: [
                _PetSwitch(
                  pets: pets,
                  selectedId: pet.id,
                  expanded: _isPetListExpanded,
                  onSelect: (id) => setState(() => _selectedPetId = id),
                  onToggleExpanded: () =>
                      setState(() => _isPetListExpanded = !_isPetListExpanded),
                ),
                const SizedBox(height: 16),
                _PetHeaderCard(
                  pet: pet,
                  recordCount: records.length,
                  photoCount: photosAsync.maybeWhen(
                    data: (p) => p.where((x) => x.petId == pet.id).length,
                    orElse: () => 0,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '成长时间线',
                    style: TextStyle(
                      fontSize: 20,
                      height: 28 / 20,
                      fontWeight: FontWeight.w400,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (records.isEmpty)
                  const _EmptyTimeline()
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const cardGap = 12.0;
                      final cardWidth = (constraints.maxWidth - cardGap) / 2;
                      final orderedRecords = [...records]
                        ..sort((a, b) {
                          const order = <GrowthType, int>{
                            GrowthType.weight: 0,
                            GrowthType.note: 1,
                            GrowthType.vaccine: 2,
                          };
                          final typeCompare = (order[a.type] ?? 99).compareTo(
                            order[b.type] ?? 99,
                          );
                          if (typeCompare != 0) {
                            return typeCompare;
                          }
                          return b.date.compareTo(a.date);
                        });
                      return Wrap(
                        spacing: cardGap,
                        runSpacing: cardGap,
                        children: orderedRecords
                            .map(
                              (r) => SizedBox(
                                width: cardWidth,
                                child: _TimelineItem(
                                  record: r,
                                  onAdd: () =>
                                      _showAddSheet(context, pet.id, r.type),
                                  onDelete: () => ref
                                      .read(growthRecordsMutationProvider)
                                      .remove(pet.id, r.id),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddSheet(BuildContext context, String petId, GrowthType type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddRecordSheet(
        type: type,
        onSubmit: (record) {
          ref.read(growthRecordsMutationProvider).add(petId, record);
          Navigator.pop(context);
        },
      ),
    );
  }
}

/// 成长手记顶部宠物切换卡片。
/// 按设计稿支持展开/收起两种状态：展开时显示头像列表，收起时只保留标题栏。
class _PetSwitch extends StatelessWidget {
  const _PetSwitch({
    required this.pets,
    required this.selectedId,
    required this.expanded,
    required this.onSelect,
    required this.onToggleExpanded,
  });
  final List<Pet> pets;
  final String selectedId;
  final bool expanded;
  final ValueChanged<String> onSelect;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '毛孩们',
                    style: TextStyle(
                      fontSize: AppUi.fontTitle,
                      height: 24 / AppUi.fontTitle,
                      fontWeight: FontWeight.w400,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggleExpanded,
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: expanded
                          ? const Color(0xFF000000)
                          : const Color(0xFF09244B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 88,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < pets.length; i++) ...[
                      _PetFilterAvatarTile(
                        name: pets[i].name,
                        avatarUrl: pets[i].avatarUrl,
                        selected: pets[i].id == selectedId,
                        onTap: () => onSelect(pets[i].id),
                      ),
                      if (i != pets.length - 1) const SizedBox(width: 16),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 宠物档案卡：头像 + 名字 + 品种年龄 + 统计。
class _PetHeaderCard extends StatelessWidget {
  const _PetHeaderCard({
    required this.pet,
    required this.recordCount,
    required this.photoCount,
  });
  final Pet pet;
  final int recordCount;
  final int photoCount;

  /// 统计区年龄使用更紧凑的数字展示，和设计稿里的数值样式保持一致。
  String get _ageMetricValue {
    final birthday = DateTime.tryParse(pet.birthday);
    if (birthday == null) return pet.ageLabel;
    final now = DateTime(2026, 7, 24);
    var years = now.year - birthday.year;
    var months = now.month - birthday.month;
    if (now.day < birthday.day) {
      months -= 1;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    if (years <= 0) {
      return '$months月';
    }
    if (months == 0) {
      return '$years';
    }
    return (years + months / 12).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = pet.breed.isNotEmpty
        ? (pet.ageLabel != '未知' ? '${pet.breed} · ${pet.ageLabel}' : pet.breed)
        : (pet.ageLabel != '未知' ? pet.ageLabel : '');

    return Container(
      constraints: const BoxConstraints(minHeight: 204),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部信息区：头像与基础资料横向排列，贴近设计稿结构。
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipOval(
                child: AppImage(
                  url: pet.avatarUrl,
                  width: 64,
                  height: 64,
                  memCacheWidth: 128,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        height: 28 / 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF000000),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 20 / 12,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF999999),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            pet.bio,
            style: const TextStyle(
              fontSize: 14,
              height: 22 / 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF000000),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PetMetricItem(label: '照片', value: '$photoCount'),
              const SizedBox(width: 12),
              _PetMetricItem(label: '记录', value: '$recordCount'),
              const SizedBox(width: 12),
              _PetMetricItem(label: '年龄', value: _ageMetricValue),
            ],
          ),
        ],
      ),
    );
  }
}

/// 时间线单条记录。
class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.record,
    required this.onAdd,
    required this.onDelete,
  });
  final GrowthRecord record;
  final VoidCallback onAdd;
  final VoidCallback onDelete;

  (Color, Widget, String, String) get _style {
    switch (record.type) {
      case GrowthType.weight:
        return (
          const Color(0xFF38D070),
          const MingCuteIcon(
            MingCuteIcons.instrumentFill,
            size: 18,
            color: Colors.white,
          ),
          '记体重',
          '体重',
        );
      case GrowthType.vaccine:
        return (
          const Color(0xFFFF5C5A),
          const MingCuteIcon(
            MingCuteIcons.injectionFill,
            size: 18,
            color: Colors.white,
          ),
          '记疫苗',
          '疫苗',
        );
      case GrowthType.note:
        return (
          const Color(0xFF9180FF),
          const MingCuteIcon(
            MingCuteIcons.tongueFill,
            size: 18,
            color: Colors.white,
          ),
          '记趣事',
          '趣事',
        );
    }
  }

  String get _valueText {
    switch (record.type) {
      case GrowthType.weight:
        return '${record.value}kg';
      case GrowthType.vaccine:
        return record.value;
      case GrowthType.note:
        return record.value;
    }
  }

  /// 时间样式改成“8月14日 23:05”，贴近设计稿展示。
  String get _dateText {
    final hh = record.date.hour.toString().padLeft(2, '0');
    final mm = record.date.minute.toString().padLeft(2, '0');
    final ss = record.date.second.toString().padLeft(2, '0');
    return '${record.date.month}月${record.date.day}日 $hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final (accentColor, iconWidget, actionLabel, typeName) = _style;
    return GestureDetector(
      onLongPress: () async {
        // 长按后先二次确认，避免误删成长记录。
        final shouldDelete = await showDialog<bool>(
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
                    const Text(
                      '删除记录',
                      style: TextStyle(
                        fontSize: AppUi.fontHeadline,
                        height: 28 / AppUi.fontHeadline,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF000000),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '确认删除这条$typeName记录吗？删除后将无法恢复。',
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
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppPrimaryActionButton(
                            label: '删除',
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
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
        if (shouldDelete == true) {
          onDelete();
        }
      },
      child: Container(
        height: 164,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: iconWidget,
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAdd,
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.5),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      actionLabel,
                      style: TextStyle(
                        fontSize: 12,
                        height: 20 / 12,
                        fontWeight: FontWeight.w400,
                        color: accentColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeName,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF000000),
                  ),
                ),
                Text(
                  _valueText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF000000),
                  ),
                ),
                Text(
                  _dateText,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 20 / 12,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              record.note.isNotEmpty ? record.note : '已记录$typeName信息',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 20 / 12,
                fontWeight: FontWeight.w400,
                color: Color(0xFF000000),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 统一浅色描边次按钮，给弹窗和底部弹层复用。
class _AppSecondaryActionButton extends StatelessWidget {
  const _AppSecondaryActionButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: context.tokens.textPrimary,
          side: const BorderSide(color: Color(0xFFE2E4E6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: AppUi.fontTitle,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 164,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MingCuteIcon(
            MingCuteIcons.clipboard,
            size: 24,
            color: Color(0xFF999999),
          ),
          SizedBox(height: 8),
          Text(
            '还没有记录，点上方按钮添加第一条',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 22 / 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}

/// 录入底部弹层表单。
class _AddRecordSheet extends StatefulWidget {
  const _AddRecordSheet({required this.type, required this.onSubmit});
  final GrowthType type;
  final ValueChanged<GrowthRecord> onSubmit;

  @override
  State<_AddRecordSheet> createState() => _AddRecordSheetState();
}

class _AddRecordSheetState extends State<_AddRecordSheet> {
  static const Color _fieldBorderColor = Color(0xFFE2E4E6);
  DateTime _date = DateTime.now();
  final _valueCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String get _title => switch (widget.type) {
    GrowthType.weight => '记体重',
    GrowthType.vaccine => '记疫苗',
    GrowthType.note => '记趣事',
  };

  String get _valueLabel => switch (widget.type) {
    GrowthType.weight => '体重 (kg)',
    GrowthType.vaccine => '疫苗名称',
    GrowthType.note => '趣事标题',
  };

  String get _noteLabel => switch (widget.type) {
    GrowthType.note => '趣事内容',
    GrowthType.vaccine => '备注（选填）',
    GrowthType.weight => '备注（选填）',
  };

  @override
  void dispose() {
    _valueCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final record = GrowthRecord(
      id: 'rec_${DateTime.now().microsecondsSinceEpoch}',
      type: widget.type,
      date: _date,
      value: _valueCtl.text.trim(),
      note: _noteCtl.text.trim(),
    );
    widget.onSubmit(record);
  }

  String _formatDateLabel(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    final ss = date.second.toString().padLeft(2, '0');
    return '${date.year}年${date.month.toString().padLeft(2, '0')}月${date.day.toString().padLeft(2, '0')}日 $hh:$mm:$ss';
  }

  InputDecoration _buildInputDecoration(
    BuildContext context, {
    required String hintText,
  }) {
    final t = context.tokens;
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        fontSize: AppUi.fontBody,
        height: AppUi.lineHeight(AppUi.fontBody),
        color: t.textSecondary,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        borderSide: const BorderSide(color: _fieldBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        borderSide: const BorderSide(color: _fieldBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        borderSide: const BorderSide(color: Color(0xFF000000)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        borderSide: const BorderSide(color: Color(0xFFFF5C5A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        borderSide: const BorderSide(color: Color(0xFFFF5C5A)),
      ),
      errorStyle: const TextStyle(fontSize: 12, height: 20 / 12),
    );
  }

  Future<void> _showCustomDateSheet() async {
    var tempDate = _date;
    var tempSecond = _date.second;
    final selectedDate = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E4E6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '记录时间',
                    style: TextStyle(
                      fontSize: AppUi.fontHeadline,
                      height: 28 / AppUi.fontHeadline,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 220,
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.dateAndTime,
                            use24hFormat: true,
                            initialDateTime: _date,
                            minimumDate: DateTime(2018),
                            maximumDate: DateTime.now(),
                            onDateTimeChanged: (value) {
                              tempDate = value;
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        height: 220,
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            const Text(
                              '秒',
                              style: TextStyle(
                                fontSize: 12,
                                height: 20 / 12,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF999999),
                              ),
                            ),
                            Expanded(
                              child: CupertinoPicker(
                                itemExtent: 36,
                                scrollController: FixedExtentScrollController(
                                  initialItem: _date.second,
                                ),
                                onSelectedItemChanged: (value) {
                                  tempSecond = value;
                                },
                                children: List.generate(
                                  60,
                                  (index) => Center(
                                    child: Text(
                                      index.toString().padLeft(2, '0'),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFF000000),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _AppSecondaryActionButton(
                          label: '取消',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppPrimaryActionButton(
                          label: '确定',
                          onPressed: () {
                            final picked = DateTime(
                              tempDate.year,
                              tempDate.month,
                              tempDate.day,
                              tempDate.hour,
                              tempDate.minute,
                              tempSecond,
                            );
                            final now = DateTime.now();
                            Navigator.of(
                              sheetContext,
                            ).pop(picked.isAfter(now) ? now : picked);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted || selectedDate == null) return;
    setState(() => _date = selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _title,
              style: TextStyle(
                fontSize: AppUi.fontHeadline,
                height: 28 / AppUi.fontHeadline,
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '日期',
              style: TextStyle(
                fontSize: AppUi.fontBody,
                height: AppUi.lineHeight(AppUi.fontBody),
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showCustomDateSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  border: Border.all(color: _fieldBorderColor),
                ),
                child: Row(
                  children: [
                    const MingCuteIcon(
                      MingCuteIcons.calendar,
                      size: 20,
                      color: Color(0xFF000000),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateLabel(_date),
                      style: TextStyle(
                        fontSize: AppUi.fontBody,
                        color: t.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    // 日期选择入口右箭头统一使用 MingCute 和灰色规范。
                    const MingCuteIcon(
                      MingCuteIcons.rightLine,
                      size: 20,
                      color: Color(0xFF999999),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _valueLabel,
              style: TextStyle(
                fontSize: AppUi.fontBody,
                height: AppUi.lineHeight(AppUi.fontBody),
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _valueCtl,
              keyboardType: widget.type == GrowthType.weight
                  ? TextInputType.number
                  : TextInputType.text,
              style: TextStyle(
                fontSize: AppUi.fontBody,
                height: AppUi.lineHeight(AppUi.fontBody),
                color: t.textPrimary,
              ),
              decoration: _buildInputDecoration(
                context,
                hintText: switch (widget.type) {
                  GrowthType.weight => '请输入体重，例如 4.8',
                  GrowthType.vaccine => '请输入疫苗名称',
                  GrowthType.note => '请输入趣事标题',
                },
              ),
              validator: (v) => v == null || v.trim().isEmpty ? '此项必填' : null,
            ),
            const SizedBox(height: 12),
            Text(
              _noteLabel,
              style: TextStyle(
                fontSize: AppUi.fontBody,
                height: AppUi.lineHeight(AppUi.fontBody),
                fontWeight: FontWeight.w400,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _noteCtl,
              maxLines: 3,
              style: TextStyle(
                fontSize: AppUi.fontBody,
                height: AppUi.lineHeight(AppUi.fontBody),
                color: t.textPrimary,
              ),
              decoration: _buildInputDecoration(
                context,
                hintText: widget.type == GrowthType.note
                    ? '请输入趣事内容'
                    : '补充一点备注信息',
              ),
            ),
            const SizedBox(height: 20),
            AppPrimaryActionButton(label: '保存', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

class _PetMetricItem extends StatelessWidget {
  const _PetMetricItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      // 统计项改为左对齐，和当前卡片信息区的阅读方向保持一致。
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              height: 28 / 20,
              fontWeight: FontWeight.w400,
              color: Color(0xFF000000),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              height: 20 / 12,
              fontWeight: FontWeight.w400,
              color: Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}
