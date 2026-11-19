import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/dashboard/data/mis_report_download_service.dart';
import 'package:mobile_app/features/dashboard/domain/dashboard_failure.dart';
import 'package:mobile_app/features/dashboard/presentation/mis_report_controller.dart';

/// In-memory stand-in for [MisReportDownloadService], so the
/// controller's status transitions can be tested without touching the
/// network or the filesystem — same pattern as
/// dashboard_controller_test.dart's `_FakeDashboardRepository`.
class _FakeMisReportDownloadService implements MisReportDownloadService {
  bool shouldFail = false;
  Duration delay = Duration.zero;
  String pathToReturn = '/data/app/mis_reports/mis_export_2026-11.xlsx';

  @override
  Future<String> downloadMonthlyReport({int? year, int? month}) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (shouldFail) {
      throw const DashboardFailure('Could not reach the server. Check your connection and try again.');
    }
    return pathToReturn;
  }
}

void main() {
  late _FakeMisReportDownloadService downloadService;
  late MisReportController controller;

  setUp(() {
    downloadService = _FakeMisReportDownloadService();
    controller = MisReportController(downloadService: downloadService);
  });

  test('starts idle', () {
    expect(controller.status, MisReportStatus.idle);
    expect(controller.isDownloading, isFalse);
  });

  test('moves to downloading, then success, with the saved path set', () async {
    final future = controller.downloadCurrentMonthReport();
    expect(controller.status, MisReportStatus.downloading);
    expect(controller.isDownloading, isTrue);

    await future;

    expect(controller.status, MisReportStatus.success);
    expect(controller.isDownloading, isFalse);
    expect(controller.savedFilePath, '/data/app/mis_reports/mis_export_2026-11.xlsx');
    expect(controller.errorMessage, isNull);
  });

  test('moves to error with the failure message when the download fails', () async {
    downloadService.shouldFail = true;

    await controller.downloadCurrentMonthReport();

    expect(controller.status, MisReportStatus.error);
    expect(controller.isDownloading, isFalse);
    expect(controller.errorMessage, 'Could not reach the server. Check your connection and try again.');
    expect(controller.savedFilePath, isNull);
  });

  test('notifies listeners on both the downloading and the final transition', () async {
    final statuses = <MisReportStatus>[];
    controller.addListener(() => statuses.add(controller.status));

    await controller.downloadCurrentMonthReport();

    expect(statuses, [MisReportStatus.downloading, MisReportStatus.success]);
  });
}
