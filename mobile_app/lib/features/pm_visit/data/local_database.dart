import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens (and, on first run, creates) the on-device SQLite database that
/// stores in-progress PM visits and their confirmed photos.
///
/// A visit and its photos stay available with no network connection and
/// across app restarts; the on-device data is never required for
/// capture, only for sync/submission (see SyncManager and
/// PmVisitController.submitVisit). `watermarked_file_path` holds the
/// GPS-watermarked evidence copy (see WatermarkService) alongside the
/// untouched original in `local_file_path`. `drive_file_id` and
/// `drive_file_link` remain reserved, nullable, and unwritten — nothing
/// maps the per-photo Google Drive upload result back into these
/// columns today. `pm_visits.status` is the full visit lifecycle (see
/// VisitSyncStatus): draft -> inProgress -> readyForSubmission ->
/// pendingSync -> syncing -> synced -> submitted, or -> syncFailed.
class PmVisitLocalDatabase {
  PmVisitLocalDatabase._({String? customDatabasePath}) : _customDatabasePath = customDatabasePath;

  static final PmVisitLocalDatabase instance = PmVisitLocalDatabase._();

  /// Creates an instance that stores its database at [databasePath]
  /// instead of resolving one via path_provider. path_provider needs a
  /// platform channel that plain `flutter test` doesn't provide, so
  /// this is how repository tests use a real (FFI-backed) SQLite
  /// database without a device/emulator — see
  /// sqflite_pm_visit_repository_test.dart.
  @visibleForTesting
  factory PmVisitLocalDatabase.withPath(String databasePath) =>
      PmVisitLocalDatabase._(customDatabasePath: databasePath);

  final String? _customDatabasePath;

  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final dbPath = _customDatabasePath ?? await _resolveDefaultPath();

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pm_visits (
            id TEXT PRIMARY KEY,
            employee_id TEXT NOT NULL,
            pop_id INTEGER NOT NULL,
            pop_code TEXT NOT NULL,
            district TEXT NOT NULL,
            block TEXT NOT NULL,
            gp TEXT NOT NULL,
            started_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'draft'
          )
        ''');

        await db.execute('''
          CREATE TABLE pm_photos (
            visit_id TEXT NOT NULL,
            category TEXT NOT NULL,
            pop_id INTEGER NOT NULL,
            local_file_path TEXT NOT NULL,
            captured_at TEXT NOT NULL,
            gps_latitude REAL NOT NULL,
            gps_longitude REAL NOT NULL,
            gps_accuracy_m REAL NOT NULL,
            upload_status TEXT NOT NULL DEFAULT 'pending',
            watermarked_file_path TEXT,
            drive_file_id TEXT,
            drive_file_link TEXT,
            PRIMARY KEY (visit_id, category)
          )
        ''');
      },
    );
  }

  Future<String> _resolveDefaultPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, 'tanfinet_pm_visits.db');
  }
}
