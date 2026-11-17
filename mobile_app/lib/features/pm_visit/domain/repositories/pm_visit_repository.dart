import '../entities/pm_photo_record.dart';
import '../entities/pm_visit.dart';
import '../entities/photo_category.dart';

/// Local-only persistence for an in-progress PM visit and its photos.
///
/// There is no remote sync yet: everything here reads/writes the
/// on-device store only (see ../data/sqflite_pm_visit_repository.dart),
/// so a visit and its confirmed photos survive app restarts and need no
/// network connection.
abstract class PmVisitRepository {
  Future<PmVisit> startVisit({required int popId, required String popCode});

  /// Inserts the confirmed photo for `record.category`, or replaces it
  /// if that category was already captured for this visit (retake).
  Future<void> savePhoto(PmPhotoRecord record);

  /// All confirmed photos for a visit, keyed by category.
  Future<Map<PhotoCategory, PmPhotoRecord>> getPhotosForVisit(String visitId);
}
