import 'package:flutter/foundation.dart';

import '../data/mis_report_download_service.dart';
import '../domain/dashboard_failure.dart';

enum MisReportStatus { idle, downloading, success, error }

/// Drives the "Download MIS Report" action on [DashboardScreen].
/// Depends only on [MisReportDownloadService], which itself reuses the
/// existing MIS export endpoint and JWT session — this controller adds
/// no network/auth logic of its own.
class MisReportController extends ChangeNotifier {
  MisReportController({MisReportDownloadService? downloadService})
      : _downloadService = downloadService ?? MisReportDownloadService();

  final MisReportDownloadService _downloadService;

  MisReportStatus status = MisReportStatus.idle;
  String? savedFilePath;
  String? errorMessage;

  bool get isDownloading => status == MisReportStatus.downloading;

  /// Downloads and saves the report for the current device month.
  Future<void> downloadCurrentMonthReport() async {
    status = MisReportStatus.downloading;
    errorMessage = null;
    notifyListeners();

    try {
      savedFilePath = await _downloadService.downloadMonthlyReport();
      status = MisReportStatus.success;
    } on DashboardFailure catch (failure) {
      errorMessage = failure.message;
      status = MisReportStatus.error;
    } catch (_) {
      errorMessage = 'Could not download the MIS report. Please try again.';
      status = MisReportStatus.error;
    }
    notifyListeners();
  }
}
