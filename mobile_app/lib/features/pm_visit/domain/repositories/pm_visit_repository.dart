import '../entities/pm_photo_record.dart';
import '../entities/pm_visit.dart';
import '../entities/photo_category.dart';
import '../entities/visit_sync_status.dart';

/// Local-only persistence for an in-progress PM visit and its photos.
///
/// There is no remote sync yet: everything here reads/writes the
/// on-device store only (see ../data/sqflite_pm_visit_repository.dart),
/// so a visit and its confirmed photos survive app restarts and need no
/// network connection.
abstract class PmVisitRepository {
  Future<PmVisit> startVisit({
    required String employeeId,
    required int popId,
    required String popCode,
    required String districtName,
    required String blockName,
    required String gpName,
  });

  /// The most recent not-yet-fully-captured visit (status `draft` or
  /// `inProgress`) for [popId] on this device, if any — used to resume
  /// capture after the app is closed and reopened, instead of starting
  /// a duplicate visit.
  Future<PmVisit?> getResumableVisit(int popId);

  /// Looks up a single visit by id.
  Future<PmVisit?> getVisit(String visitId);

  /// All visits currently in any of [statuses] — used by the sync
  /// engine to find visits eligible for sync (pendingSync and
  /// syncFailed).
  Future<List<PmVisit>> getVisitsByStatus(List<VisitSyncStatus> statuses);

  /// Updates just a visit's lifecycle status (e.g. draft -> inProgress
  /// as photos are confirmed, readyForSubmission -> pendingSync on
  /// submission, or during a sync attempt). Never touches its photos.
  Future<void> updateVisitStatus(String visitId, VisitSyncStatus status);

  /// Inserts the confirmed photo for `record.category`, or replaces it
  /// if that category was already captured for this visit (retake).
  Future<void> savePhoto(PmPhotoRecord record);

  /// All confirmed photos for a visit, keyed by category.
  Future<Map<PhotoCategory, PmPhotoRecord>> getPhotosForVisit(String visitId);
}
