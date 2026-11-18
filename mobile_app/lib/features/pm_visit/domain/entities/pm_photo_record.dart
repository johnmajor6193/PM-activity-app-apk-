import 'gps_reading.dart';
import 'photo_category.dart';

/// Tracks whether a confirmed photo has been synced anywhere yet.
/// Deliberately per-photo-granularity-ready, but nothing sets this past
/// `pending` today: Google Drive upload (see GoogleDriveUploadService)
/// and SyncManager only ever update the visit-level VisitSyncStatus,
/// not this field — see docs/data-model.md.
enum PhotoUploadStatus { pending, uploaded, failed }

/// A single captured, engineer-confirmed PM visit photograph, with
/// everything required to store and later sync it.
///
/// [watermarkedFilePath] is the GPS-watermarked evidence copy of
/// [localFilePath] (the untouched original) — see WatermarkService. It
/// is populated for every photo confirmed from this point on; it stays
/// nullable because older local rows, if any existed before this was
/// added, have none.
///
/// [driveFileId] and [driveFileLink] are reserved for the later Google
/// Drive upload step and are always null today.
class PmPhotoRecord {
  const PmPhotoRecord({
    required this.visitId,
    required this.popId,
    required this.category,
    required this.localFilePath,
    required this.capturedAt,
    required this.gps,
    this.uploadStatus = PhotoUploadStatus.pending,
    this.watermarkedFilePath,
    this.driveFileId,
    this.driveFileLink,
  });

  final String visitId;
  final int popId;
  final PhotoCategory category;
  final String localFilePath;
  final DateTime capturedAt;
  final GpsReading gps;
  final PhotoUploadStatus uploadStatus;
  final String? watermarkedFilePath;
  final String? driveFileId;
  final String? driveFileLink;
}

extension PmPhotoRecordValidation on PmPhotoRecord {
  /// True only if this record has everything a PM visit submission
  /// requires for this category: a non-empty original path, a
  /// non-empty watermarked path, and a plausible GPS fix. `category`
  /// and `capturedAt` are always present by construction (non-nullable
  /// fields), so they need no runtime check.
  ///
  /// In normal operation every confirmed photo already satisfies this
  /// (PmVisitController.capturePhoto never confirms one without a real
  /// GPS fix and a watermark), so this mainly guards against legacy or
  /// otherwise corrupted rows — e.g. photos saved before the watermark
  /// step existed, which have `watermarkedFilePath == null`.
  bool get isValidForSubmission {
    if (localFilePath.isEmpty) {
      return false;
    }
    final watermarked = watermarkedFilePath;
    if (watermarked == null || watermarked.isEmpty) {
      return false;
    }
    if (!gps.isPlausible) {
      return false;
    }
    return true;
  }
}
