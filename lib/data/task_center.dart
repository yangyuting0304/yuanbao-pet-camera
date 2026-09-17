import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_camera/data/ai_video_service.dart';
import 'package:pet_camera/data/task_store.dart';

/// 任务中心对外暴露的状态。
class TaskCenterState {
  const TaskCenterState({
    this.task,
    this.videoBytes,
    this.error,
    this.polling = false,
  });

  /// 本地缓存的任务（未闭环时才有意义；闭环后保留一段时间便于查看错误）。
  final PendingTask? task;

  /// 原生端预下载的视频字节（Web 端为 null，走流式地址播放）。
  final Uint8List? videoBytes;

  /// 轮询 / 查询过程中的提示（网络抖动等，不终结任务）。
  final String? error;

  /// 是否正在轮询。
  final bool polling;

  TaskCenterState copyWith({
    PendingTask? task,
    Uint8List? videoBytes,
    String? error,
    bool? polling,
    bool clearError = false,
  }) => TaskCenterState(
    task: task ?? this.task,
    videoBytes: videoBytes ?? this.videoBytes,
    error: clearError ? null : (error ?? this.error),
    polling: polling ?? this.polling,
  );
}

/// 任务中心：统一托管异步生成任务（当前只有 AI 成片视频）。
///
/// 关键点：**轮询不挂在页面上**。视频生成要 1-5 分钟，用户随时可能退出页面、
/// 切 Tab 甚至重启 App；轮询放在这个 App 级 Provider 里（非 autoDispose），
/// 页面销毁只影响 UI，不影响任务推进。taskId 与阶段同步落 [TaskStore]，
/// 冷启动时按缓存恢复轮询（只读 /status，不会重新提交、不产生费用）。
class TaskCenter extends Notifier<TaskCenterState> {
  static const Duration _pollInterval = Duration(seconds: 20);

  /// 单轮最多轮询次数（20s × 30 ≈ 10 分钟）。超过后停止自动轮询但**不判失败**：
  /// 万相偶发超时但最终会成功，任务继续留在「生成中」，用户可在结果页点「继续查询」。
  static const int _maxAttempts = 30;

  /// 缓存保留时长：超过这个时间认为服务端结果已失效，直接丢弃缓存。
  static const Duration _expireAfter = Duration(days: 7);

  Completer<AiVideoResult>? _pendingResult;
  bool _polling = false;
  String? _pollingTaskId;

  @override
  TaskCenterState build() {
    final cached = TaskStore.load();
    if (cached == null) return const TaskCenterState();

    if (DateTime.now().difference(cached.createdAt) > _expireAfter) {
      TaskStore.clear();
      return const TaskCenterState();
    }

    if (cached.stage == TaskStage.generating) {
      // 冷启动恢复：先立刻查一次（可能已经生成完），再按间隔继续。
      unawaited(_runPolling(cached, immediate: true, attempts: 0));
      return TaskCenterState(task: cached, polling: true);
    }
    return TaskCenterState(task: cached);
  }

  /// 顶部导航栏要展示的任务（未闭环才展示）。
  PendingTask? get navEntry {
    final t = state.task;
    return (t != null && t.stage.visibleInNav) ? t : null;
  }

  /// 提交视频生成任务，并持续轮询直到成功 / 失败。
  ///
  /// 返回的 Future 供发起页原地等待结果；即便页面被销毁，轮询与落盘照常进行，
  /// 用户可从顶部入口回到结果页。视频生成前会先丢弃本地未闭环的旧任务
  /// （进入生成页时已有提示弹窗引导处理）。
  Future<AiVideoResult> submitVideo(AiVideoRequest req) async {
    final service = ref.read(aiVideoServiceProvider);
    final taskId = await service.submit(req);

    // 提交成功后再废弃旧任务，避免提交失败却把旧结果弄丢。
    final previous = state.task;
    if (previous != null && !previous.stage.finished) {
      TaskStore.clear();
      _pendingResult = null;
    }
    _stopPolling();

    final now = DateTime.now();
    final task = PendingTask(
      taskId: taskId,
      kind: TaskKind.video,
      stage: TaskStage.generating,
      prompt: req.prompt,
      duration: req.duration,
      createdAt: now,
      updatedAt: now,
    );
    TaskStore.save(task);

    final completer = Completer<AiVideoResult>();
    _pendingResult = completer;
    state = TaskCenterState(task: task, polling: true);
    unawaited(_runPolling(task, immediate: false, attempts: 0, completer: completer));
    return completer.future;
  }

  /// 结果页用：拿到可直接播放的结果。
  /// 缓存里已有 videoUrl 时直接构造；否则先查一次状态。
  Future<AiVideoResult> loadResult() async {
    final task = state.task;
    if (task == null) throw const AiVideoException('没有正在处理的任务');
    final service = ref.read(aiVideoServiceProvider);

    if (task.videoUrl != null && task.videoUrl!.isNotEmpty) {
      return service.buildResult(
        taskId: task.taskId,
        videoUrl: task.videoUrl!,
        videoBytes: state.videoBytes,
      );
    }

    final status = await service.fetchStatus(task.taskId);
    switch (status.status) {
      case AiVideoTaskStatus.succeeded:
        final url = status.videoUrl;
        if (url == null || url.isEmpty) {
          throw const AiVideoException('任务成功但缺少视频地址');
        }
        _applyStage(TaskStage.succeeded, videoUrl: url, error: '');
        Uint8List? bytes = state.videoBytes;
        if (!kIsWeb && (bytes == null || bytes.isEmpty)) {
          try {
            bytes = await service.fetchVideoBytes(task.taskId);
            state = state.copyWith(videoBytes: bytes);
          } catch (_) {
            bytes = null;
          }
        }
        return service.buildResult(
          taskId: task.taskId,
          videoUrl: url,
          videoBytes: bytes,
        );
      case AiVideoTaskStatus.failed:
        throw AiVideoException(status.error ?? '生成失败');
      case AiVideoTaskStatus.canceled:
        throw const AiVideoException('任务已取消');
      case AiVideoTaskStatus.unknown:
        throw const AiVideoException('任务不存在或已过期');
      case AiVideoTaskStatus.pending:
      case AiVideoTaskStatus.running:
        throw const AiVideoException('视频还在生成中');
    }
  }

  /// 用户已查看（去掉「未读」红点，但入口保留，直到保存 / 下载 / 丢弃）。
  void markViewed() => _applyStage(TaskStage.viewed);

  /// 已下载或已保存到相册：任务闭环，顶部入口隐藏。
  void markProcessed() => _applyStage(TaskStage.processed);

  /// 用户主动丢弃：任务结束，顶部入口隐藏。
  void discard() {
    _applyStage(TaskStage.discarded);
    _stopPolling();
    _pendingResult = null;
  }

  /// 手动继续查询（自动轮询超过 [_maxAttempts] 停在这里时用）。
  ///
  /// 每次调用都拿到完整的轮询预算（[_maxAttempts] 次，不累计）；
  /// 已在轮询中时忽略，避免并发出两条轮询。
  void resume() {
    final task = state.task;
    if (task == null ||
        task.stage != TaskStage.generating ||
        _polling) {
      return;
    }
    unawaited(_runPolling(task, immediate: true, attempts: 0));
  }

  /// 调试用：把已有 taskId 登记成「已生成未查看」，用于验证顶部入口与结果页。
  /// 仅当本地没有未闭环任务时生效，避免覆盖真实进行中的任务。
  void debugSeed(String taskId) {
    final current = state.task;
    if (current != null && !current.stage.finished) return;
    final now = DateTime.now();
    final task = PendingTask(
      taskId: taskId,
      kind: TaskKind.video,
      stage: TaskStage.succeeded,
      prompt: '调试回放任务',
      duration: 8,
      createdAt: now,
      updatedAt: now,
    );
    TaskStore.save(task);
    state = TaskCenterState(task: task);
  }

  // ============ 内部实现 ============

  void _stopPolling() {
    _polling = false;
    _pollingTaskId = null;
  }

  void _applyStage(
    TaskStage stage, {
    String? videoUrl,
    String? error,
  }) {
    final task = state.task;
    if (task == null) return;
    final updated = task.copyWith(
      stage: stage,
      videoUrl: videoUrl,
      error: error,
      updatedAt: DateTime.now(),
    );
    TaskStore.save(updated);
    state = state.copyWith(task: updated);
    if (stage.finished) _stopPolling();
  }

  void _completeError(Object error) {
    final completer = _pendingResult;
    _pendingResult = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  Future<void> _runPolling(
    PendingTask task, {
    required bool immediate,
    required int attempts,
    Completer<AiVideoResult>? completer,
  }) async {
    final taskId = task.taskId;
    _polling = true;
    _pollingTaskId = taskId;
    state = state.copyWith(polling: true, task: task, clearError: true);

    var done = attempts;
    while (_polling && _pollingTaskId == taskId) {
      if (!immediate || done > 0) {
        await Future<void>.delayed(_pollInterval);
      }
      if (!_polling || _pollingTaskId != taskId) return;
      done++;

      try {
        final status = await ref
            .read(aiVideoServiceProvider)
            .fetchStatus(taskId);
        if (!_polling || _pollingTaskId != taskId) return;

        switch (status.status) {
          case AiVideoTaskStatus.succeeded:
            final url = status.videoUrl;
            if (url == null || url.isEmpty) {
              await _finishFailed(task, '任务成功但缺少视频地址', completer);
            } else {
              await _finishSucceeded(task, url, completer);
            }
            return;
          case AiVideoTaskStatus.failed:
            await _finishFailed(task, status.error ?? '生成失败', completer);
            return;
          case AiVideoTaskStatus.canceled:
            await _finishFailed(task, '任务已取消', completer);
            return;
          case AiVideoTaskStatus.unknown:
            await _finishFailed(task, '任务不存在或已过期', completer);
            return;
          case AiVideoTaskStatus.pending:
          case AiVideoTaskStatus.running:
            break; // 继续等下一轮
        }
      } catch (e) {
        // 网络抖动 / 超时：不终结任务，下一轮继续。
        if (!_polling || _pollingTaskId != taskId) return;
        state = state.copyWith(
          error: e is AiVideoException ? e.message : '查询状态失败：$e',
        );
      }

      if (done >= _maxAttempts) {
        // 超过 10 分钟：停止自动轮询，任务仍留在「生成中」等用户手动续查。
        _polling = false;
        _pollingTaskId = null;
        state = state.copyWith(polling: false);
        _completeError(
          const AiVideoException(
            '已等待约 10 分钟仍在生成，可在「当前任务」里继续查询',
          ),
        );
        return;
      }
    }
  }

  Future<void> _finishSucceeded(
    PendingTask task,
    String videoUrl,
    Completer<AiVideoResult>? completer,
  ) async {
    _stopPolling();
    final updated = task.copyWith(
      stage: TaskStage.succeeded,
      videoUrl: videoUrl,
      error: '',
      updatedAt: DateTime.now(),
    );
    TaskStore.save(updated);

    // 原生端需要字节才能播，先在后台预取；Web 端走代理流，不整包下载。
    Uint8List? bytes;
    if (!kIsWeb) {
      try {
        bytes = await ref
            .read(aiVideoServiceProvider)
            .fetchVideoBytes(task.taskId);
      } catch (_) {
        bytes = null; // 失败不影响落盘状态，结果页会按需再拉。
      }
    }
    state = TaskCenterState(task: updated, videoBytes: bytes, polling: false);

    final target = completer ?? _pendingResult;
    _pendingResult = null;
    if (target != null && !target.isCompleted) {
      target.complete(
        ref.read(aiVideoServiceProvider).buildResult(
          taskId: task.taskId,
          videoUrl: videoUrl,
          videoBytes: bytes,
        ),
      );
    }
  }

  Future<void> _finishFailed(
    PendingTask task,
    String message,
    Completer<AiVideoResult>? completer,
  ) async {
    _stopPolling();
    final updated = task.copyWith(
      stage: TaskStage.failed,
      error: message,
      updatedAt: DateTime.now(),
    );
    TaskStore.save(updated);
    state = TaskCenterState(task: updated, polling: false);

    final target = completer ?? _pendingResult;
    _pendingResult = null;
    if (target != null && !target.isCompleted) {
      target.completeError(AiVideoException(message));
    }
  }
}

/// Riverpod Provider：任务中心（App 级常驻，非 autoDispose）。
final taskCenterProvider = NotifierProvider<TaskCenter, TaskCenterState>(
  TaskCenter.new,
);
