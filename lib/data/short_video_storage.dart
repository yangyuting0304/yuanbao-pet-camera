import 'dart:typed_data';
import 'short_video_storage_web.dart'
    if (dart.library.io) 'short_video_storage_io.dart'
    as impl;

Future<String> storeShortVideo(String name, Uint8List bytes) =>
    impl.store(name, bytes);
Future<Uint8List> readShortVideo(String ref) => impl.read(ref);
Future<void> deleteShortVideo(String ref) => impl.remove(ref);
