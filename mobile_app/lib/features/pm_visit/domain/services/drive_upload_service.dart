import '../entities/pm_photo_record.dart';
import '../entities/pm_visit.dart';

/// Uploads a PENDING_SYNC (or retried SYNC_FAILED) visit's confirmed
/// photos, via the backend's `/visits/{id}/sync` endpoint, under the
/// District/Block/GP/POP folder convention — see GoogleDriveUploadService
/// (../../data/google_drive_upload_service.dart), the default/real
/// implementation. NotImplementedDriveUploadService
/// (../../data/not_implemented_drive_upload_service.dart) remains
/// available to pass explicitly instead (e.g. developing with no
/// backend reachable); it always fails on purpose. SyncManager
/// (../../data/sync_manager.dart) depends only on this interface, so
/// either implementation can be swapped in without changing any sync
/// queue/state logic.
abstract class DriveUploadService {
  /// Uploads [photos] (expected: all 5 mandatory categories) for
  /// [visit]. Throws on any failure — callers must not assume partial
  /// success.
  Future<void> uploadVisit(PmVisit visit, List<PmPhotoRecord> photos);
}
