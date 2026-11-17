import 'gps_reading.dart';
import 'photo_category.dart';

/// Tracks whether a confirmed photo has been synced anywhere yet. Upload
/// logic itself (Google Drive) is not implemented in this module — this
/// enum only prepares the field so offline capture and later sync don't
/// need a schema change.
enum PhotoUploadStatus { pending, uploaded, failed }

/// A single captured, engineer-confirmed PM visit photograph, with
/// everything required to store and later sync it.
///
/// [watermarkedFilePath], [driveFileId], and [driveFileLink] are reserved
/// for later steps (GPS watermark, Google Drive upload) and are always
/// null today.
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
