import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 成长手记记录类型：体重 / 疫苗 / 趣事。
enum GrowthType { weight, vaccine, note }

extension GrowthTypeX on GrowthType {
  String get key => switch (this) {
    GrowthType.weight => 'weight',
    GrowthType.vaccine => 'vaccine',
    GrowthType.note => 'note',
  };

  static GrowthType fromKey(String k) => switch (k) {
    'vaccine' => GrowthType.vaccine,
    'note' => GrowthType.note,
    _ => GrowthType.weight,
  };
}

/// 单条成长记录。统一用 JSON 字符串存 Hive（不写 TypeAdapter，降低复杂度）。
class GrowthRecord {
  const GrowthRecord({
    required this.id,
    required this.type,
    required this.date,
    required this.value,
    this.note = '',
  });

  final String id;
  final GrowthType type;
  final DateTime date;

  /// weight: 体重 kg 数值字符串；vaccine: 疫苗名称；note: 趣事标题
  final String value;

  /// 备注 / 趣事正文
  final String note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.key,
    'date': date.toIso8601String(),
    'value': value,
    'note': note,
  };

  factory GrowthRecord.fromJson(Map<String, dynamic> j) => GrowthRecord(
    id: j['id'] as String,
    type: GrowthTypeX.fromKey(j['type'] as String),
    date: DateTime.parse(j['date'] as String),
    value: j['value'] as String,
    note: (j['note'] as String?) ?? '',
  );
}

/// 成长手记仓储：Hive box 持久化，按 petId 维度读写。
class GrowthRecordsRepository {
  static const String _boxName = 'growthRecords';
  static Box get _box => Hive.box(_boxName);

  /// 读取某宠物的成长记录（倒序）。无数据返回预置示例，便于 Demo 展示。
  static List<GrowthRecord> get(String petId) {
    final raw = _box.get('g_$petId');
    if (raw == null) return _seed(petId);
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => GrowthRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    } catch (_) {
      return _seed(petId);
    }
  }

  /// 保存（倒序写入）。
  static void save(String petId, List<GrowthRecord> records) {
    final sorted = [...records]..sort((a, b) => b.date.compareTo(a.date));
    _box.put('g_$petId', jsonEncode(sorted.map((e) => e.toJson()).toList()));
  }

  /// 预置示例数据（仅当 Hive 无记录时返回，不落盘；用户首次添加即被真实数据覆盖）。
  static List<GrowthRecord> _seed(String petId) {
    final now = DateTime(2026, 7, 24);
    GrowthRecord mk(int daysAgo, GrowthType t, String v, [String n = '']) =>
        GrowthRecord(
          id: '${petId}_seed_$daysAgo',
          type: t,
          date: now.subtract(Duration(days: daysAgo)),
          value: v,
          note: n,
        );
    switch (petId) {
      case 'yuanbao':
        return [
          mk(8, GrowthType.weight, '4.8', '体重稳定增长，体态匀称'),
          mk(35, GrowthType.vaccine, '猫三联', '年度加强针，无不良反应'),
          mk(66, GrowthType.note, '第一次学会握手', '用冻干引导，三周学会'),
        ];
      case 'xiaomianhua':
        return [
          mk(12, GrowthType.weight, '3.6', '偏瘦，已增加主食罐频次'),
          mk(50, GrowthType.vaccine, '狂犬疫苗', '社区免费接种点'),
        ];
      case 'xiaotangyuan':
        return [
          mk(5, GrowthType.weight, '2.9', '幼猫成长期，食量增大'),
          mk(28, GrowthType.note, '拆家小能手', '咬坏了一根数据线'),
        ];
      case 'friends':
        return [mk(20, GrowthType.note, '猫友聚会', '小区三只猫一起晒太阳')];
      default:
        return [
          mk(15, GrowthType.weight, '3.5'),
          mk(45, GrowthType.vaccine, '猫三联', '年度加强'),
        ];
    }
  }
}

/// 只读：按宠物读取成长记录（FutureProvider.family 自动缓存，写后 invalidate 刷新）。
final growthRecordsProvider = FutureProvider.family<List<GrowthRecord>, String>(
  (ref, petId) => GrowthRecordsRepository.get(petId),
);

/// 写入助手：写后 invalidate 对应 petId 的读取 provider，触发 UI 刷新。
final growthRecordsMutationProvider = Provider((ref) => _GrowthMutation(ref));

class _GrowthMutation {
  _GrowthMutation(this._ref);
  final Ref _ref;

  void add(String petId, GrowthRecord r) {
    final next = [...GrowthRecordsRepository.get(petId), r]
      ..sort((a, b) => b.date.compareTo(a.date));
    GrowthRecordsRepository.save(petId, next);
    _ref.invalidate(growthRecordsProvider(petId));
  }

  void remove(String petId, String id) {
    final next = GrowthRecordsRepository.get(
      petId,
    ).where((e) => e.id != id).toList();
    GrowthRecordsRepository.save(petId, next);
    _ref.invalidate(growthRecordsProvider(petId));
  }
}
