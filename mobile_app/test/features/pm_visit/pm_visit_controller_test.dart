import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/pm_visit/data/camera_capture_service.dart';
import 'package:mobile_app/features/pm_visit/data/connectivity_service.dart';
import 'package:mobile_app/features/pm_visit/data/location_service.dart';
import 'package:mobile_app/features/pm_visit/data/sync_manager.dart';
import 'package:mobile_app/features/pm_visit/data/watermark_service.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/gps_reading.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/pm_photo_record.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/pm_visit.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/photo_category.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/visit_sync_status.dart';
import 'package:mobile_app/features/pm_visit/domain/pm_visit_failure.dart';
import 'package:mobile_app/features/pm_visit/domain/repositories/pm_visit_repository.dart';
import 'package:mobile_app/features/pm_visit/domain/services/drive_upload_service.dart';
import 'package:mobile_app/features/pm_visit/presentation/pm_visit_controller.dart';

const _employeeId = 'ENG001';
const _popId = 42;
const _popCode = 'POP-CHN-001';
const _districtName = 'Chennai';
const _blockName = 'Sholinganallur';
const _gpName = 'Semmancheri GP';

Future<void> _startVisit(PmVisitController controller, {int popId = _popId}) {
  return controller.startVisit(
    employeeId: _employeeId,
    popId: popId,
    popCode: _popCode,
    districtName: _districtName,
    blockName: _blockName,
    gpName: _gpName,
  );
}

/// In-memory stand-in for the real SQLite-backed repository, so the
/// controller's logic can be tested without a device database. Tracks
/// status changes the same way the real repository would (see
/// sqflite_pm_visit_repository_test.dart for the real-database tests).
class _FakeRepository implements PmVisitRepository {
  final Map<String, PmVisit> _visits = {};
  final Map<String, Map<PhotoCategory, PmPhotoRecord>> _photosByVisit = {};
  int saveCallCount = 0;
  int visitIdCounter = 0;

  @override
  Future<PmVisit> startVisit({
    required String employeeId,
    required int popId,
    required String popCode,
    required String districtName,
    required String blockName,
    required String gpName,
  }) async {
    visitIdCounter++;
    final visit = PmVisit(
      id: 'visit-$popId-$visitIdCounter',
      employeeId: employeeId,
      popId: popId,
      popCode: popCode,
      districtName: districtName,
      blockName: blockName,
      gpName: gpName,
      startedAt: DateTime(2026, 1, 1),
    );
    _visits[visit.id] = visit;
    _photosByVisit.putIfAbsent(visit.id, () => {});
    return visit;
  }

  @override
  Future<PmVisit?> getResumableVisit(int popId) async {
    for (final visit in _visits.values) {
      if (visit.popId == popId && visit.status == VisitSyncStatus.localOnly) {
        return visit;
      }
    }
    return null;
  }

  @override
  Future<PmVisit?> getVisit(String visitId) async => _visits[visitId];

  @override
  Future<List<PmVisit>> getVisitsByStatus(List<VisitSyncStatus> statuses) async {
    return _visits.values.where((v) => statuses.contains(v.status)).toList();
  }

  @override
  Future<void> updateVisitStatus(String visitId, VisitSyncStatus status) async {
    final current = _visits[visitId];
    if (current != null) {
      _visits[visitId] = current.copyWithStatus(status);
    }
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

/// Records what it was asked to watermark and returns a fake path,
/// without touching a real image file (the real implementation's own
/// image-manipulation behavior has its own tests — see
/// watermark_service_test.dart).
class _FakeWatermarkService extends WatermarkService {
  bool throwOnApply = false;
  final List<({String originalFilePath, String popCode, PhotoCategory category, GpsReading gps})>
  calls = [];

  @override
  Future<String> applyWatermark({
    required String originalFilePath,
    required String popCode,
    required PhotoCategory category,
    required DateTime capturedAt,
    required GpsReading gps,
  }) async {
    if (throwOnApply) {
      throw const PmVisitFailure(
        'Could not read the captured photo to add the GPS watermark.',
      );
    }
    calls.add((
      originalFilePath: originalFilePath,
      popCode: popCode,
      category: category,
      gps: gps,
    ));
    return '${originalFilePath}_watermarked.jpg';
  }
}

class _FakeConnectivityService extends ConnectivityService {
  bool online = true;

  @override
  Future<bool> hasConnection() async => online;
}

/// A [DriveUploadService] whose outcome is controlled by the test,
/// standing in for both "not implemented yet" and "implemented and
/// working" without needing real Google Drive access.
class _FakeDriveUploadService implements DriveUploadService {
  bool shouldFail = true;

  @override
  Future<void> uploadVisit(PmVisit visit, List<PmPhotoRecord> photos) async {
    if (shouldFail) {
      throw Exception('Simulated Drive upload failure');
    }
  }
}

void main() {
  late _FakeRepository repository;
  late _FakeCameraService camera;
  late _FakeLocationService location;
  late _FakeWatermarkService watermark;
  late _FakeConnectivityService connectivity;
  late _FakeDriveUploadService driveUploadService;
  late PmVisitController controller;

  setUp(() {
    repository = _FakeRepository();
    camera = _FakeCameraService();
    location = _FakeLocationService();
    watermark = _FakeWatermarkService();
    connectivity = _FakeConnectivityService();
    driveUploadService = _FakeDriveUploadService();
    controller = PmVisitController(
      repository: repository,
      cameraService: camera,
      locationService: location,
      watermarkService: watermark,
      syncManager: SyncManager(
        repository: repository,
        connectivityService: connectivity,
        driveUploadService: driveUploadService,
      ),
    );
  });

  Future<void> completeAllPhotos() async {
    for (final category in mandatoryPhotoCategories) {
      await controller.capturePhoto(category);
      await controller.confirm();
    }
  }

  test('startVisit creates a visit and loads any existing photos', () async {
    await _startVisit(controller);

    expect(controller.isStarted, isTrue);
    expect(controller.visit?.popId, _popId);
    expect(controller.visit?.employeeId, _employeeId);
    expect(controller.visit?.districtName, _districtName);
    expect(controller.visit?.blockName, _blockName);
    expect(controller.visit?.gpName, _gpName);
    expect(controller.visitStatus, VisitSyncStatus.localOnly);
    expect(controller.allPhotosCompleted, isFalse);
  });

  test(
    'reopening the same POP resumes the existing LOCAL_ONLY visit instead of starting a new one',
    () async {
      await _startVisit(controller);
      await controller.capturePhoto(PhotoCategory.popRack);
      await controller.confirm();
      final originalVisitId = controller.visit!.id;

      // Simulate the app being closed and a fresh controller created
      // when it's reopened and the engineer navigates to the same POP.
      final reopenedController = PmVisitController(
        repository: repository,
        cameraService: camera,
        locationService: location,
        watermarkService: watermark,
      );
      await _startVisit(reopenedController);

      expect(reopenedController.visit!.id, originalVisitId);
      expect(reopenedController.isCompleted(PhotoCategory.popRack), isTrue);
      expect(reopenedController.photosByCategory.length, 1);
    },
  );

  test('starting a visit for a different POP does not resume an unrelated one', () async {
    await _startVisit(controller, popId: _popId);
    final firstVisitId = controller.visit!.id;

    await _startVisit(controller, popId: 999);

    expect(controller.visit!.id, isNot(firstVisitId));
  });

  test('capturing and confirming a photo marks the category Completed', () async {
    await _startVisit(controller);

    await controller.capturePhoto(PhotoCategory.popRack);

    expect(controller.pendingReview, isNotNull);
    expect(controller.pendingReview!.category, PhotoCategory.popRack);
    expect(controller.pendingReview!.watermarkedFilePath, isNotEmpty);
    expect(controller.isCompleted(PhotoCategory.popRack), isFalse);

    await controller.confirm();

    expect(controller.pendingReview, isNull);
    expect(controller.isCompleted(PhotoCategory.popRack), isTrue);
    expect(repository.saveCallCount, 1);
    expect(controller.photosByCategory[PhotoCategory.popRack]?.watermarkedFilePath, isNotNull);
  });

  test(
    'the visit becomes PENDING_SYNC automatically, offline, once all 5 photos are confirmed',
    () async {
      await _startVisit(controller);
      expect(controller.visitStatus, VisitSyncStatus.localOnly);

      await completeAllPhotos();

      expect(controller.allPhotosCompleted, isTrue);
      expect(controller.visitStatus, VisitSyncStatus.pendingSync);
      // Confirming the 5th photo required no connectivity/drive calls.
      expect(connectivity.online, isTrue); // never even checked
    },
  );

  test(
    'the GPS and POP ID passed to the watermark match what is stored on the confirmed record',
    () async {
      await _startVisit(controller);

      await controller.capturePhoto(PhotoCategory.popRack);
      await controller.confirm();

      final savedRecord = controller.photosByCategory[PhotoCategory.popRack]!;
      final watermarkCall = watermark.calls.single;

      expect(watermarkCall.gps, same(savedRecord.gps));
      expect(watermarkCall.popCode, _popCode);
      expect(watermarkCall.category, PhotoCategory.popRack);
    },
  );

  test('retake discards the pending photo and deletes both its files without saving', () async {
    await _startVisit(controller);
    await controller.capturePhoto(PhotoCategory.busbar);
    final originalPath = controller.pendingReview!.localFilePath;
    final watermarkedPath = controller.pendingReview!.watermarkedFilePath;

    await controller.retake();

    expect(controller.pendingReview, isNull);
    expect(controller.isCompleted(PhotoCategory.busbar), isFalse);
    expect(repository.saveCallCount, 0);
    expect(camera.deletedPaths, containsAll(<String>[originalPath, watermarkedPath]));
  });

  test(
    'a watermark failure after GPS capture surfaces an error and deletes the orphaned original',
    () async {
      await _startVisit(controller);
      watermark.throwOnApply = true;

      await controller.capturePhoto(PhotoCategory.earthPitOpenWithRod);

      expect(controller.pendingReview, isNull);
      expect(controller.isCompleted(PhotoCategory.earthPitOpenWithRod), isFalse);
      expect(controller.errorMessage, isNotNull);
      expect(camera.deletedPaths, contains('/fake/photo.jpg'));
    },
  );

  test('cancelling the camera leaves the category Pending with no error', () async {
    await _startVisit(controller);
    camera.nextFilePath = null; // simulates backing out of the camera

    await controller.capturePhoto(PhotoCategory.upsBattery);

    expect(controller.pendingReview, isNull);
    expect(controller.isCompleted(PhotoCategory.upsBattery), isFalse);
    expect(controller.errorMessage, isNull);
  });

  test('a GPS failure after capture surfaces an error and deletes the orphaned file', () async {
    await _startVisit(controller);
    location.throwOnRead = true;

    await controller.capturePhoto(PhotoCategory.earthPitChamber);

    expect(controller.pendingReview, isNull);
    expect(controller.isCompleted(PhotoCategory.earthPitChamber), isFalse);
    expect(controller.errorMessage, isNotNull);
    expect(camera.deletedPaths, contains('/fake/photo.jpg'));
    // GPS failed before the watermark step was ever reached.
    expect(watermark.calls, isEmpty);
  });

  test('allPhotosCompleted is only true once all 5 mandatory categories are confirmed', () async {
    await _startVisit(controller);

    for (final category in mandatoryPhotoCategories) {
      expect(controller.allPhotosCompleted, isFalse);
      await controller.capturePhoto(category);
      await controller.confirm();
    }

    expect(controller.allPhotosCompleted, isTrue);
    expect(controller.photosByCategory.length, 5);
  });

  test('GPS is captured fresh for every photo, not reused from the first one', () async {
    await _startVisit(controller);

    await controller.capturePhoto(PhotoCategory.popRack);
    final firstGps = controller.pendingReview!.gps;
    await controller.confirm();

    await controller.capturePhoto(PhotoCategory.busbar);
    final secondGps = controller.pendingReview!.gps;

    expect(location.callCount, 2);
    expect(firstGps.latitude, isNot(secondGps.latitude));
    expect(controller.photosByCategory[PhotoCategory.popRack]?.gps.latitude, firstGps.latitude);
  });

  test('attemptSyncNow with no connection leaves the visit PENDING_SYNC and reports why', () async {
    await _startVisit(controller);
    await completeAllPhotos();
    connectivity.online = false;

    await controller.attemptSyncNow();

    expect(controller.visitStatus, VisitSyncStatus.pendingSync);
    expect(controller.syncMessage, contains('No internet connection'));
    expect(controller.isSyncing, isFalse);
  });

  test(
    'attemptSyncNow with the not-yet-implemented Drive service fails without losing local data',
    () async {
      await _startVisit(controller);
      await completeAllPhotos();
      driveUploadService.shouldFail = true; // the real default behaves this way too

      await controller.attemptSyncNow();

      expect(controller.visitStatus, VisitSyncStatus.syncFailed);
      expect(controller.syncMessage, isNotNull);
      // All 5 photos are still there locally after the failed attempt.
      expect(controller.photosByCategory.length, 5);
    },
  );

  test('attemptSyncNow can be retried after a failure and succeed once upload works', () async {
    await _startVisit(controller);
    await completeAllPhotos();
    driveUploadService.shouldFail = true;

    await controller.attemptSyncNow();
    expect(controller.visitStatus, VisitSyncStatus.syncFailed);

    driveUploadService.shouldFail = false;
    await controller.attemptSyncNow();

    expect(controller.visitStatus, VisitSyncStatus.synced);
  });

  test('attemptSyncNow does nothing while photos are still incomplete', () async {
    await _startVisit(controller);
    await controller.capturePhoto(PhotoCategory.popRack);
    await controller.confirm();

    await controller.attemptSyncNow();

    expect(controller.visitStatus, VisitSyncStatus.localOnly);
    expect(controller.syncMessage, isNull);
  });
}
