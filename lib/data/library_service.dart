import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// 作品类型（对应后端 WORK_TYPES）。
/// 分属 COS 上两份清单：seed.json（seed_photo）与 works.json（其余四类）。
enum LibraryType {
  /// 种子图（宠物/相册的初始照片），存于 seed.json。
  seedPhoto('seed_photo'),

  /// 用户拍摄的照片。
  capturedPhoto('captured_photo'),

  /// 美颜 / 编辑后保存的图片。
  editedPhoto('edited_photo'),

  /// AI 写真 / AI 编辑结果。
  createdImage('created_image'),

  /// AI 成片视频。
  createdVideo('created_video');

  const LibraryType(this.value);
  final String value;

  static LibraryType fromValue(String? v) => values.firstWhere(
    (t) => t.value == v,
    orElse: () => LibraryType.createdImage,
  );
}

/// 统一的相册条目：既涵盖种子图，也涵盖用户拍摄/编辑/AI 生成的作品。
/// 全部以 COS 公网 URL 为数据源，刷新后可从服务端重新拉取。
class LibraryItem {
  const LibraryItem({
    required this.id,
    required this.type,
    required this.url,
    this.label = '',
    this.petId = '',
    this.albumId = '',
    this.createdAt,
    this.bytes,
  });

  final String id;
  final LibraryType type;
  final String url;
  final String label;
  final String petId;
  final String albumId;

  /// 创建时间（服务端生成；缺失时按当前时间处理）。
  final DateTime? createdAt;

  /// 本地字节（仅新建作品在内存中暂留，用于即时预览；刷新后以 url 为准）。
  final Uint8List? bytes;

  /// 用于排序 / 分组的时间（缺失时回退到当前时间）。
  DateTime get takenAt => createdAt ?? DateTime.now();

  bool get isVideo => type == LibraryType.createdVideo;

  /// 归属相册「照片」分组（按宠物/时间）：种子图 + 拍摄照片。
  bool get isPhotoGroup => type == LibraryType.seedPhoto || type == LibraryType.capturedPhoto;

  /// 归属相册「我的创作」：编辑图 + AI 生成图 + 视频。
  bool get isCreatedGroup =>
      type == LibraryType.editedPhoto ||
      type == LibraryType.createdImage ||
      type == LibraryType.createdVideo;

  /// 保留 url/元数据，附带本地字节（用于上传后即时预览）。
  LibraryItem copyWithBytes(Uint8List bytes) => LibraryItem(
    id: id,
    type: type,
    url: url,
    label: label,
    petId: petId,
    albumId: albumId,
    createdAt: createdAt,
    bytes: bytes,
  );

  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem(
    id: (j['id'] ?? '') as String,
    type: LibraryType.fromValue(j['type'] as String?),
    url: (j['url'] ?? '') as String,
    label: (j['label'] ?? '') as String,
    petId: (j['petId'] ?? '') as String,
    albumId: (j['albumId'] ?? '') as String,
    createdAt: DateTime.tryParse((j['createdAt'] ?? j['capturedAt'] ?? '') as String),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type.value,
    'url': url,
    'label': label,
    'petId': petId,
    'albumId': albumId,
    'createdAt': takenAt.toIso8601String(),
  };
}

/// 相册库服务：种子数据与作品清单都从 COS 经代理读取。
///
/// 代理地址复用编译期 --dart-define（AI_VIDEO_PROXY_URL / AI_PROXY_URL / FIERED_PROXY_URL），
/// 与 UploadService 完全一致，未配置时各接口抛出 [LibraryException]。
class LibraryService {
  static const String _videoProxy = String.fromEnvironment(
    'AI_VIDEO_PROXY_URL',
    defaultValue: '',
  );
  static const String _aiProxy = String.fromEnvironment(
    'AI_PROXY_URL',
    defaultValue: '',
  );
  static const String _fireredProxy = String.fromEnvironment(
    'FIERED_PROXY_URL',
    defaultValue: '',
  );

  /// 解析代理根地址（三个代理路径不同，统一取 scheme://authority）。
  static Uri? _uriFor(String path) {
    String? raw;
    if (_videoProxy.isNotEmpty) {
      raw = _videoProxy;
    } else if (_aiProxy.isNotEmpty) {
      raw = _aiProxy;
    } else if (_fireredProxy.isNotEmpty) {
      raw = _fireredProxy;
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      final uri = Uri.parse(raw);
      if (!uri.hasScheme || uri.host.isEmpty) return null;
      return Uri.parse('${uri.scheme}://${uri.authority}$path');
    } catch (_) {
      return null;
    }
  }

  bool get configured => _uriFor('/api/seed') != null;

  /// 拉取种子数据（pets / albums / photos）。
  Future<List<LibraryItem>> fetchSeed() async {
    final uri = _uriFor('/api/seed');
    if (uri == null) throw const LibraryException('未配置代理（AI_VIDEO_PROXY_URL / AI_PROXY_URL）');
    final resp = await http.get(uri).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw LibraryException('拉取种子数据失败：${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final photos = data['photos'] as List<dynamic>? ?? const [];
    return photos
        .map((e) => LibraryItem.fromJson(e as Map<String, dynamic>))
        .where((it) => it.url.isNotEmpty)
        .toList();
  }

  /// 拉取作品清单（拍摄 / 编辑 / AI 生成的图片与视频）。
  Future<List<LibraryItem>> fetchWorks() async {
    final uri = _uriFor('/api/works');
    if (uri == null) throw const LibraryException('未配置代理（AI_VIDEO_PROXY_URL / AI_PROXY_URL）');
    final resp = await http.get(uri).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw LibraryException('拉取作品清单失败：${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? const [];
    return items
        .map((e) => LibraryItem.fromJson(e as Map<String, dynamic>))
        .where((it) => it.url.isNotEmpty)
        .toList();
  }

  /// 上传作品并登记进 works.json，返回带 url 的条目。
  Future<LibraryItem> uploadWork({
    required Uint8List bytes,
    required LibraryType type,
    String ext = 'jpg',
    String? contentType,
    String label = '',
    String petId = '',
  }) async {
    final uri = _uriFor('/api/upload');
    if (uri == null) throw const LibraryException('未配置代理（AI_VIDEO_PROXY_URL / AI_PROXY_URL）');
    final resp = await http
        .post(
          uri,
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{
            'dataBase64': base64Encode(bytes),
            'type': type.value,
            'ext': ext,
            if (contentType != null) 'contentType': contentType,
            'label': label,
            'petId': petId,
          }),
        )
        .timeout(const Duration(minutes: 5));
    if (resp.statusCode != 200) {
      throw LibraryException('上传失败：${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['error'] != null) throw LibraryException('上传失败：${data['error']}');
    final item = data['item'] as Map<String, dynamic>?;
    if (item == null) throw const LibraryException('上传成功但未返回条目');
    return LibraryItem.fromJson(item).copyWithBytes(bytes);
  }
}

/// 相册库异常。
class LibraryException implements Exception {
  const LibraryException(this.message);
  final String message;
  @override
  String toString() => 'LibraryException: $message';
}

/// 作品清单状态：启动时从 /api/works 拉取，新增作品时乐观插入队首。
class WorksNotifier extends AsyncNotifier<List<LibraryItem>> {
  @override
  Future<List<LibraryItem>> build() => ref.read(libraryServiceProvider).fetchWorks();

  /// 上传并登记一条作品（失败时回滚本地状态）。
  Future<LibraryItem> add({
    required Uint8List bytes,
    required LibraryType type,
    String ext = 'jpg',
    String? contentType,
    String label = '',
    String petId = '',
  }) async {
    final item = await ref
        .read(libraryServiceProvider)
        .uploadWork(
          bytes: bytes,
          type: type,
          ext: ext,
          contentType: contentType,
          label: label,
          petId: petId,
        );
    state = AsyncData(<LibraryItem>[item, ...?state.value]);
    return item;
  }
}

final libraryServiceProvider = Provider<LibraryService>((ref) => LibraryService());

final worksProvider =
    AsyncNotifierProvider<WorksNotifier, List<LibraryItem>>(WorksNotifier.new);
