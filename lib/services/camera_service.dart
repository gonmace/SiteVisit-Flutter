import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class CameraService {
  final _picker = ImagePicker();

  Future<File?> capturePhoto({int quality = 85}) async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: quality,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (xFile == null) return null;

    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${docsDir.path}/photos');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    final dest = File('${photosDir.path}/${const Uuid().v4()}.jpg');
    await File(xFile.path).copy(dest.path);
    return dest;
  }
}
