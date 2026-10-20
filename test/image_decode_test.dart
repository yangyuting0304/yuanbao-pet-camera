// 限尺寸解码 —— 契约测试。
//
// 2026-10-20 用户实机反馈（iPhone 14 Pro Max）：「第一天还能拍，第二天直接
// 闪退，拍照模式很卡」。排查结论是**输出尺寸失控**：
//
// iOS 上 takePicture 的输出由 AVCaptureDevice 的 activeFormat 决定，
// camera_avfoundation 任何 ResolutionPreset 都只改 session preset，改不了
// activeFormat，于是拍出来就是 48MP。链路里每个消费点都曾用
// `img.decodeImage` 全尺寸解码 —— 48MP 铺成 RGBA 就是 192MB，
// 纯 Dart 解码还要 3~8 秒。
//
// 这里钉死三件事：
//   ① 限尺寸解码确实把像素缩到目标尺寸（而不是解完再缩）；
//   ② 坏数据不会把调用方带崩（返回 null，不抛异常）；
//   ③ 滤镜的「已解码像素」通路生效——输出尺寸就是给定的像素尺寸，
//      证明它没有偷偷去解全尺寸 JPEG。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pet_camera/data/image_decode.dart';
import 'package:pet_camera/data/pet_capture_profile.dart';
import 'package:pet_camera/data/pet_filter.dart';

void main() {
  group('限尺寸解码', () {
    test('把长边压到目标尺寸，且像素数与尺寸严格对应', () async {
      final src = img.Image(width: 2000, height: 1500, numChannels: 3);
      img.fill(src, color: img.ColorRgb8(120, 110, 100));
      final jpeg = img.encodeJpg(src, quality: 90);

      final out = await decodeRgbaLimited(jpeg, 500);
      expect(out, isNotNull);
      expect(out!.width, 500);
      expect(out.height, 375); // 等比
      expect(out.rgba.length, out.width * out.height * 4);
    });

    test('maxSide 为 0 时不缩放', () async {
      final src = img.Image(width: 300, height: 200, numChannels: 3);
      img.fill(src, color: img.ColorRgb8(10, 200, 30));
      final jpeg = img.encodeJpg(src, quality: 90);

      final out = await decodeRgbaLimited(jpeg, 0);
      expect(out, isNotNull);
      expect(out!.width, 300);
      expect(out.height, 200);
    });

    test('比目标尺寸小的图保持原尺寸（不放大）', () async {
      final src = img.Image(width: 120, height: 90, numChannels: 3);
      img.fill(src, color: img.ColorRgb8(5, 5, 5));
      final jpeg = img.encodeJpg(src, quality: 90);

      final out = await decodeRgbaLimited(jpeg, 800);
      expect(out, isNotNull);
      expect(out!.width, 120);
      expect(out.height, 90);
    });

    test('坏数据返回 null，不抛异常', () async {
      final out = await decodeRgbaLimited(
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        500,
      );
      expect(out, isNull);
    });

    test('空数据返回 null', () async {
      expect(await decodeRgbaLimited(Uint8List(0), 500), isNull);
    });
  });

  group('滤镜的已解码像素通路', () {
    test('输出尺寸就是给定的像素尺寸（没有再去解全尺寸 JPEG）', () {
      // 造一张 400×300 的像素图，故意与 JPEG 原图尺寸不同：
      // 若滤镜偷偷去解了 bytes，输出尺寸会变成 JPEG 的尺寸。
      final rgba = Uint8List(400 * 300 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 128;
        rgba[i + 1] = 120;
        rgba[i + 2] = 110;
        rgba[i + 3] = 255;
      }
      final profile = PetCaptureProfile.resolve(
        species: PetSpecies.cat,
        coat: PetCoat.tabby,
        scene: PetScene.portrait,
        look: PetLook.natural,
      );
      // 一张 2000×1500 的 JPEG 字节（只当"原图"占位，不会被解）
      final big = img.Image(width: 2000, height: 1500, numChannels: 3);
      img.fill(big, color: img.ColorRgb8(90, 90, 90));
      final jpeg = img.encodeJpg(big, quality: 90);

      final request = PetFilter.buildRequest(jpeg, profile);
      final withPixels = PetFilter.withRgba(request, rgba, 400, 300);
      final out = runPetFilter(withPixels);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 400);
      expect(decoded.height, 300);
    });
  });
}
