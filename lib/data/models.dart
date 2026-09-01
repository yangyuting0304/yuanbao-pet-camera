/// 本地数据模型 —— 对齐 Spec §6 数据库表（pets / albums / photos）。
/// 当前片用资源清单(seed_manifest.json)驱动，模型与 Drift 表字段一一对应，
/// 后续接入 Drift 本地库时可直接映射，无需改动 UI 层。
library;

import 'seed_config.dart';

class Pet {
  final String id;
  final String name;
  final String species;
  final String breed;
  final String birthday;
  final String avatarFileName;
  final String bio;

  const Pet({
    required this.id,
    required this.name,
    required this.species,
    required this.breed,
    required this.birthday,
    required this.avatarFileName,
    required this.bio,
  });

  factory Pet.fromJson(Map<String, dynamic> j) => Pet(
    id: j['id'] as String,
    name: j['name'] as String,
    species: j['species'] as String,
    breed: j['breed'] as String,
    birthday: j['birthday'] as String,
    avatarFileName: j['avatarFileName'] as String,
    bio: j['bio'] as String,
  );

  /// 远程头像地址（种子图已外置到对象存储，按「前缀 + 文件名」拼接）。
  String get avatarUrl => SeedConfig.photoUrl(avatarFileName);

  /// 本地资源路径，仅作数据记录 —— 图片已不随安装包分发。
  String get avatarPath => 'assets/seed/photos/$avatarFileName';

  /// 由生日计算年龄（周岁，向下取整）。
  int get ageYears {
    final b = DateTime.tryParse(birthday);
    if (b == null) return 0;
    final now = DateTime(2026, 7, 24);
    var age = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) {
      age -= 1;
    }
    return age;
  }

  /// 精确年龄标签（如"3岁10个月"）。
  String get ageLabel {
    final b = DateTime.tryParse(birthday);
    if (b == null) return '未知';
    final now = DateTime(2026, 7, 24);
    var years = now.year - b.year;
    var months = now.month - b.month;
    if (now.day < b.day) months--;
    if (months < 0) {
      years--;
      months += 12;
    }
    if (years > 0 && months > 0) return '$years岁${months}个月';
    if (years > 0) return '$years岁';
    return '$months个月';
  }
}

class Album {
  final String id;
  final String petId;
  final String title;

  const Album({required this.id, required this.petId, required this.title});

  factory Album.fromJson(Map<String, dynamic> j) => Album(
    id: j['id'] as String,
    petId: j['petId'] as String,
    title: j['title'] as String,
  );
}

class Photo {
  final String id;
  final String petId;
  final String albumId;
  final String fileName;
  final DateTime capturedAt;
  final String source;

  const Photo({
    required this.id,
    required this.petId,
    required this.albumId,
    required this.fileName,
    required this.capturedAt,
    required this.source,
  });

  factory Photo.fromJson(Map<String, dynamic> j) => Photo(
    id: j['id'] as String,
    petId: j['petId'] as String,
    albumId: j['albumId'] as String,
    fileName: j['fileName'] as String,
    capturedAt: DateTime.parse(j['capturedAt'] as String),
    source: j['source'] as String,
  );

  /// 远程图片地址（种子图已外置到对象存储，按「前缀 + 文件名」拼接）。
  String get remoteUrl => SeedConfig.photoUrl(fileName);

  /// 本地资源路径，仅作数据记录 —— 图片已不随安装包分发。
  String get assetPath => 'assets/seed/photos/$fileName';

  /// 时间视图分组键：YYYY年M月
  String get monthKey => '${capturedAt.year}年${capturedAt.month}月';
}
