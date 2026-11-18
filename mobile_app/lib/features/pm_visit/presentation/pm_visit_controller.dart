import 'package:flutter/foundation.dart';

import '../data/camera_capture_service.dart';
import '../data/location_service.dart';
import '../data/sqflite_pm_visit_repository.dart';
import '../data/sync_manager.dart';
import '../data/watermark_service.dart';
import '../domain/entities/gps_reading.dart';
import '../domain/entities/pm_photo_record.dart';
import '../domain/entities/pm_visit.dart';
import '../domain/entities/photo_category.dart';
import '../domain/entities/visit_sync_status.dart';
import '../domain/pm_visit_failure.dart';
import '../domain/repositories/pm_visit_repository.dart';

/// A photo the engineer just took, awaiting Retake/Confirm — not yet
/// saved to the repository. [watermarkedFilePath] is the GPS-watermarked
/// evidence copy shown on the review screen; [localFilePath] is the
/// untouched original.
class PendingPhotoReview {
  const PendingPhotoReview({
    required this.category,
    required this.localFilePath,
    required this.watermarkedFilePath,
    required this.capturedAt,
    required this.gps,
  });

  final PhotoCategory category;
  final String localFilePath;
  final String watermarkedFilePath;
  final DateTime capturedAt;
  final GpsReading gps;
}

/// Drives both the "Start PM Visit" checklist screen and the
/// submission screen for a single visit: starting (or resuming) a
/// visit for a POP, capturing a live camera photo + a fresh live GPS
/// fix per category, burning that GPS fix into a watermark, the
/// Retake/Confirm review step, and — once the engineer explicitly
/// submits — moving the visit through the rest of its lifecycle (see
/// VisitSyncStatus) via the existing, unchanged sync pipeline.
///
/// Depends only on [PmVisitRepository] plus the camera/location/
/// watermark/sync services, so adding geofence validation later does
/// not require changing this controller or the screens that use it —
/// only a new service implementation.
class PmVisitController extends ChangeNotifier {
  factory PmVisitController({
    PmVisitRepository? repository,
    CameraCaptureService? cameraService,
    LocationService? locationService,
    WatermarkService? watermarkService,
    SyncManager? syncManager,
  }) {
    // Resolved once so the default SyncManager shares the same
    // repository instance as this controller, rather than each
    // constructing its own (functionally harmless either way, since
    // SqflitePmVisitRepository wraps a DB singleton, but wasteful).
    final resolvedRepository = repository ?? SqflitePmVisitRepository();
    return PmVisitController._(
      repository: resolvedRepository,
      cameraService: cameraService ?? CameraCaptureService(),
      locationService: locationService ?? LocationService(),
      watermarkService: watermarkService ?? WatermarkService(),
      syncManager: syncManager ?? SyncManager(repository: resolvedRepository),
    );
  }

  PmVisitController._({
    required PmVisitRepository repository,
    required CameraCaptureService cameraService,
    required LocationService locationService,
    required WatermarkService watermarkService,
    required SyncManager syncManager,
  }) : _repository = repository,
       _cameraService = cameraService,
       _locationService = locationService,
       _watermarkService = watermarkService,
       _syncManager = syncManager;

  final PmVisitRepository _repository;
  final CameraCaptureService _cameraService;
  final LocationService _locationService;
  final WatermarkService _watermarkService;
  final SyncManager _syncManager;

  PmVisit? visit;
  final Map<PhotoCategory, PmPhotoRecord> photosByCategory = {};
  PhotoCategory? categoryInProgress;
  PendingPhotoReview? pendingReview;
  String? errorMessage;
  bool isSyncing = false;
  String? syncMessage;

  bool get isStarted => visit != null;

  VisitSyncStatus? get visitStatus => visit?.status;

  bool isCompleted(PhotoCategory category) => photosByCategory.containsKey(category);

  /// Every mandatory category has a confirmed photo (presence only —
  /// use [allPhotosValidForSubmission] to also check GPS/watermark
  /// validity before allowing submission).
  bool get allPhotosCompleted =>
      mandatoryPhotoCategories.every((category) => photosByCategory.containsKey(category));

  /// True only when all 5 mandatory categories have a confirmed photo
  /// that is itself valid for submission — category, timestamp, a
  /// plausible GPS fix, the original path, and the watermarked path
  /// (see PmPhotoRecordValidation.isValidForSubmission). This is the
  /// actual gate [submitVisit] uses; [allPhotosCompleted] alone only
  /// checks that a row exists per category.
  bool get allPhotosValidForSubmission => mandatoryPhotoCategories.every((category) {
    final photo = photosByCategory[category];
    return photo != null && photo.isValidForSubmission;
  });

  /// The engineer may submit right now: every photo is present and
  /// valid, and the visit is either freshly ready for its first
  /// submission or retrying after a previous sync failure. `false` in
  /// every other state (including while already syncing, synced, or
  /// submitted) — this is what prevents a duplicate submission.
  bool get canSubmit =>
      visit != null &&
      allPhotosValidForSubmission &&
      (visit!.status == VisitSyncStatus.readyForSubmission ||
          visit!.status == VisitSyncStatus.syncFailed);

  /// Starts a new visit for [popId], or resumes the most recent
  /// not-yet-complete one on this device for the same POP — so closing
  /// and reopening the app mid-capture continues where the engineer
  /// left off instead of starting a duplicate visit.
  Future<void> startVisit({
    required String employeeId,
    required int popId,
    required String popCode,
    required String districtName,
    required String blockName,
    required String gpName,
  }) async {
    errorMessage = null;
    notifyListeners();
    try {
      final resumable = await _repository.getResumableVisit(popId);
      final startedVisit =
          resumable ??
          await _repository.startVisit(
            employeeId: employeeId,
            popId: popId,
            popCode: popCode,
            districtName: districtName,
            blockName: blockName,
            gpName: gpName,
          );
      final existingPhotos = await _repository.getPhotosForVisit(startedVisit.id);
      visit = startedVisit;
      photosByCategory
        ..clear()
        ..addAll(existingPhotos);
    } on PmVisitFailure catch (failure) {
      errorMessage = failure.message;
    } catch (_) {
      errorMessage = 'Could not start the PM visit. Please try again.';
    }
    notifyListeners();
  }

  /// Opens the device camera, captures a fresh GPS fix, then burns a
  /// watermark showing that same GPS fix into a copy of the photo — all
  /// for [category]. If the engineer backs out of the camera without
  /// taking a photo, nothing changes (category stays Pending, no error
  /// shown). If GPS cannot be obtained, no photo is left pending review:
  /// the category stays Pending and the GPS failure is shown via
  /// [errorMessage] — there is no way to confirm a photo for this
  /// category without a real GPS fix, and no fake coordinates are ever
  /// substituted.
  Future<void> capturePhoto(PhotoCategory category) async {
    final currentVisit = visit;
    if (currentVisit == null) {
      return;
    }

    categoryInProgress = category;
    errorMessage = null;
    notifyListeners();

    String? filePath;
    String? watermarkedPath;
    try {
      filePath = await _cameraService.capturePhoto(
        visitId: currentVisit.id,
        categoryKey: category.storageKey,
      );
      if (filePath == null) {
        return;
      }

      // GPS is captured now, at the moment of this photo — not reused
      // from visit start or from any other photo. If this fails, the
      // catch blocks below discard the photo and surface the failure;
      // no PendingPhotoReview is ever created without a real GPS fix.
      final gps = await _locationService.getCurrentGpsReading();
      final capturedAt = DateTime.now();

      // The watermark is burned in immediately, from this exact `gps`
      // value, so what the review screen shows and what gets saved can
      // never drift apart (requirement: watermark GPS must match the
      // stored GPS metadata for the same photo).
      watermarkedPath = await _watermarkService.applyWatermark(
        originalFilePath: filePath,
        popCode: currentVisit.popCode,
        category: category,
        capturedAt: capturedAt,
        gps: gps,
      );

      pendingReview = PendingPhotoReview(
        category: category,
        localFilePath: filePath,
        watermarkedFilePath: watermarkedPath,
        capturedAt: capturedAt,
        gps: gps,
      );
    } on PmVisitFailure catch (failure) {
      errorMessage = failure.message;
      await _deleteCapturedFiles(filePath, watermarkedPath);
    } catch (_) {
      errorMessage = 'Something went wrong while capturing the photo.';
      await _deleteCapturedFiles(filePath, watermarkedPath);
    } finally {
      categoryInProgress = null;
      notifyListeners();
    }
  }

  /// Discards the pending photo (and its watermarked copy) without
  /// saving it. The category stays Pending; the engineer must capture
  /// again.
  Future<void> retake() async {
    final review = pendingReview;
    pendingReview = null;
    notifyListeners();
    if (review != null) {
      await _deleteCapturedFiles(review.localFilePath, review.watermarkedFilePath);
    }
  }

  /// Persists the pending photo (original + watermarked evidence copy)
  /// and marks its category Completed. The visit moves draft ->
  /// inProgress on the first confirmed photo, and inProgress ->
  /// readyForSubmission once all 5 are confirmed and valid — both
  /// offline, with no network call. On failure, the pending photo is
  /// discarded (same as retake) and an error is shown — the engineer
  /// must capture again rather than retry just the save.
  Future<void> confirm() async {
    final currentVisit = visit;
    final review = pendingReview;
    if (currentVisit == null || review == null) {
      return;
    }

    final record = PmPhotoRecord(
      visitId: currentVisit.id,
      popId: currentVisit.popId,
      category: review.category,
      localFilePath: review.localFilePath,
      watermarkedFilePath: review.watermarkedFilePath,
      capturedAt: review.capturedAt,
      gps: review.gps,
    );

    try {
      await _repository.savePhoto(record);
      photosByCategory[review.category] = record;

      VisitSyncStatus? nextStatus;
      if (allPhotosValidForSubmission) {
        nextStatus = VisitSyncStatus.readyForSubmission;
      } else if (currentVisit.status == VisitSyncStatus.draft) {
        nextStatus = VisitSyncStatus.inProgress;
      }
      if (nextStatus != null && nextStatus != currentVisit.status) {
        await _repository.updateVisitStatus(currentVisit.id, nextStatus);
        visit = currentVisit.copyWithStatus(nextStatus);
      }
    } catch (_) {
      errorMessage = 'Could not save the photo. Please retake it.';
    }
    pendingReview = null;
    notifyListeners();
  }

  /// Submits the current visit: moves it from readyForSubmission (or
  /// retries from syncFailed) through pendingSync -> syncing ->
  /// synced -> submitted, using the existing, unchanged
  /// [SyncManager]/Google Drive pipeline — no second upload path is
  /// created here.
  ///
  /// Refuses (does nothing but set [errorMessage]) unless every photo
  /// is present and valid — this is what satisfies "the engineer must
  /// not be able to submit unless all five mandatory photographs
  /// exist". Refuses silently (no error; this is the duplicate-
  /// submission guard, not a validation failure) if the visit isn't in
  /// a submittable state, e.g. a second tap while already syncing, or
  /// after it has already reached synced/submitted.
  ///
  /// Safe to call again after a failure — [SyncManager] never deletes
  /// or modifies local photos/visit data on a failed or skipped
  /// attempt, so retrying just repeats the same call.
  Future<void> submitVisit() async {
    if (isSyncing) {
      return; // a submission is already in flight for this visit
    }
    final currentVisit = visit;
    if (currentVisit == null) {
      return;
    }
    if (!allPhotosValidForSubmission) {
      errorMessage =
          'All 5 mandatory photographs (with GPS and watermark) are required before this visit can be submitted.';
      notifyListeners();
      return;
    }
    final startStatus = currentVisit.status;
    if (startStatus != VisitSyncStatus.readyForSubmission &&
        startStatus != VisitSyncStatus.syncFailed) {
      return; // already submitted/syncing/synced - ignore a duplicate tap
    }

    // Set before the first await so a near-simultaneous second call
    // (e.g. a rapid double-tap) sees isSyncing already true.
    isSyncing = true;
    errorMessage = null;
    syncMessage = null;
    notifyListeners();

    var workingVisit = currentVisit;
    if (startStatus == VisitSyncStatus.readyForSubmission) {
      await _repository.updateVisitStatus(currentVisit.id, VisitSyncStatus.pendingSync);
      workingVisit = currentVisit.copyWithStatus(VisitSyncStatus.pendingSync);
      visit = workingVisit;
      notifyListeners();
    }

    // Optimistic: SyncManager writes `syncing` to the repository itself,
    // but has no reference to this controller, so without this the UI
    // would jump straight from "Pending Sync" to the final status.
    visit = workingVisit.copyWithStatus(VisitSyncStatus.syncing);
    notifyListeners();

    final result = await _syncManager.syncVisit(workingVisit);

    var refreshed = await _repository.getVisit(currentVisit.id);
    if (refreshed != null && refreshed.status == VisitSyncStatus.synced) {
      await _repository.updateVisitStatus(refreshed.id, VisitSyncStatus.submitted);
      refreshed = refreshed.copyWithStatus(VisitSyncStatus.submitted);
    }
    visit = refreshed ?? workingVisit;
    syncMessage = result.message ??
        (visit!.status == VisitSyncStatus.submitted ? 'Visit submitted successfully.' : null);
    isSyncing = false;
    notifyListeners();
  }

  Future<void> _deleteCapturedFiles(String? originalPath, String? watermarkedPath) async {
    if (originalPath != null) {
      await _cameraService.deleteFile(originalPath);
    }
    if (watermarkedPath != null) {
      await _cameraService.deleteFile(watermarkedPath);
    }
  }
}
