import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/dashboard/data/mis_export_api_client.dart';
import 'package:mobile_app/features/dashboard/data/mis_report_download_service.dart';
import 'package:mobile_app/features/dashboard/domain/dashboard_failure.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Stands in for the real `path_provider` platform channel, which
/// isn't available in `flutter test` — same technique used throughout
/// Flutter's own ecosystem for testing path_provider-dependent code
/// without a device. Points "application documents directory" at a
/// real temp directory on this machine so the service's actual
/// `dart:io` file-write logic is genuinely exercised, not mocked away.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.directoryPath);

  final String directoryPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => directoryPath;
}

class _FakeMisExportApiClient implements MisExportApiClient {
  List<int>? bytesToReturn;
  Object? errorToThrow;
  int? lastRequestedYear;
  int? lastRequestedMonth;

  @override
  Future<List<int>> downloadXlsx({required int year, required int month}) async {
    lastRequestedYear = year;
    lastRequestedMonth = month;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return bytesToReturn ?? [];
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mis_report_download_service_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('downloadMonthlyReport writes the downloaded bytes to a saved .xlsx file', () async {
    final apiClient = _FakeMisExportApiClient()..bytesToReturn = [10, 20, 30];
    final service = MisReportDownloadService(apiClient: apiClient);

    final savedPath = await service.downloadMonthlyReport(year: 2026, month: 11);

    expect(apiClient.lastRequestedYear, 2026);
    expect(apiClient.lastRequestedMonth, 11);
    expect(p.basename(savedPath), 'mis_export_2026-11.xlsx');
    final savedFile = File(savedPath);
    expect(savedFile.existsSync(), isTrue);
    expect(await savedFile.readAsBytes(), [10, 20, 30]);
  });

  test('downloadMonthlyReport defaults to the current device year/month when omitted', () async {
    final apiClient = _FakeMisExportApiClient()..bytesToReturn = [1];
    final service = MisReportDownloadService(apiClient: apiClient);
    final now = DateTime.now();

    await service.downloadMonthlyReport();

    expect(apiClient.lastRequestedYear, now.year);
    expect(apiClient.lastRequestedMonth, now.month);
  });

  test('downloadMonthlyReport propagates a DashboardFailure from the API client', () async {
    final apiClient = _FakeMisExportApiClient()
      ..errorToThrow = const DashboardFailure('Could not reach the server.');
    final service = MisReportDownloadService(apiClient: apiClient);

    await expectLater(
      service.downloadMonthlyReport(year: 2026, month: 11),
      throwsA(isA<DashboardFailure>()),
    );
  });
}
