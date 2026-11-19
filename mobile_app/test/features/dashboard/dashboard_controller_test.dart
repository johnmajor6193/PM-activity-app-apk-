import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/dashboard/domain/dashboard_failure.dart';
import 'package:mobile_app/features/dashboard/domain/entities/district_compliance.dart';
import 'package:mobile_app/features/dashboard/domain/entities/engineer_performance.dart';
import 'package:mobile_app/features/dashboard/domain/entities/pop_visit_entry.dart';
import 'package:mobile_app/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile_app/features/dashboard/presentation/dashboard_controller.dart';

/// In-memory stand-in for the real HTTP-backed repository, so the
/// controller's logic (status transitions, fortnight navigation) can
/// be tested without a server. Records every `date` it was called
/// with, so tests can verify fortnight navigation passes the right
/// value through, without re-deriving fortnight math in Dart.
class _FakeDashboardRepository implements DashboardRepository {
  static final _fortnightStart = DateTime(2026, 11, 16);
  static final _fortnightEnd = DateTime(2026, 11, 30);

  bool shouldFail = false;
  final List<DateTime?> districtCalls = [];
  final List<DateTime?> engineerCalls = [];

  DistrictDashboard districtResponse = DistrictDashboard(
    periodStart: _fortnightStart,
    periodEnd: _fortnightEnd,
    districts: const [],
  );
  EngineerDashboard engineerResponse = EngineerDashboard(
    periodStart: _fortnightStart,
    periodEnd: _fortnightEnd,
    engineers: const [],
  );

  @override
  Future<DistrictDashboard> getDistrictDashboard({DateTime? date}) async {
    districtCalls.add(date);
    if (shouldFail) {
      throw const DashboardFailure('Could not reach the server.');
    }
    return districtResponse;
  }

  @override
  Future<EngineerDashboard> getEngineerDashboard({DateTime? date}) async {
    engineerCalls.add(date);
    if (shouldFail) {
      throw const DashboardFailure('Could not reach the server.');
    }
    return engineerResponse;
  }

  @override
  Future<List<PopVisitEntry>> getPopVisitHistory(int popId) async => [];
}

void main() {
  late _FakeDashboardRepository repository;
  late DashboardController controller;

  setUp(() {
    repository = _FakeDashboardRepository();
    controller = DashboardController(repository: repository);
  });

  test('loadDistricts populates the district dashboard on success', () async {
    await controller.loadDistricts();

    expect(controller.districtStatus, DashboardLoadStatus.loaded);
    expect(controller.districtDashboard, isNotNull);
    expect(controller.errorMessage, isNull);
  });

  test('loadDistricts surfaces a DashboardFailure message on failure', () async {
    repository.shouldFail = true;

    await controller.loadDistricts();

    expect(controller.districtStatus, DashboardLoadStatus.error);
    expect(controller.errorMessage, 'Could not reach the server.');
    expect(controller.districtDashboard, isNull);
  });

  test('loadEngineers populates the engineer dashboard on success', () async {
    await controller.loadEngineers();

    expect(controller.engineerStatus, DashboardLoadStatus.loaded);
    expect(controller.engineerDashboard, isNotNull);
  });

  test('loadEngineers surfaces a DashboardFailure message on failure', () async {
    repository.shouldFail = true;

    await controller.loadEngineers();

    expect(controller.engineerStatus, DashboardLoadStatus.error);
    expect(controller.errorMessage, 'Could not reach the server.');
  });

  test('loadAll loads both districts and engineers', () async {
    await controller.loadAll();

    expect(controller.districtStatus, DashboardLoadStatus.loaded);
    expect(controller.engineerStatus, DashboardLoadStatus.loaded);
    expect(repository.districtCalls, hasLength(1));
    expect(repository.engineerCalls, hasLength(1));
  });

  test('a fresh controller defaults to showing today (no date selected)', () async {
    expect(controller.isShowingToday, isTrue);

    await controller.loadAll();

    expect(repository.districtCalls.single, isNull);
    expect(repository.engineerCalls.single, isNull);
  });

  test('goToPreviousFortnight moves to the day before the current period start', () async {
    await controller.loadAll();

    controller.goToPreviousFortnight();
    await Future<void>.delayed(Duration.zero);

    expect(controller.selectedDate, DateTime(2026, 11, 15));
    expect(controller.isShowingToday, isFalse);
    expect(repository.districtCalls.last, DateTime(2026, 11, 15));
  });

  test('goToNextFortnight moves to the day after the current period end', () async {
    await controller.loadAll();

    controller.goToNextFortnight();
    await Future<void>.delayed(Duration.zero);

    expect(controller.selectedDate, DateTime(2026, 12, 1));
    expect(repository.districtCalls.last, DateTime(2026, 12, 1));
  });

  test('goToToday resets the selected date back to null and reloads', () async {
    await controller.loadAll();
    controller.goToNextFortnight();
    await Future<void>.delayed(Duration.zero);
    expect(controller.isShowingToday, isFalse);

    controller.goToToday();
    await Future<void>.delayed(Duration.zero);

    expect(controller.isShowingToday, isTrue);
    expect(repository.districtCalls.last, isNull);
  });

  test('goToToday does nothing extra when already showing today', () async {
    await controller.loadAll();
    final callsBefore = repository.districtCalls.length;

    controller.goToToday();
    await Future<void>.delayed(Duration.zero);

    expect(repository.districtCalls.length, callsBefore);
  });

  test('isLoading is true only while a request is in flight', () async {
    expect(controller.isLoading, isFalse);

    final future = controller.loadAll();
    expect(controller.isLoading, isTrue);

    await future;
    expect(controller.isLoading, isFalse);
  });
}
