import 'package:flutter/foundation.dart';

import '../data/camera_capture_service.dart';
import '../data/location_service.dart';
import '../data/sqflite_pm_visit_repository.dart';
import '../domain/entities/gps_reading.dart';
import '../domain/entities/pm_photo_record.dart';
import '../domain/entities/pm_visit.dart';
import '../domain/entities/photo_category.dart';
import '../domain/pm_visit_failure.dart';
import '../domain/repositories/pm_visit_repository.dart';

/// A photo the engineer just took, awaiting Retake/Confirm — not yet
/// saved to the repository.
class PendingPhotoReview {
  const PendingPhotoReview({
    required this.category,
    required this.localFilePath,
    required this.capturedAt,
    required this.gps,
  });

  final PhotoCategory category;
  final String localFilePath;
  final DateTime capturedAt;
  final GpsReading gps;
}

/// Drives the "Start PM Visit" screen: starting a visit for a POP,
/// capturing a live camera photo + a fresh live GPS fix per category,
/// and the Retake/Confirm review step.
///
/// Depends only on [PmVisitRepository] plus the camera/location
/// services, so adding GPS watermarking, Google Drive upload, or
/// geofence validation later does not require changing this controller
/// or the screen that uses it — only a new repository/service
/// implementation.
class PmVisitController extends ChangeNotifier {
  PmVisitController({
    PmVisitRepository? repository,
    CameraCaptureService? cameraService,
    LocationService? locationService,
  }) : _repository = repository ?? SqflitePmVisitRepository(),
       _cameraService = cameraService ?? CameraCaptureService(),
       _locationService = locationService ?? LocationService();

  final PmVisitRepository _repository;
  final CameraCaptureService _cameraService;
  final LocationService _locationService;

  PmVisit? visit;
  final Map<PhotoCategory, PmPhotoRecord> photosByCategory = {};
  PhotoCategory? categoryInProgress;
  PendingPhotoReview? pendingReview;
  String? errorMessage;

  bool get isStarted => visit != null;

  bool isCompleted(PhotoCategory category) => photosByCategory.containsKey(category);

  /// The PM visit cannot be submitted until every mandatory category has
  /// a confirmed photo.
  bool get allPhotosCompleted =>
      mandatoryPhotoCategories.every((category) => photosByCategory.containsKey(category));

  Future<void> startVisit({required int popId, required String popCode}) async {
    errorMessage = null;
    notifyListeners();
    try {
      final startedVisit = await _repository.startVisit(popId: popId, popCode: popCode);
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

  /// Opens the device camera, then captures a fresh GPS fix, for
  /// [category]. If the engineer backs out of the camera without taking
  /// a photo, nothing changes (category stays Pending, no error shown).
  Future<void> capturePhoto(PhotoCategory category) async {
    final currentVisit = visit;
    if (currentVisit == null) {
      return;
    }

    categoryInProgress = category;
    errorMessage = null;
    notifyListeners();

    String? filePath;
    try {
      filePath = await _cameraService.capturePhoto(
        visitId: currentVisit.id,
        categoryKey: category.storageKey,
      );
      if (filePath == null) {
        return;
      }

      // GPS is captured now, at the moment of this photo — not reused
      // from visit start or from any other photo.
      final gps = await _locationService.getCurrentGpsReading();
      pendingReview = PendingPhotoReview(
        category: category,
        localFilePath: filePath,
        capturedAt: DateTime.now(),
        gps: gps,
      );
    } on PmVisitFailure catch (failure) {
      errorMessage = failure.message;
      if (filePath != null) {
        await _cameraService.deleteFile(filePath);
      }
    } catch (_) {
      errorMessage = 'Something went wrong while capturing the photo.';
      if (filePath != null) {
        await _cameraService.deleteFile(filePath);
      }
    } finally {
      categoryInProgress = null;
      notifyListeners();
    }
  }

  /// Discards the pending photo without saving it. The category stays
  /// Pending; the engineer must capture again.
  void retake() {
    pendingReview = null;
    notifyListeners();
  }

  /// Persists the pending photo and marks its category Completed. On
  /// failure, the pending photo is discarded (same as retake) and an
  /// error is shown — the engineer must capture again rather than retry
  /// just the save.
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
      capturedAt: review.capturedAt,
      gps: review.gps,
    );

    try {
      await _repository.savePhoto(record);
      photosByCategory[review.category] = record;
    } catch (_) {
      errorMessage = 'Could not save the photo. Please retake it.';
    }
    pendingReview = null;
    notifyListeners();
  }
}
