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

  /// Only actual user records are returned. Legacy demo rows are filtered out.
  static List<GrowthRecord> get(String petId) {
    final raw = _box.get('g_$petId');
    if (raw == null) return [];
    final list = (jsonDecode(raw as String) as List)
        .map((e) => GrowthRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((r) => !r.id.contains('_seed_'))
        .toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  static Future<void> save(String petId, List<GrowthRecord> records) async {
    final sorted = [...records]..sort((a, b) => b.date.compareTo(a.date));
    await _box.put(
      'g_$petId',
      jsonEncode(sorted.map((e) => e.toJson()).toList()),
    );
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

  Future<void> add(String petId, GrowthRecord r) async {
    final next = [
      ...GrowthRecordsRepository.get(petId).where((e) => e.id != r.id),
      r,
    ]..sort((a, b) => b.date.compareTo(a.date));
    await GrowthRecordsRepository.save(petId, next);
    _ref.invalidate(growthRecordsProvider(petId));
  }

  Future<void> remove(String petId, String id) async {
    final next = GrowthRecordsRepository.get(
      petId,
    ).where((e) => e.id != id).toList();
    await GrowthRecordsRepository.save(petId, next);
    _ref.invalidate(growthRecordsProvider(petId));
  }
}
