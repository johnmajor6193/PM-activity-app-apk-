import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/dashboard/domain/dashboard_failure.dart';
import 'package:mobile_app/features/dashboard/domain/entities/district_compliance.dart';
import 'package:mobile_app/features/dashboard/domain/entities/engineer_performance.dart';
import 'package:mobile_app/features/dashboard/domain/entities/pop_period_status.dart';
import 'package:mobile_app/features/dashboard/domain/entities/pop_visit_entry.dart';
import 'package:mobile_app/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile_app/features/dashboard/presentation/dashboard_controller.dart';
import 'package:mobile_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:mobile_app/features/dashboard/presentation/pop_visit_history_screen.dart';

/// Widget-level verification for DashboardScreen: this is the part of
/// the final UI/device verification pass that an emulator-less
/// environment *can* genuinely do — pumping the real widget tree and
/// asserting on what actually renders, including narrow-mobile-width
/// overflow — not a substitute for a real device/emulator pass (see
/// the top-level report for exactly what remains device-only).
class _FakeDashboardRepository implements DashboardRepository {
  bool shouldFail = false;
  Duration delay = Duration.zero;
  DistrictDashboard districtResponse = DistrictDashboard(
    periodStart: DateTime(2026, 11, 16),
    periodEnd: DateTime(2026, 11, 30),
    districts: const [],
  );
  EngineerDashboard engineerResponse = EngineerDashboard(
    periodStart: DateTime(2026, 11, 16),
    periodEnd: DateTime(2026, 11, 30),
    engineers: const [],
  );

  /// Set true to make the canned responses reflect whatever `date` was
  /// actually requested (mirroring the real backend's fortnight_bounds
  /// just enough to verify navigation reaches the controller/repository
  /// correctly) - off by default, since most tests want a fixed period.
  bool respondToRequestedDate = false;

  @override
  Future<DistrictDashboard> getDistrictDashboard({DateTime? date}) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (shouldFail) {
      throw const DashboardFailure('Could not reach the server. Check your connection and try again.');
    }
    if (respondToRequestedDate && date != null) {
      final (start, end) = _fortnightFor(date);
      return DistrictDashboard(periodStart: start, periodEnd: end, districts: districtResponse.districts);
    }
    return districtResponse;
  }

  @override
  Future<EngineerDashboard> getEngineerDashboard({DateTime? date}) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (shouldFail) {
      throw const DashboardFailure('Could not reach the server. Check your connection and try again.');
    }
    if (respondToRequestedDate && date != null) {
      final (start, end) = _fortnightFor(date);
      return EngineerDashboard(periodStart: start, periodEnd: end, engineers: engineerResponse.engineers);
    }
    return engineerResponse;
  }

  /// Minimal mirror of the real backend's calendar-fortnight rule
  /// (1st-15th / 16th-end-of-month), only so this fake can respond
  /// believably to fortnight navigation in a test - the real rule
  /// stays solely in backend/app/services/compliance.py.
  (DateTime, DateTime) _fortnightFor(DateTime date) {
    if (date.day <= 15) {
      return (DateTime(date.year, date.month, 1), DateTime(date.year, date.month, 15));
    }
    final lastDay = DateTime(date.year, date.month + 1, 0).day;
    return (DateTime(date.year, date.month, 16), DateTime(date.year, date.month, lastDay));
  }

  @override
  Future<List<PopVisitEntry>> getPopVisitHistory(int popId) async => [];
}

PopPeriodStatus _compliantPop() => const PopPeriodStatus(
  popId: 1,
  popCode: 'POP-CHN-001',
  popName: 'Semmancheri POP 1',
  status: PopVisitStatus.completed,
  isCompliant: true,
  latestVisitId: 'visit-1',
  categoriesPresent: ['pop_rack', 'ups_battery', 'busbar', 'earth_pit_chamber', 'earth_pit_open_with_rod'],
  categoriesMissing: [],
);

PopPeriodStatus _incompletePop() => const PopPeriodStatus(
  popId: 3,
  popCode: 'POP-CHN-003',
  popName: 'Kazhipattur POP 1 — With An Unusually Long Display Name For Layout Testing',
  status: PopVisitStatus.completed,
  isCompliant: false,
  latestVisitId: 'visit-2',
  categoriesPresent: ['pop_rack', 'ups_battery', 'busbar'],
  categoriesMissing: ['earth_pit_chamber', 'earth_pit_open_with_rod'],
);

PopPeriodStatus _pendingPop() => const PopPeriodStatus(
  popId: 4,
  popCode: 'POP-CHN-004',
  popName: 'Chitlapakkam POP 1',
  status: PopVisitStatus.pending,
  isCompliant: false,
  latestVisitId: null,
  categoriesPresent: [],
  categoriesMissing: ['pop_rack', 'ups_battery', 'busbar', 'earth_pit_chamber', 'earth_pit_open_with_rod'],
);

/// Sets the test surface to a narrow, "normal mobile screen" size
/// (similar to a budget/mid-range Android phone) so overflow bugs
/// that only show up on a real narrow device are caught here too.
void _useMobileScreenSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('shows a loading indicator before the first response arrives', (tester) async {
    _useMobileScreenSize(tester);
    final repository = _FakeDashboardRepository()..delay = const Duration(milliseconds: 500);

    await tester.pumpWidget(
      MaterialApp(home: DashboardScreen(controller: DashboardController(repository: repository))),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
  });

  testWidgets('renders district compliance with completed/pending/compliance-percent clearly', (
    tester,
  ) async {
    _useMobileScreenSize(tester);
    final repository = _FakeDashboardRepository();
    repository.districtResponse = DistrictDashboard(
      periodStart: DateTime(2026, 11, 16),
      periodEnd: DateTime(2026, 11, 30),
      districts: [
        DistrictCompliance(
          districtId: 1,
          districtName: 'Chennai',
          totalActivePops: 3,
          compliantPops: 1,
          compliancePercent: 33.3,
          completedPops: 2,
          pendingPops: 1,
          pops: [_compliantPop(), _incompletePop(), _pendingPop()],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: DashboardScreen(controller: DashboardController(repository: repository))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chennai'), findsOneWidget);
    expect(find.text('33.3%'), findsWidgets); // once in the district badge, once in the overall summary
    expect(find.text('1/3 compliant · 2 completed · 1 pending'), findsOneWidget);
    expect(find.text('2 visited this fortnight · 1 pending'), findsOneWidget);

    // Expand the district card to see the per-POP breakdown.
    await tester.tap(find.text('Chennai'));
    await tester.pumpAndSettle();

    expect(find.textContaining('POP-CHN-001'), findsOneWidget);
    expect(find.text('Completed — all 5 categories synced'), findsOneWidget);
    expect(find.textContaining('POP-CHN-003'), findsOneWidget);
    expect(find.text('Completed — 3/5 categories synced'), findsOneWidget);
    expect(find.textContaining('Missing: Earth Pit Chamber, Earth Pit Open with Rod'), findsOneWidget);
    expect(find.textContaining('POP-CHN-004'), findsOneWidget);
    expect(find.text('Pending — no visit synced this fortnight'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a POP opens PopVisitHistoryScreen', (tester) async {
    _useMobileScreenSize(tester);
    final repository = _FakeDashboardRepository();
    repository.districtResponse = DistrictDashboard(
      periodStart: DateTime(2026, 11, 16),
      periodEnd: DateTime(2026, 11, 30),
      districts: [
        DistrictCompliance(
          districtId: 1,
          districtName: 'Chennai',
          totalActivePops: 1,
          compliantPops: 1,
          compliancePercent: 100.0,
          completedPops: 1,
          pendingPops: 0,
          pops: [_compliantPop()],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: DashboardScreen(controller: DashboardController(repository: repository))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chennai'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('POP-CHN-001'));
    await tester.pumpAndSettle();

    expect(find.byType(PopVisitHistoryScreen), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no districts or engineers', (tester) async {
    _useMobileScreenSize(tester);
    final repository = _FakeDashboardRepository();

    await tester.pumpWidget(
      MaterialApp(home: DashboardScreen(controller: DashboardController(repository: repository))),
    );
    await tester.pumpAndSettle();

    expect(find.text('No districts found.'), findsOneWidget);

    await tester.tap(find.text('Engineers'));
    await tester.pumpAndSettle();

    expect(find.text('No active engineers found.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a clear error message when the API call fails', (tester) async {
    _useMobileScreenSize(tester);
    final repository = _FakeDashboardRepository()..shouldFail = true;

    await tester.pumpWidget(
      MaterialApp(home: DashboardScreen(controller: DashboardController(repository: repository))),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Could not reach the server. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the Engineers tab with visits-synced / compliant ratios', (tester) async {
    _useMobileScreenSize(tester);
    final repository = _FakeDashboardRepository();
    repository.engineerResponse = EngineerDashboard(
      periodStart: DateTime(2026, 11, 16),
      periodEnd: DateTime(2026, 11, 30),
      engineers: const [
        EngineerPerformance(
          employeeId: 'ENG001',
          name: 'Dev Test Engineer With A Fairly Long Name For Layout Testing',
          visitsSynced: 3,
          compliantVisits: 2,
        ),
        EngineerPerformance(employeeId: 'ENG002', name: 'Dev Test Engineer Two', visitsSynced: 0, compliantVisits: 0),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: DashboardScreen(controller: DashboardController(repository: repository))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Engineers'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ENG001'), findsOneWidget);
    expect(find.text('2/3\ncompliant'), findsOneWidget);
    expect(find.textContaining('ENG002'), findsOneWidget);
    expect(find.text('0/0\ncompliant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fortnight navigation moves to the adjacent period without error', (tester) async {
    _useMobileScreenSize(tester);
    final repository = _FakeDashboardRepository()..respondToRequestedDate = true;
    repository.districtResponse = DistrictDashboard(
      periodStart: DateTime(2026, 11, 16),
      periodEnd: DateTime(2026, 11, 30),
      districts: const [],
    );

    await tester.pumpWidget(
      MaterialApp(home: DashboardScreen(controller: DashboardController(repository: repository))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Nov 16, 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Next fortnight'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dec 1, 2026'), findsOneWidget);
    expect(find.byTooltip('Jump to today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
