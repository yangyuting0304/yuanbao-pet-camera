import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pet_camera/app/movie_page.dart';
import 'package:pet_camera/app/pages.dart';
import 'package:pet_camera/app/tokens.dart';
import 'package:pet_camera/data/growth_records.dart';
import 'package:pet_camera/data/models.dart';
import 'package:pet_camera/data/movie_export.dart';
import 'package:pet_camera/data/seed_repository.dart';
import 'package:pet_camera/data/short_videos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('yuanbao_test_');
    Hive.init(temp.path);
    for (final name in ['growthRecords', 'shortVideos', 'shortVideoBytes', 'petProfiles']) {
      await Hive.openBox(name);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => temp.path);
  });
  tearDown(() async { await Hive.close(); await temp.delete(recursive: true); });

  test('growth records are real, isolated by pet and survive reopening', () async {
    expect(GrowthRecordsRepository.get('yuanbao'), isEmpty);
    final c = ProviderContainer();
    final mutation = c.read(growthRecordsMutationProvider);
    await mutation.add('my_cat', GrowthRecord(id: 'a', type: GrowthType.weight, date: DateTime(2026), value: '4.2'));
    await mutation.add('my_cat', GrowthRecord(id: 'a', type: GrowthType.weight, date: DateTime(2026), value: '4.3'));
    expect(GrowthRecordsRepository.get('my_cat').single.value, '4.3');
    expect(GrowthRecordsRepository.get('other_cat'), isEmpty);
    await Hive.box('growthRecords').close(); await Hive.openBox('growthRecords');
    expect(GrowthRecordsRepository.get('my_cat').length, 1);
    await mutation.remove('my_cat', 'a');
    expect(GrowthRecordsRepository.get('my_cat'), isEmpty);
    c.dispose();
  });

  test('invalid movie recipes cannot start encoding', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    expect(() => MovieExportRequest(slides: [bytes]).validate(), returnsNormally);
    expect(() => const MovieExportRequest().validate(), throwsArgumentError);
    expect(() => MovieExportRequest(slides: [bytes], videoBytes: bytes).validate(), throwsArgumentError);
    expect(() => MovieExportRequest(videoBytes: bytes, videoDurationMs: 31000).validate(), throwsArgumentError);
    expect(() => MovieExportRequest(slides: List.filled(9, bytes)).validate(), throwsArgumentError);
  });

  test('short videos persist an index and load bytes only on demand', () async {
    final c = ProviderContainer();
    final bytes = Uint8List.fromList([0, 1, 4, 5, 9]);
    await c.read(shortVideosProvider.notifier).add(ShortVideoEdit(videoBytes: bytes,
      trimStartMs: 0, trimEndMs: 3000, caption: '元宝日常', captionStyle: 0, rendered: true));
    final saved = c.read(shortVideosProvider).single;
    expect(saved.videoBytes, isEmpty);
    expect(await saved.readVideoBytes(), bytes);
    c.dispose();
    final restored = ProviderContainer();
    final edit = restored.read(shortVideosProvider).single;
    expect(edit.rendered, isTrue);
    expect(await edit.readVideoBytes(), bytes);
    await restored.read(shortVideosProvider.notifier).remove(edit);
    expect(restored.read(shortVideosProvider), isEmpty);
    restored.dispose();
  });

  testWidgets('movie editor starts empty and never offers an AI model', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: MoviePage())));
    expect(find.text('把日常，剪成珍藏'), findsOneWidget);
    expect(find.text('选照片'), findsOneWidget);
    expect(find.text('AI 一键成片'), findsNothing);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '制作并预览视频'));
    expect(button.onPressed, isNull);
  });

  testWidgets('an empty growth timeline can add a validated real record', (tester) async {
    const pet = Pet(id: 'local_cat', name: '我的猫', species: 'cat', breed: '家猫', birthday: '', avatarFileName: '', bio: '');
    await tester.pumpWidget(ProviderScope(overrides: [
      petsProvider.overrideWith((ref) async => [pet]),
      photosProvider.overrideWith((ref) async => []),
    ], child: MaterialApp(theme: ThemeData(extensions: const [AppTokens.light]), home: const PetProfilePage())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记体重')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'NaN');
    await tester.ensureVisible(find.text('保存')); await tester.tap(find.text('保存')); await tester.pumpAndSettle();
    expect(find.text('请输入0～30之间的有效体重(kg)'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '4.2');
    await tester.ensureVisible(find.text('保存'));
    await tester.runAsync(() async {
      await tester.tap(find.text('保存'));
      await Future<void>.delayed(const Duration(milliseconds: 350));
    });
    await tester.pumpAndSettle();
    expect(GrowthRecordsRepository.get('local_cat').single.value, '4.2');
  });
}
