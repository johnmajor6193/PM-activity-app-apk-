import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/pm_visit_failure.dart';

/// Opens the device's native camera — never the photo gallery — and
/// copies the captured image into this app's private storage so it
/// survives independently of the camera app's own temp file.
///
/// Using `ImageSource.camera` is what guarantees "camera only, no
/// gallery": `image_picker` never shows a gallery picker for this
/// source, it launches the device camera directly. A custom live
/// camera preview (the `camera` package) could replace this later if an
/// in-app GPS watermark overlay during capture is wanted, without
/// changing PmVisitController or the screen.
class CameraCaptureService {
  CameraCaptureService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Returns the saved local file path, or null if the engineer backed
  /// out of the camera without taking a photo.
  Future<String?> capturePhoto({required String visitId, required String categoryKey}) async {
    XFile? captured;
    try {
      captured = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
    } catch (error) {
      throw PmVisitFailure('Could not open the camera: $error');
    }

    if (captured == null) {
      return null;
    }

    final directory = await _visitPhotosDirectory(visitId);
    final extension = p.extension(captured.path).isEmpty ? '.jpg' : p.extension(captured.path);
    final destinationPath = p.join(
      directory.path,
      '$categoryKey-${DateTime.now().millisecondsSinceEpoch}$extension',
    );

    final savedFile = await File(captured.path).copy(destinationPath);
    return savedFile.path;
  }

  /// Removes a file this service saved (e.g. when GPS capture fails
  /// right after a successful photo, so no orphaned file is left behind).
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _visitPhotosDirectory(String visitId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(appDir.path, 'pm_visit_photos', visitId));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }
}
