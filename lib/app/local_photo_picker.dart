import 'package:file_picker/file_picker.dart';
import 'package:pet_camera/data/ai_portrait_service.dart';
import 'package:pet_camera/data/prepare_local_photo.dart';

Future<SourcePhoto?> pickLocalPhoto() async {
  final files = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  if (files == null) return null;
  final file = files.files.single;
  if (file.bytes == null || file.size > 25 * 1024 * 1024) {
    throw StateError('请选择25MB以内的照片');
  }
  return SourcePhoto(
    bytes: await prepareLocalPhoto(file.bytes!),
    caption: '我的照片',
  );
}
