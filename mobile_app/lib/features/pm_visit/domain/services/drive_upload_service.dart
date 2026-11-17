import '../entities/pm_photo_record.dart';
import '../entities/pm_visit.dart';

/// What the future Google Drive upload step will implement: taking a
/// PENDING_SYNC (or retried SYNC_FAILED) visit and its confirmed photos
/// and uploading them under the District/Block folder convention.
///
/// Not implemented in this module — the only implementation that exists
/// today is NotImplementedDriveUploadService
/// (../../data/not_implemented_drive_upload_service.dart), which always
/// fails on purpose. SyncManager (../../data/sync_manager.dart) depends
/// only on this interface, so a real Drive-backed implementation can be
/// swapped in later without changing any sync queue/state logic.
abstract class DriveUploadService {
  /// Uploads [photos] (expected: all 5 mandatory categories) for
  /// [visit]. Throws on any failure — callers must not assume partial
  /// success.
  Future<void> uploadVisit(PmVisit visit, List<PmPhotoRecord> photos);
}
