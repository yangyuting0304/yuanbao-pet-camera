import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// 任务类型。
/// 本次只落地 video（AI 一键成片）；image 为预留位，后续 AI 写真 / 图片编辑
/// 的异步任务可以直接复用同一套存储、轮询与顶部入口，无需再建一套。
enum TaskKind { video, image }

extension TaskKindX on TaskKind {
  String get key => switch (this) {
    TaskKind.video => 'video',
    TaskKind.image => 'image',
  };

  static TaskKind fromKey(String? k) =>
      k == 'image' ? TaskKind.image : TaskKind.video;
}

/// 任务阶段。
/// - generating：已提交，轮询中；
/// - succeeded：服务端已生成，用户还没打开看过；
/// - viewed：用户已看过，但还没下载 / 保存到相册；
/// - processed：已下载或已保存，任务闭环（顶部入口隐藏）；
/// - failed：生成失败 / 任务已过期（顶部入口隐藏）；
/// - discarded：用户主动丢弃（顶部入口隐藏）。
enum TaskStage { generating, succeeded, viewed, processed, failed, discarded }

extension TaskStageX on TaskStage {
  String get key => switch (this) {
    TaskStage.generating => 'generating',
    TaskStage.succeeded => 'succeeded',
    TaskStage.viewed => 'viewed',
    TaskStage.processed => 'processed',
    TaskStage.failed => 'failed',
    TaskStage.discarded => 'discarded',
  };

  static TaskStage fromKey(String? k) => switch (k) {
    'succeeded' => TaskStage.succeeded,
    'viewed' => TaskStage.viewed,
    'processed' => TaskStage.processed,
    'failed' => TaskStage.failed,
    'discarded' => TaskStage.discarded,
    _ => TaskStage.generating,
  };

  /// 顶部导航栏是否展示入口：只有未闭环的任务才需要提醒用户。
  bool get visibleInNav =>
      this == TaskStage.generating ||
      this == TaskStage.succeeded ||
      this == TaskStage.viewed;

  /// 是否已闭环：不需要再提醒，也不需要继续轮询。
  bool get finished =>
      this == TaskStage.processed ||
      this == TaskStage.failed ||
      this == TaskStage.discarded;
}

/// 进行中的任务（本地只存一条）。
/// 视频生成耗时数分钟，taskId 必须落盘，否则退出页面 / 重启 App 就找不回结果。
class PendingTask {
  const PendingTask({
    required this.taskId,
    required this.kind,
    required this.stage,
    required this.createdAt,
    required this.updatedAt,
    this.prompt = '',
    this.duration = 0,
    this.videoUrl,
    this.error = '',
  });

  final String taskId;

  /// video / image（image 为后续扩展预留）。
  final TaskKind kind;

  final TaskStage stage;

  /// 提示词（结果页回显用）。
  final String prompt;

  /// 视频时长（秒）；图片任务为 0。
  final int duration;

  /// 成功后写入的远程视频地址，避免每次进结果页都重新查状态。
  final String? videoUrl;

  /// 失败原因 / 轮询异常提示。
  final String error;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 非空时返回错误文案（存盘时用空串表示「无错误」）。
  String? get errorMessage =>
      (error.isEmpty) ? null : error;

  PendingTask copyWith({
    String? taskId,
    TaskKind? kind,
    TaskStage? stage,
    String? prompt,
    int? duration,
    String? videoUrl,
    String? error,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PendingTask(
    taskId: taskId ?? this.taskId,
    kind: kind ?? this.kind,
    stage: stage ?? this.stage,
    prompt: prompt ?? this.prompt,
    duration: duration ?? this.duration,
    videoUrl: videoUrl ?? this.videoUrl,
    error: error ?? this.error,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'taskId': taskId,
    'kind': kind.key,
    'stage': stage.key,
    'prompt': prompt,
    'duration': duration,
    if (videoUrl != null) 'videoUrl': videoUrl,
    'error': error,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PendingTask.fromJson(Map<String, dynamic> j) => PendingTask(
    taskId: (j['taskId'] ?? '') as String,
    kind: TaskKindX.fromKey(j['kind'] as String?),
    stage: TaskStageX.fromKey(j['stage'] as String?),
    prompt: (j['prompt'] ?? '') as String,
    duration: (j['duration'] ?? 0) as int,
    videoUrl: j['videoUrl'] as String?,
    error: (j['error'] ?? '') as String,
    createdAt:
        DateTime.tryParse((j['createdAt'] ?? '') as String) ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse((j['updatedAt'] ?? '') as String) ?? DateTime.now(),
  );
}

/// 任务本地存储（Hive，单条：key = 'current'）。
///
/// Hive 在 Web 走 IndexedDB、在原生走文件；初始化失败时（见 main.dart 的降级）
/// 这里整体退化为「不持久化」，不影响 App 运行。
class TaskStore {
  static const String boxName = 'tasks';
  static const String _key = 'current';

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen(boxName) ? Hive.box<dynamic>(boxName) : null;

  /// 读取当前任务；没有或解析失败返回 null。
  static PendingTask? load() {
    final raw = _box?.get(_key);
    if (raw is! String || raw.isEmpty) return null;
    try {
      return PendingTask.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static void save(PendingTask task) {
    try {
      _box?.put(_key, jsonEncode(task.toJson()));
    } catch (_) {
      // 持久化失败不阻塞交互，任务仍留在内存状态里。
    }
  }

  static void clear() {
    try {
      _box?.delete(_key);
    } catch (_) {}
  }
}
