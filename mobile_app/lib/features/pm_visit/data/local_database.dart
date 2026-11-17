import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens (and, on first run, creates) the on-device SQLite database that
/// stores in-progress PM visits and their confirmed photos.
///
/// This is the only persistence in this module — there is no remote
/// sync yet, so a visit and its photos stay available with no network
/// connection and across app restarts. `watermarked_file_path` holds the
/// GPS-watermarked evidence copy (see WatermarkService) alongside the
/// untouched original in `local_file_path`. `drive_file_id` and
/// `drive_file_link` remain reserved, nullable, and unwritten — for the
/// later Google Drive upload step.
class PmVisitLocalDatabase {
  PmVisitLocalDatabase._();

  static final PmVisitLocalDatabase instance = PmVisitLocalDatabase._();

  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, 'tanfinet_pm_visits.db');

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pm_visits (
            id TEXT PRIMARY KEY,
            pop_id INTEGER NOT NULL,
            pop_code TEXT NOT NULL,
            started_at TEXT NOT NULL
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
}
