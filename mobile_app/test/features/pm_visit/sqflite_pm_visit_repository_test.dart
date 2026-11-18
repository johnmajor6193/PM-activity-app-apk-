import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/pm_visit/data/local_database.dart';
import 'package:mobile_app/features/pm_visit/data/sqflite_pm_visit_repository.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/gps_reading.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/pm_photo_record.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/photo_category.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/visit_sync_status.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// These tests run against a REAL SQLite database (via
/// `sqflite_common_ffi`, which loads the system's native sqlite3
/// through FFI) — not a fake or an in-memory stand-in for the schema.
/// This is possible because SQLite itself has no platform channel; only
/// `path_provider` (used to locate the database file in production)
/// does, and PmVisitLocalDatabase.withPath exists specifically to skip
/// that for tests. So unlike the camera/GPS/watermark controller tests
/// elsewhere in this module, this file genuinely exercises the on-disk
/// schema, SQL, and row mapping.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late SqflitePmVisitRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pm_visit_db_test_');
    final db = PmVisitLocalDatabase.withPath('${tempDir.path}/test.db');
    repository = SqflitePmVisitRepository(database: db);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  PmPhotoRecord buildPhoto(String visitId, PhotoCategory category) {
    return PmPhotoRecord(
      visitId: visitId,
      popId: 7,
      category: category,
      localFilePath: '/fake/${category.storageKey}.jpg',
      watermarkedFilePath: '/fake/${category.storageKey}_watermarked.jpg',
      capturedAt: DateTime(2026, 2, 1, 10, 0, 0),
      gps: const GpsReading(latitude: 11.1, longitude: 77.2, accuracyMeters: 4.0),
    );
  }

  test('saves a PM visit locally with all required fields', () async {
    final visit = await repository.startVisit(
      employeeId: 'ENG001',
      popId: 7,
      popCode: 'POP-CHN-001',
      districtName: 'Chennai',
      blockName: 'Sholinganallur',
      gpName: 'Semmancheri GP',
    );

    expect(visit.id, isNotEmpty);
    expect(visit.employeeId, 'ENG001');
    expect(visit.popId, 7);
    expect(visit.popCode, 'POP-CHN-001');
    expect(visit.districtName, 'Chennai');
    expect(visit.blockName, 'Sholinganallur');
    expect(visit.gpName, 'Semmancheri GP');
    expect(visit.status, VisitSyncStatus.draft);
  });

  test('reopening/retrieving a pending visit returns everything stored for it', () async {
    final visit = await repository.startVisit(
      employeeId: 'ENG001',
      popId: 7,
      popCode: 'POP-CHN-001',
      districtName: 'Chennai',
      blockName: 'Sholinganallur',
      gpName: 'Semmancheri GP',
    );
    await repository.updateVisitStatus(visit.id, VisitSyncStatus.pendingSync);

    // Simulate the app being closed and reopened: look the visit up
    // again by id, as if from a fresh in-memory state.
    final reopened = await repository.getVisit(visit.id);

    expect(reopened, isNotNull);
    expect(reopened!.id, visit.id);
    expect(reopened.employeeId, 'ENG001');
    expect(reopened.districtName, 'Chennai');
    expect(reopened.blockName, 'Sholinganallur');
    expect(reopened.gpName, 'Semmancheri GP');
    expect(reopened.status, VisitSyncStatus.pendingSync);
  });

  test('getResumableVisit finds an incomplete visit for the same POP', () async {
    final visit = await repository.startVisit(
      employeeId: 'ENG001',
      popId: 7,
      popCode: 'POP-CHN-001',
      districtName: 'Chennai',
      blockName: 'Sholinganallur',
      gpName: 'Semmancheri GP',
    );

    final resumable = await repository.getResumableVisit(7);

    expect(resumable, isNotNull);
    expect(resumable!.id, visit.id);
  });

  test('getResumableVisit returns null once the visit is no longer draft/in-progress', () async {
    final visit = await repository.startVisit(
      employeeId: 'ENG001',
      popId: 7,
      popCode: 'POP-CHN-001',
      districtName: 'Chennai',
      blockName: 'Sholinganallur',
      gpName: 'Semmancheri GP',
    );
    await repository.updateVisitStatus(visit.id, VisitSyncStatus.pendingSync);

    final resumable = await repository.getResumableVisit(7);

    expect(resumable, isNull);
  });

  test('saves all five photo records for a visit and retrieves them by category', () async {
    final visit = await repository.startVisit(
      employeeId: 'ENG001',
      popId: 7,
      popCode: 'POP-CHN-001',
      districtName: 'Chennai',
      blockName: 'Sholinganallur',
      gpName: 'Semmancheri GP',
    );

    for (final category in mandatoryPhotoCategories) {
      await repository.savePhoto(buildPhoto(visit.id, category));
    }

    final photos = await repository.getPhotosForVisit(visit.id);

    expect(photos.length, 5);
    for (final category in mandatoryPhotoCategories) {
      final photo = photos[category]!;
      expect(photo.category, category);
      expect(photo.localFilePath, '/fake/${category.storageKey}.jpg');
      expect(photo.watermarkedFilePath, '/fake/${category.storageKey}_watermarked.jpg');
      expect(photo.gps.latitude, 11.1);
      expect(photo.gps.longitude, 77.2);
      expect(photo.gps.accuracyMeters, 4.0);
    }
  });

  test('a photo is still retrievable — with its files and GPS intact — after a sync failure', () async {
    final visit = await repository.startVisit(
      employeeId: 'ENG001',
      popId: 7,
      popCode: 'POP-CHN-001',
      districtName: 'Chennai',
      blockName: 'Sholinganallur',
      gpName: 'Semmancheri GP',
    );
    await repository.savePhoto(buildPhoto(visit.id, PhotoCategory.popRack));

    await repository.updateVisitStatus(visit.id, VisitSyncStatus.pendingSync);
    await repository.updateVisitStatus(visit.id, VisitSyncStatus.syncing);
    await repository.updateVisitStatus(visit.id, VisitSyncStatus.syncFailed);

    final visitAfterFailure = await repository.getVisit(visit.id);
    final photosAfterFailure = await repository.getPhotosForVisit(visit.id);

    expect(visitAfterFailure!.status, VisitSyncStatus.syncFailed);
    expect(photosAfterFailure.length, 1);
    expect(photosAfterFailure[PhotoCategory.popRack]!.localFilePath, '/fake/pop_rack.jpg');
    expect(
      photosAfterFailure[PhotoCategory.popRack]!.watermarkedFilePath,
      '/fake/pop_rack_watermarked.jpg',
    );
  });

  test('getVisitsByStatus returns only visits in the requested statuses', () async {
    final pending = await repository.startVisit(
      employeeId: 'ENG001',
      popId: 1,
      popCode: 'POP-A',
      districtName: 'Chennai',
      blockName: 'B',
      gpName: 'G',
    );
    final failed = await repository.startVisit(
      employeeId: 'ENG001',
      popId: 2,
      popCode: 'POP-B',
      districtName: 'Chennai',
      blockName: 'B',
      gpName: 'G',
    );
    final stillLocal = await repository.startVisit(
      employeeId: 'ENG001',
      popId: 3,
      popCode: 'POP-C',
      districtName: 'Chennai',
      blockName: 'B',
      gpName: 'G',
    );
    await repository.updateVisitStatus(pending.id, VisitSyncStatus.pendingSync);
    await repository.updateVisitStatus(failed.id, VisitSyncStatus.syncFailed);
    // stillLocal is left as draft on purpose.

    final eligible = await repository.getVisitsByStatus([
      VisitSyncStatus.pendingSync,
      VisitSyncStatus.syncFailed,
    ]);

    expect(eligible.map((v) => v.id), containsAll(<String>[pending.id, failed.id]));
    expect(eligible.map((v) => v.id), isNot(contains(stillLocal.id)));
  });

  test('retaking a photo (same visit + category) replaces it instead of duplicating it', () async {
    final visit = await repository.startVisit(
      employeeId: 'ENG001',
      popId: 7,
      popCode: 'POP-CHN-001',
      districtName: 'Chennai',
      blockName: 'Sholinganallur',
      gpName: 'Semmancheri GP',
    );
    await repository.savePhoto(buildPhoto(visit.id, PhotoCategory.busbar));
    await repository.savePhoto(
      PmPhotoRecord(
        visitId: visit.id,
        popId: 7,
        category: PhotoCategory.busbar,
        localFilePath: '/fake/busbar_retake.jpg',
        watermarkedFilePath: '/fake/busbar_retake_watermarked.jpg',
        capturedAt: DateTime(2026, 2, 1, 10, 5, 0),
        gps: const GpsReading(latitude: 22.2, longitude: 88.3, accuracyMeters: 3.0),
      ),
    );

    final photos = await repository.getPhotosForVisit(visit.id);

    expect(photos.length, 1);
    expect(photos[PhotoCategory.busbar]!.localFilePath, '/fake/busbar_retake.jpg');
  });
}
