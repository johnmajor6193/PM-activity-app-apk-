import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/dashboard/domain/dashboard_failure.dart';
import 'package:mobile_app/features/dashboard/domain/entities/district_compliance.dart';
import 'package:mobile_app/features/dashboard/domain/entities/engineer_performance.dart';
import 'package:mobile_app/features/dashboard/domain/entities/pop_period_status.dart';
import 'package:mobile_app/features/dashboard/domain/entities/pop_visit_entry.dart';
import 'package:mobile_app/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile_app/features/dashboard/presentation/dashboard_controller.dart';
import 'package:mobile_app/features/dashboard/presentation/pop_visit_history_controller.dart';
import 'package:mobile_app/features/location_selection/domain/entities/block.dart';
import 'package:mobile_app/features/location_selection/domain/entities/district.dart';
import 'package:mobile_app/features/location_selection/domain/entities/gp.dart';
import 'package:mobile_app/features/location_selection/domain/entities/pop_detail.dart';
import 'package:mobile_app/features/location_selection/domain/entities/pop_summary.dart';
import 'package:mobile_app/features/location_selection/domain/location_failure.dart';
import 'package:mobile_app/features/location_selection/domain/repositories/location_repository.dart';

/// Reuses the existing, unchanged LocationRepository interface — this
/// fake stands in for the real one (already implemented/verified),
/// not a new location feature.
class _FakeLocationRepository implements LocationRepository {
  bool shouldFail = false;
  PopDetail popDetailResponse = const PopDetail(
    id: 1,
    popCode: 'POP-CHN-001',
    name: 'Semmancheri POP 1',
    isActive: true,
    gpId: 1,
    gpName: 'Semmancheri GP',
    blockName: 'Sholinganallur',
    districtName: 'Chennai',
  );

  @override
  Future<PopDetail> getPopDetail(int popId) async {
    if (shouldFail) {
      throw const LocationFailure('Could not reach the server.');
    }
    return popDetailResponse;
  }

  @override
  Future<List<District>> getDistricts() => throw UnimplementedError();

  @override
  Future<List<Block>> getBlocks(int districtId) => throw UnimplementedError();

  @override
  Future<List<Gp>> getGps(int blockId) => throw UnimplementedError();

  @override
  Future<List<PopSummary>> getPops(int gpId, {bool activeOnly = true}) =>
      throw UnimplementedError();
}

class _FakeDashboardRepository implements DashboardRepository {
  bool shouldFail = false;
  List<PopVisitEntry> visitsResponse = [];

  @override
  Future<List<PopVisitEntry>> getPopVisitHistory(int popId) async {
    if (shouldFail) {
      throw const DashboardFailure('Could not reach the server.');
    }
    return visitsResponse;
  }

  @override
  Future<DistrictDashboard> getDistrictDashboard({DateTime? date}) => throw UnimplementedError();

  @override
  Future<EngineerDashboard> getEngineerDashboard({DateTime? date}) => throw UnimplementedError();
}

void main() {
  late _FakeDashboardRepository dashboardRepository;
  late _FakeLocationRepository locationRepository;
  late PopVisitHistoryController controller;

  setUp(() {
    dashboardRepository = _FakeDashboardRepository();
    locationRepository = _FakeLocationRepository();
    controller = PopVisitHistoryController(
      dashboardRepository: dashboardRepository,
      locationRepository: locationRepository,
    );
  });

  test('load populates both POP detail (hierarchy context) and visit history', () async {
    dashboardRepository.visitsResponse = [
      PopVisitEntry(
        visitId: 'visit-1',
        employeeId: 'ENG001',
        employeeName: 'Dev Test Engineer',
        visitDate: '2026-11-17',
        status: PopVisitStatus.completed,
        photoCount: 5,
        isCompliant: true,
        categoriesPresent: const ['pop_rack', 'ups_battery', 'busbar', 'earth_pit_chamber', 'earth_pit_open_with_rod'],
        categoriesMissing: const [],
        firstSyncedAt: DateTime(2026, 11, 17, 10, 0),
        lastSyncedAt: DateTime(2026, 11, 17, 10, 0),
      ),
    ];

    await controller.load(1);

    expect(controller.status, DashboardLoadStatus.loaded);
    expect(controller.popDetail?.districtName, 'Chennai');
    expect(controller.popDetail?.gpName, 'Semmancheri GP');
    expect(controller.visits, hasLength(1));
    expect(controller.visits.single.visitId, 'visit-1');
    expect(controller.errorMessage, isNull);
  });

  test('load surfaces a LocationFailure message when POP lookup fails', () async {
    locationRepository.shouldFail = true;

    await controller.load(1);

    expect(controller.status, DashboardLoadStatus.error);
    expect(controller.errorMessage, 'Could not reach the server.');
  });

  test('load surfaces a DashboardFailure message when visit history lookup fails', () async {
    dashboardRepository.shouldFail = true;

    await controller.load(1);

    expect(controller.status, DashboardLoadStatus.error);
    expect(controller.errorMessage, 'Could not reach the server.');
  });

  test('load with an empty visit history leaves visits empty, not an error', () async {
    dashboardRepository.visitsResponse = [];

    await controller.load(1);

    expect(controller.status, DashboardLoadStatus.loaded);
    expect(controller.visits, isEmpty);
    expect(controller.errorMessage, isNull);
  });
}
