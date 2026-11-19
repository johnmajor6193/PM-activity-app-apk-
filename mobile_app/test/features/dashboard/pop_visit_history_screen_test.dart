import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/dashboard/domain/dashboard_failure.dart';
import 'package:mobile_app/features/dashboard/domain/entities/district_compliance.dart';
import 'package:mobile_app/features/dashboard/domain/entities/engineer_performance.dart';
import 'package:mobile_app/features/dashboard/domain/entities/pop_period_status.dart';
import 'package:mobile_app/features/dashboard/domain/entities/pop_visit_entry.dart';
import 'package:mobile_app/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile_app/features/dashboard/presentation/pop_visit_history_controller.dart';
import 'package:mobile_app/features/dashboard/presentation/pop_visit_history_screen.dart';
import 'package:mobile_app/features/location_selection/domain/entities/block.dart';
import 'package:mobile_app/features/location_selection/domain/entities/district.dart';
import 'package:mobile_app/features/location_selection/domain/entities/gp.dart';
import 'package:mobile_app/features/location_selection/domain/entities/pop_detail.dart';
import 'package:mobile_app/features/location_selection/domain/entities/pop_summary.dart';
import 'package:mobile_app/features/location_selection/domain/location_failure.dart';
import 'package:mobile_app/features/location_selection/domain/repositories/location_repository.dart';

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
    if (shouldFail) throw const LocationFailure('Could not reach the server.');
    return popDetailResponse;
  }

  @override
  Future<List<District>> getDistricts() => throw UnimplementedError();

  @override
  Future<List<Block>> getBlocks(int districtId) => throw UnimplementedError();

  @override
  Future<List<Gp>> getGps(int blockId) => throw UnimplementedError();

  @override
  Future<List<PopSummary>> getPops(int gpId, {bool activeOnly = true}) => throw UnimplementedError();
}

class _FakeDashboardRepository implements DashboardRepository {
  bool shouldFail = false;
  List<PopVisitEntry> visitsResponse = [];

  @override
  Future<List<PopVisitEntry>> getPopVisitHistory(int popId) async {
    if (shouldFail) throw const DashboardFailure('Could not reach the server.');
    return visitsResponse;
  }

  @override
  Future<DistrictDashboard> getDistrictDashboard({DateTime? date}) => throw UnimplementedError();

  @override
  Future<EngineerDashboard> getEngineerDashboard({DateTime? date}) => throw UnimplementedError();
}

void _useMobileScreenSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _buildScreen(_FakeLocationRepository location, _FakeDashboardRepository dashboard, {int popId = 1}) {
  return MaterialApp(
    home: PopVisitHistoryScreen(
      popId: popId,
      controller: PopVisitHistoryController(dashboardRepository: dashboard, locationRepository: location),
    ),
  );
}

void main() {
  testWidgets('shows the District/Block/GP context from the existing locations endpoint', (
    tester,
  ) async {
    _useMobileScreenSize(tester);
    final location = _FakeLocationRepository();
    final dashboard = _FakeDashboardRepository();

    await tester.pumpWidget(_buildScreen(location, dashboard));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chennai'), findsWidgets);
    expect(find.text('Chennai › Sholinganallur › Semmancheri GP'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('No visits recorded yet for this POP.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a compliant visit with full category breakdown and date/time', (tester) async {
    _useMobileScreenSize(tester);
    final location = _FakeLocationRepository();
    final dashboard = _FakeDashboardRepository();
    dashboard.visitsResponse = [
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
        firstSyncedAt: DateTime(2026, 11, 17, 10, 30),
        lastSyncedAt: DateTime(2026, 11, 17, 10, 30),
      ),
    ];

    await tester.pumpWidget(_buildScreen(location, dashboard));
    await tester.pumpAndSettle();

    expect(find.text('Visit date: 2026-11-17'), findsOneWidget);
    expect(find.text('Compliant'), findsOneWidget);
    expect(find.textContaining('Dev Test Engineer (ENG001)'), findsOneWidget);
    expect(find.text('Photos synced: 5/5'), findsOneWidget);
    expect(find.text('POP Rack'), findsOneWidget);
    expect(find.text('Earth Pit Open with Rod'), findsOneWidget);
    expect(find.textContaining('Synced:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders an incomplete visit with Incomplete badge and missing categories', (
    tester,
  ) async {
    _useMobileScreenSize(tester);
    final location = _FakeLocationRepository();
    final dashboard = _FakeDashboardRepository();
    dashboard.visitsResponse = [
      PopVisitEntry(
        visitId: 'visit-2',
        employeeId: 'ENG002',
        employeeName: 'Dev Test Engineer Two',
        visitDate: '2026-11-18',
        status: PopVisitStatus.completed,
        photoCount: 3,
        isCompliant: false,
        categoriesPresent: const ['pop_rack', 'ups_battery', 'busbar'],
        categoriesMissing: const ['earth_pit_chamber', 'earth_pit_open_with_rod'],
        firstSyncedAt: DateTime(2026, 11, 18, 9, 0),
        lastSyncedAt: DateTime(2026, 11, 18, 9, 5),
      ),
    ];

    await tester.pumpWidget(_buildScreen(location, dashboard));
    await tester.pumpAndSettle();

    expect(find.text('Incomplete'), findsOneWidget);
    expect(find.text('Photos synced: 3/5'), findsOneWidget);
    expect(find.text('Earth Pit Chamber'), findsOneWidget);
    expect(find.text('Earth Pit Open with Rod'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple visits render most-recent-first without overflow on a narrow screen', (
    tester,
  ) async {
    _useMobileScreenSize(tester);
    final location = _FakeLocationRepository();
    final dashboard = _FakeDashboardRepository();
    dashboard.visitsResponse = [
      PopVisitEntry(
        visitId: 'visit-newer',
        employeeId: 'ENG001',
        employeeName: 'Dev Test Engineer',
        visitDate: '2026-11-18',
        status: PopVisitStatus.completed,
        photoCount: 5,
        isCompliant: true,
        categoriesPresent: const ['pop_rack', 'ups_battery', 'busbar', 'earth_pit_chamber', 'earth_pit_open_with_rod'],
        categoriesMissing: const [],
        firstSyncedAt: DateTime(2026, 11, 18, 9, 0),
        lastSyncedAt: DateTime(2026, 11, 18, 9, 0),
      ),
      PopVisitEntry(
        visitId: 'visit-older',
        employeeId: 'ENG002',
        employeeName: 'Dev Test Engineer Two',
        visitDate: '2026-11-03',
        status: PopVisitStatus.completed,
        photoCount: 2,
        isCompliant: false,
        categoriesPresent: const ['pop_rack', 'ups_battery'],
        categoriesMissing: const ['busbar', 'earth_pit_chamber', 'earth_pit_open_with_rod'],
        firstSyncedAt: DateTime(2026, 11, 3, 14, 0),
        lastSyncedAt: DateTime(2026, 11, 3, 14, 0),
      ),
    ];

    await tester.pumpWidget(_buildScreen(location, dashboard));
    await tester.pumpAndSettle();

    final visitDateFinder = find.textContaining('Visit date:');
    expect(visitDateFinder, findsNWidgets(2));
    expect(
      tester.widget<Text>(visitDateFinder.at(0)).data,
      'Visit date: 2026-11-18',
    );
    expect(
      tester.widget<Text>(visitDateFinder.at(1)).data,
      'Visit date: 2026-11-03',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a clear error when the POP lookup fails', (tester) async {
    _useMobileScreenSize(tester);
    final location = _FakeLocationRepository()..shouldFail = true;
    final dashboard = _FakeDashboardRepository();

    await tester.pumpWidget(_buildScreen(location, dashboard));
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a clear error when the visit history lookup fails', (tester) async {
    _useMobileScreenSize(tester);
    final location = _FakeLocationRepository();
    final dashboard = _FakeDashboardRepository()..shouldFail = true;

    await tester.pumpWidget(_buildScreen(location, dashboard));
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
