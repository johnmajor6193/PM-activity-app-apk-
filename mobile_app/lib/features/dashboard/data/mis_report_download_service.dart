import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'mis_export_api_client.dart';

/// Downloads the Monthly MIS Excel report via [MisExportApiClient] and
/// saves it to this app's private on-device storage — the same
/// `path_provider` app-documents-directory pattern already used by
/// `camera_capture_service.dart` for PM visit photos. No new storage
/// mechanism, permission, or dependency is introduced.
class MisReportDownloadService {
  MisReportDownloadService({MisExportApiClient? apiClient})
      : _apiClient = apiClient ?? MisExportApiClient();

  final MisExportApiClient _apiClient;

  /// Downloads and saves the report for [year]/[month] (defaults to
  /// the device's current year/month when omitted), returning the
  /// saved file's full path.
  Future<String> downloadMonthlyReport({int? year, int? month}) async {
    final now = DateTime.now();
    final resolvedYear = year ?? now.year;
    final resolvedMonth = month ?? now.month;

    final bytes = await _apiClient.downloadXlsx(year: resolvedYear, month: resolvedMonth);

    final directory = await _reportsDirectory();
    final filename =
        'mis_export_${resolvedYear.toString().padLeft(4, '0')}-${resolvedMonth.toString().padLeft(2, '0')}.xlsx';
    final file = File(p.join(directory.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Directory> _reportsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(appDir.path, 'mis_reports'));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }
}
