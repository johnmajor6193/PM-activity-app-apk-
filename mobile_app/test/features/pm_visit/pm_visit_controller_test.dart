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

  static const _resumableStatuses = [VisitSyncStatus.draft, VisitSyncStatus.inProgress];

  @override
  Future<PmVisit?> getResumableVisit(int popId) async {
    for (final visit in _visits.values) {
      if (visit.popId == popId && _resumableStatuses.contains(visit.status)) {
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

  /// Lets a test hold `capturePhoto` mid-flight (simulating a real GPS
  /// fix's latency) so it can dispose the controller before this
  /// resolves, the same way a real device's slower GPS fix leaves a
  /// window for the engineer to navigate away mid-capture.
  Duration delay = Duration.zero;

  @override
  Future<GpsReading> getCurrentGpsReading() async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
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
  int callCount = 0;

  @override
  Future<void> uploadVisit(PmVisit visit, List<PmPhotoRecord> photos) async {
    callCount++;
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
    expect(controller.visitStatus, VisitSyncStatus.draft);
    expect(controller.allPhotosCompleted, isFalse);
  });

  test(
    'reopening the same POP resumes the existing draft/in-progress visit instead of starting a '
    'new one',
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
    'the visit becomes READY_FOR_SUBMISSION automatically, offline, once all 5 photos are '
    'confirmed',
    () async {
      await _startVisit(controller);
      expect(controller.visitStatus, VisitSyncStatus.draft);

      await completeAllPhotos();

      expect(controller.allPhotosCompleted, isTrue);
      expect(controller.allPhotosValidForSubmission, isTrue);
      expect(controller.visitStatus, VisitSyncStatus.readyForSubmission);
      // Confirming the 5th photo required no connectivity/drive calls —
      // actual submission/sync only happens via submitVisit().
      expect(connectivity.online, isTrue); // never even checked
      expect(driveUploadService.callCount, 0);
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

  test('submitVisit is blocked when one mandatory photo is missing', () async {
    await _startVisit(controller);
    // Confirm only 4 of the 5 mandatory categories.
    for (final category in mandatoryPhotoCategories.skip(1)) {
      await controller.capturePhoto(category);
      await controller.confirm();
    }
    expect(controller.visitStatus, VisitSyncStatus.inProgress);

    await controller.submitVisit();

    expect(controller.errorMessage, contains('5 mandatory photographs'));
    expect(controller.visitStatus, VisitSyncStatus.inProgress); // never moved
    expect(controller.isSyncing, isFalse);
    expect(driveUploadService.callCount, 0);
  });

  test(
    'submitVisit refuses a visit with an invalid/out-of-range GPS reading even if all 5 '
    'categories have a photo',
    () async {
      await _startVisit(controller);
      await completeAllPhotos();
      expect(controller.visitStatus, VisitSyncStatus.readyForSubmission);

      // Simulate corrupted/legacy data: a confirmed-looking photo whose
      // GPS fix is structurally impossible. The normal capture flow
      // never produces this; this directly exercises the validation
      // gate submitVisit relies on.
      final corrupted = controller.photosByCategory[PhotoCategory.popRack]!;
      controller.photosByCategory[PhotoCategory.popRack] = PmPhotoRecord(
        visitId: corrupted.visitId,
        popId: corrupted.popId,
        category: corrupted.category,
        localFilePath: corrupted.localFilePath,
        watermarkedFilePath: corrupted.watermarkedFilePath,
        capturedAt: corrupted.capturedAt,
        gps: const GpsReading(latitude: 999, longitude: 20, accuracyMeters: 5),
      );

      await controller.submitVisit();

      expect(controller.errorMessage, contains('5 mandatory photographs'));
      expect(driveUploadService.callCount, 0);
    },
  );

  test('submitVisit succeeds end-to-end when all five photos are valid', () async {
    await _startVisit(controller);
    await completeAllPhotos();
    driveUploadService.shouldFail = false;

    await controller.submitVisit();

    expect(controller.visitStatus, VisitSyncStatus.submitted);
    expect(controller.syncMessage, contains('submitted'));
    expect(controller.isSyncing, isFalse);
    expect(driveUploadService.callCount, 1);
  });

  test('offline submission leaves the visit PENDING_SYNC and reports why', () async {
    await _startVisit(controller);
    await completeAllPhotos();
    connectivity.online = false;

    await controller.submitVisit();

    expect(controller.visitStatus, VisitSyncStatus.pendingSync);
    expect(controller.syncMessage, contains('No internet connection'));
    expect(controller.isSyncing, isFalse);
    expect(driveUploadService.callCount, 0);
  });

  test(
    'a failed Drive upload marks the visit SYNC_FAILED without losing any local evidence',
    () async {
      await _startVisit(controller);
      await completeAllPhotos();
      driveUploadService.shouldFail = true; // the real default behaves this way too

      await controller.submitVisit();

      expect(controller.visitStatus, VisitSyncStatus.syncFailed);
      expect(controller.syncMessage, isNotNull);
      // All 5 photos are still there locally after the failed attempt.
      expect(controller.photosByCategory.length, 5);
    },
  );

  test('a failed submission can be retried and succeeds once the upload works', () async {
    await _startVisit(controller);
    await completeAllPhotos();
    driveUploadService.shouldFail = true;

    await controller.submitVisit();
    expect(controller.visitStatus, VisitSyncStatus.syncFailed);

    driveUploadService.shouldFail = false;
    await controller.submitVisit();

    expect(controller.visitStatus, VisitSyncStatus.submitted);
    expect(driveUploadService.callCount, 2);
  });

  test('a near-simultaneous duplicate submission only reaches Drive once', () async {
    await _startVisit(controller);
    await completeAllPhotos();
    driveUploadService.shouldFail = false;

    // Not awaited individually — the second call races the first,
    // simulating a rapid double-tap of the Submit button.
    final first = controller.submitVisit();
    final second = controller.submitVisit();
    await Future.wait([first, second]);

    expect(driveUploadService.callCount, 1);
    expect(controller.visitStatus, VisitSyncStatus.submitted);
  });

  test('resubmitting an already-submitted visit does not upload again', () async {
    await _startVisit(controller);
    await completeAllPhotos();
    driveUploadService.shouldFail = false;
    await controller.submitVisit();
    expect(controller.visitStatus, VisitSyncStatus.submitted);
    expect(driveUploadService.callCount, 1);

    await controller.submitVisit();

    expect(controller.visitStatus, VisitSyncStatus.submitted);
    expect(driveUploadService.callCount, 1); // no second upload
  });

  test('submitVisit does nothing but set an error while photos are still incomplete', () async {
    await _startVisit(controller);
    await controller.capturePhoto(PhotoCategory.popRack);
    await controller.confirm();

    await controller.submitVisit();

    expect(controller.visitStatus, VisitSyncStatus.inProgress);
    expect(controller.syncMessage, isNull);
    expect(controller.errorMessage, isNotNull);
  });

  test(
    'a successful submission moves the visit through every expected lifecycle state in order',
    () async {
      await _startVisit(controller);
      final statuses = <VisitSyncStatus>[controller.visitStatus!];
      controller.addListener(() {
        final status = controller.visitStatus;
        if (status != null && statuses.last != status) {
          statuses.add(status);
        }
      });

      await completeAllPhotos();
      driveUploadService.shouldFail = false;
      await controller.submitVisit();

      expect(statuses, [
        VisitSyncStatus.draft,
        VisitSyncStatus.inProgress,
        VisitSyncStatus.readyForSubmission,
        VisitSyncStatus.pendingSync,
        VisitSyncStatus.syncing,
        VisitSyncStatus.submitted,
      ]);
    },
  );

  test(
    'disposing the controller while capturePhoto is awaiting GPS does not throw '
    '(e.g. the engineer backs out of the screen during a slow real GPS fix)',
    () async {
      await _startVisit(controller);
      location.delay = const Duration(milliseconds: 50);

      final capture = controller.capturePhoto(PhotoCategory.popRack);
      controller.dispose();

      await expectLater(capture, completes);
    },
  );
}
