import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/pm_visit/data/camera_capture_service.dart';
import 'package:mobile_app/features/pm_visit/data/location_service.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/gps_reading.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/pm_photo_record.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/pm_visit.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/photo_category.dart';
import 'package:mobile_app/features/pm_visit/domain/pm_visit_failure.dart';
import 'package:mobile_app/features/pm_visit/domain/repositories/pm_visit_repository.dart';
import 'package:mobile_app/features/pm_visit/presentation/pm_visit_controller.dart';

/// In-memory stand-in for the real SQLite-backed repository, so the
/// controller's logic can be tested without a device database.
class _FakeRepository implements PmVisitRepository {
  final Map<String, Map<PhotoCategory, PmPhotoRecord>> _photosByVisit = {};
  int saveCallCount = 0;

  @override
  Future<PmVisit> startVisit({required int popId, required String popCode}) async {
    final visit = PmVisit(
      id: 'visit-$popId',
      popId: popId,
      popCode: popCode,
      startedAt: DateTime(2026, 1, 1),
    );
    _photosByVisit.putIfAbsent(visit.id, () => {});
    return visit;
  }

  @override
  Future<void> savePhoto(PmPhotoRecord record) async {
    saveCallCount++;
    _photosByVisit.putIfAbsent(record.visitId, () => {})[record.category] = record;
  }

  @override
  Future<Map<PhotoCategory, PmPhotoRecord>> getPhotosForVisit(String visitId) async {
    return Map.of(_photosByVisit[visitId] ?? {});
  }
}

/// Always "takes" a photo at a fixed fake path, never opens a real camera.
class _FakeCameraService extends CameraCaptureService {
  String? nextFilePath = '/fake/photo.jpg';
  bool throwOnCapture = false;
  final List<String> deletedPaths = [];

  @override
  Future<String?> capturePhoto({required String visitId, required String categoryKey}) async {
    if (throwOnCapture) {
      throw const PmVisitFailure('Could not open the camera: fake failure');
    }
    return nextFilePath;
  }

  @override
  Future<void> deleteFile(String path) async {
    deletedPaths.add(path);
  }
}

/// Returns a distinct fake GPS fix on each call (never the same twice),
/// so tests can tell a fresh per-photo call apart from a cached/reused
/// one. Never calls the real location API.
class _FakeLocationService extends LocationService {
  bool throwOnRead = false;
  int callCount = 0;

  @override
  Future<GpsReading> getCurrentGpsReading() async {
    if (throwOnRead) {
      throw const PmVisitFailure('Location permission is required to capture GPS for this photo.');
    }
    callCount++;
    return GpsReading(latitude: 10.0 + callCount, longitude: 20.0 + callCount, accuracyMeters: 5.0);
  }
}

void main() {
  late _FakeRepository repository;
  late _FakeCameraService camera;
  late _FakeLocationService location;
  late PmVisitController controller;

  setUp(() {
    repository = _FakeRepository();
    camera = _FakeCameraService();
    location = _FakeLocationService();
    controller = PmVisitController(
      repository: repository,
      cameraService: camera,
      locationService: location,
    );
  });

  test('startVisit creates a visit and loads any existing photos', () async {
    await controller.startVisit(popId: 42, popCode: 'POP-CHN-001');

    expect(controller.isStarted, isTrue);
    expect(controller.visit?.popId, 42);
    expect(controller.allPhotosCompleted, isFalse);
  });

  test('capturing and confirming a photo marks the category Completed', () async {
    await controller.startVisit(popId: 42, popCode: 'POP-CHN-001');

    await controller.capturePhoto(PhotoCategory.popRack);

    expect(controller.pendingReview, isNotNull);
    expect(controller.pendingReview!.category, PhotoCategory.popRack);
    expect(controller.isCompleted(PhotoCategory.popRack), isFalse);

    await controller.confirm();

    expect(controller.pendingReview, isNull);
    expect(controller.isCompleted(PhotoCategory.popRack), isTrue);
    expect(repository.saveCallCount, 1);
  });

  test('retake discards the pending photo without saving it', () async {
    await controller.startVisit(popId: 42, popCode: 'POP-CHN-001');
    await controller.capturePhoto(PhotoCategory.busbar);

    controller.retake();

    expect(controller.pendingReview, isNull);
    expect(controller.isCompleted(PhotoCategory.busbar), isFalse);
    expect(repository.saveCallCount, 0);
  });

  test('cancelling the camera leaves the category Pending with no error', () async {
    await controller.startVisit(popId: 42, popCode: 'POP-CHN-001');
    camera.nextFilePath = null; // simulates backing out of the camera

    await controller.capturePhoto(PhotoCategory.upsBattery);

    expect(controller.pendingReview, isNull);
    expect(controller.isCompleted(PhotoCategory.upsBattery), isFalse);
    expect(controller.errorMessage, isNull);
  });

  test('a GPS failure after capture surfaces an error and deletes the orphaned file', () async {
    await controller.startVisit(popId: 42, popCode: 'POP-CHN-001');
    location.throwOnRead = true;

    await controller.capturePhoto(PhotoCategory.earthPitChamber);

    expect(controller.pendingReview, isNull);
    expect(controller.isCompleted(PhotoCategory.earthPitChamber), isFalse);
    expect(controller.errorMessage, isNotNull);
    expect(camera.deletedPaths, contains('/fake/photo.jpg'));
  });

  test('allPhotosCompleted is only true once all 5 mandatory categories are confirmed', () async {
    await controller.startVisit(popId: 42, popCode: 'POP-CHN-001');

    for (final category in mandatoryPhotoCategories) {
      expect(controller.allPhotosCompleted, isFalse);
      await controller.capturePhoto(category);
      await controller.confirm();
    }

    expect(controller.allPhotosCompleted, isTrue);
    expect(controller.photosByCategory.length, 5);
  });

  test('GPS is captured fresh for every photo, not reused from the first one', () async {
    await controller.startVisit(popId: 42, popCode: 'POP-CHN-001');

    await controller.capturePhoto(PhotoCategory.popRack);
    final firstGps = controller.pendingReview!.gps;
    await controller.confirm();

    await controller.capturePhoto(PhotoCategory.busbar);
    final secondGps = controller.pendingReview!.gps;

    expect(location.callCount, 2);
    expect(firstGps.latitude, isNot(secondGps.latitude));
    expect(controller.photosByCategory[PhotoCategory.popRack]?.gps.latitude, firstGps.latitude);
  });
}
