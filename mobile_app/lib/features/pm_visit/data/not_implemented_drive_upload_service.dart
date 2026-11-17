import '../domain/entities/pm_photo_record.dart';
import '../domain/entities/pm_visit.dart';
import '../domain/pm_visit_failure.dart';
import '../domain/services/drive_upload_service.dart';

/// Placeholder [DriveUploadService]: Google Drive upload is not
/// implemented yet, so every call fails — on purpose.
///
/// This exists so the sync queue/retry state machine (SyncManager) can
/// be built and tested now, while guaranteeing nothing here ever claims
/// a photo was uploaded when it wasn't. Replace this with a real
/// Drive-backed implementation later; nothing else in this module
/// needs to change when that happens.
class NotImplementedDriveUploadService implements DriveUploadService {
  @override
  Future<void> uploadVisit(PmVisit visit, List<PmPhotoRecord> photos) async {
    throw const PmVisitFailure(
      'Google Drive upload is not implemented yet. This visit stays '
      'Pending Sync and can be retried once it is.',
    );
  }
}
