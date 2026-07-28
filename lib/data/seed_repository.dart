import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';

/// 种子数据仓库：从资源清单加载金元宝演示数据。
/// 单例 + 内存缓存，首次加载后不再读盘。
class SeedRepository {
  SeedRepository._();
  static final SeedRepository instance = SeedRepository._();

  Map<String, dynamic>? _cache;

  Future<Map<String, dynamic>> _load() async {
    if (_cache != null) return _cache!;
    final str = await rootBundle.loadString('assets/seed/seed_manifest.json');
    _cache = jsonDecode(str) as Map<String, dynamic>;
    return _cache!;
  }

  Future<List<Pet>> getPets() async {
    final m = await _load();
    return (m['pets'] as List).map((e) => Pet.fromJson(e)).toList();
  }

  Future<List<Photo>> getPhotos() async {
    final m = await _load();
    final list = (m['photos'] as List).map((e) => Photo.fromJson(e)).toList();
    // 按拍摄时间倒序（最新在前）
    list.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return list;
  }

  Future<List<Album>> getAlbums() async {
    final m = await _load();
    return (m['albums'] as List).map((e) => Album.fromJson(e)).toList();
  }
}

final seedRepositoryProvider = Provider<SeedRepository>((ref) => SeedRepository.instance);

final petsProvider = FutureProvider<List<Pet>>(
  (ref) => ref.watch(seedRepositoryProvider).getPets(),
);

final photosProvider = FutureProvider<List<Photo>>(
  (ref) => ref.watch(seedRepositoryProvider).getPhotos(),
);

final albumsProvider = FutureProvider<List<Album>>(
  (ref) => ref.watch(seedRepositoryProvider).getAlbums(),
);
