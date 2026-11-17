import 'package:sqflite/sqflite.dart';

import '../domain/entities/gps_reading.dart';
import '../domain/entities/pm_photo_record.dart';
import '../domain/entities/pm_visit.dart';
import '../domain/entities/photo_category.dart';
import '../domain/repositories/pm_visit_repository.dart';
import 'local_database.dart';

/// [PmVisitRepository] backed by the on-device SQLite database (see
/// local_database.dart). No network call is made anywhere in this class.
class SqflitePmVisitRepository implements PmVisitRepository {
  SqflitePmVisitRepository({PmVisitLocalDatabase? database})
      : _database = database ?? PmVisitLocalDatabase.instance;

  final PmVisitLocalDatabase _database;

  @override
  Future<PmVisit> startVisit({required int popId, required String popCode}) async {
    final db = await _database.database;
    final visit = PmVisit(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      popId: popId,
      popCode: popCode,
      startedAt: DateTime.now(),
    );

    await db.insert('pm_visits', {
      'id': visit.id,
      'pop_id': visit.popId,
      'pop_code': visit.popCode,
      'started_at': visit.startedAt.toIso8601String(),
    });

    return visit;
  }

  @override
  Future<void> savePhoto(PmPhotoRecord record) async {
    final db = await _database.database;
    await db.insert(
      'pm_photos',
      {
        'visit_id': record.visitId,
        'category': record.category.storageKey,
        'pop_id': record.popId,
        'local_file_path': record.localFilePath,
        'captured_at': record.capturedAt.toIso8601String(),
        'gps_latitude': record.gps.latitude,
        'gps_longitude': record.gps.longitude,
        'gps_accuracy_m': record.gps.accuracyMeters,
        'upload_status': record.uploadStatus.name,
        'watermarked_file_path': record.watermarkedFilePath,
        'drive_file_id': record.driveFileId,
        'drive_file_link': record.driveFileLink,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Map<PhotoCategory, PmPhotoRecord>> getPhotosForVisit(String visitId) async {
    final db = await _database.database;
    final rows = await db.query('pm_photos', where: 'visit_id = ?', whereArgs: [visitId]);

    final result = <PhotoCategory, PmPhotoRecord>{};
    for (final row in rows) {
      final category = photoCategoryFromStorageKey(row['category'] as String);
      result[category] = PmPhotoRecord(
        visitId: row['visit_id'] as String,
        popId: row['pop_id'] as int,
        category: category,
        localFilePath: row['local_file_path'] as String,
        capturedAt: DateTime.parse(row['captured_at'] as String),
        gps: GpsReading(
          latitude: row['gps_latitude'] as double,
          longitude: row['gps_longitude'] as double,
          accuracyMeters: row['gps_accuracy_m'] as double,
        ),
        uploadStatus: PhotoUploadStatus.values.byName(row['upload_status'] as String),
        watermarkedFilePath: row['watermarked_file_path'] as String?,
        driveFileId: row['drive_file_id'] as String?,
        driveFileLink: row['drive_file_link'] as String?,
      );
    }
    return result;
  }
}
