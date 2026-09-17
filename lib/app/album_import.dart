import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pet_camera/data/library_service.dart';

/// 从手机相册导入照片 / 视频到「元宝拍拍」。
/// Web 与移动端统一走 file_picker：图片进相册「照片」分组，
/// 视频进「我的创作」；上传成功后经 worksProvider 自动出现在列表。
const _videoExts = <String>{'mp4', 'mov', 'webm', 'm4v'};

/// 单文件上限（Web 端 withData 全量进内存，防大视频拖垮页面）。
const _maxFileBytes = 100 * 1024 * 1024;

/// 打开系统相册选择器并上传所选文件。
Future<void> importFromDeviceGallery(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.media,
    allowMultiple: true,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return;
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text('正在导入 ${result.files.length} 个文件…'),
      duration: const Duration(minutes: 1),
    ),
  );

  var okImages = 0;
  var okVideos = 0;
  var skipped = 0;
  var failed = 0;

  for (final file in result.files) {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      skipped++;
      continue;
    }
    if (bytes.length > _maxFileBytes) {
      skipped++;
      continue;
    }
    final ext = (file.extension ?? '').toLowerCase();
    final isVideo = _videoExts.contains(ext);
    try {
      await ref
          .read(worksProvider.notifier)
          .add(
            bytes: bytes,
            type: isVideo
                ? LibraryType.createdVideo
                : LibraryType.capturedPhoto,
            ext: ext.isEmpty ? (isVideo ? 'mp4' : 'jpg') : ext,
            contentType: _contentTypeFor(ext, isVideo),
            label: '相册导入',
          );
      isVideo ? okVideos++ : okImages++;
    } catch (_) {
      failed++;
    }
  }

  messenger.clearSnackBars();
  final parts = <String>[
    if (okImages > 0) '照片 $okImages 张',
    if (okVideos > 0) '视频 $okVideos 个',
    if (skipped > 0) '跳过 $skipped 个',
    if (failed > 0) '失败 $failed 个',
  ];
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        parts.isEmpty ? '没有可导入的文件' : '导入完成：${parts.join('，')}',
      ),
    ),
  );
}

/// 按扩展名返回 MIME 类型；未知时交由服务端按扩展名兜底。
String? _contentTypeFor(String ext, bool isVideo) {
  const map = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
  };
  return map[ext] ?? (isVideo ? 'video/mp4' : 'image/jpeg');
}
