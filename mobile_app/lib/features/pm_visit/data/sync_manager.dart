import '../domain/entities/pm_visit.dart';
import '../domain/entities/visit_sync_status.dart';
import '../domain/repositories/pm_visit_repository.dart';
import '../domain/services/drive_upload_service.dart';
import 'connectivity_service.dart';
import 'google_drive_upload_service.dart';

/// How one sync attempt for a single visit ended.
enum SyncOutcome {
  /// Upload succeeded; the visit is now SYNCED.
  synced,

  /// Upload was attempted and failed; the visit is now SYNC_FAILED.
  /// Nothing local was deleted — it stays eligible for retry.
  failed,

  /// No attempt was made because the device has no connection right
  /// now. The visit's status is left exactly as it was.
  skippedNoConnection,
}

/// The outcome of one sync attempt, plus a message safe to show the
/// engineer (e.g. why it failed, or that there's no connection).
class SyncAttemptResult {
  const SyncAttemptResult({required this.outcome, this.message});

  final SyncOutcome outcome;
  final String? message;
}

/// Finds PM visits eligible for synchronization (PENDING_SYNC and
/// SYNC_FAILED) and attempts to sync them, retry-safely.
///
/// A failed or skipped attempt never deletes or modifies local photos
/// or visit data beyond the `status` column, so calling this again
/// later (once connectivity returns, or once a real Drive upload
/// service exists) always has the same visits/photos to work with.
///
/// Depends only on [PmVisitRepository] and [DriveUploadService], so
/// swapping [GoogleDriveUploadService] (the default — calls the
/// backend's `/visits/{id}/sync` endpoint; see that class for why this
/// app never talks to Google Drive directly) for
/// `NotImplementedDriveUploadService` (e.g. when developing without a
/// reachable backend) needs no change here — just pass it explicitly.
class SyncManager {
  SyncManager({
    required PmVisitRepository repository,
    DriveUploadService? driveUploadService,
    ConnectivityService? connectivityService,
  }) : _repository = repository,
       _driveUploadService = driveUploadService ?? GoogleDriveUploadService(),
       _connectivityService = connectivityService ?? ConnectivityService();

  final PmVisitRepository _repository;
  final DriveUploadService _driveUploadService;
  final ConnectivityService _connectivityService;

  static const _eligibleStatuses = [VisitSyncStatus.pendingSync, VisitSyncStatus.syncFailed];

  /// Visits currently eligible for sync: PENDING_SYNC (never attempted,
  /// or completed since a previous failure) and SYNC_FAILED (safe to
  /// retry).
  Future<List<PmVisit>> getVisitsEligibleForSync() {
    return _repository.getVisitsByStatus(_eligibleStatuses);
  }

  /// Attempts to sync every currently eligible visit. One visit's
  /// failure does not stop the others from being attempted.
  Future<Map<String, SyncAttemptResult>> trySyncPendingVisits() async {
    final eligible = await getVisitsEligibleForSync();
    final outcomes = <String, SyncAttemptResult>{};
    for (final visit in eligible) {
      outcomes[visit.id] = await syncVisit(visit);
    }
    return outcomes;
  }

  /// Retry-safe sync of a single visit.
  ///
  /// If there is no connection, nothing is attempted and [visit]'s
  /// status is left untouched. Otherwise: PENDING_SYNC/SYNC_FAILED ->
  /// SYNCING -> SYNCED (success) or back to SYNC_FAILED (failure).
  /// Local photos and the visit row are never deleted, and no column
  /// other than `status` is ever modified by this method.
  Future<SyncAttemptResult> syncVisit(PmVisit visit) async {
    if (!await _connectivityService.hasConnection()) {
      return const SyncAttemptResult(
        outcome: SyncOutcome.skippedNoConnection,
        message: 'No internet connection. This visit stays Pending Sync '
            'and will be eligible to retry once you are back online.',
      );
    }

    await _repository.updateVisitStatus(visit.id, VisitSyncStatus.syncing);
    try {
      final photos = await _repository.getPhotosForVisit(visit.id);
      await _driveUploadService.uploadVisit(visit, photos.values.toList());
      await _repository.updateVisitStatus(visit.id, VisitSyncStatus.synced);
      return const SyncAttemptResult(outcome: SyncOutcome.synced);
    } catch (error) {
      await _repository.updateVisitStatus(visit.id, VisitSyncStatus.syncFailed);
      return SyncAttemptResult(outcome: SyncOutcome.failed, message: error.toString());
    }
  }
}
