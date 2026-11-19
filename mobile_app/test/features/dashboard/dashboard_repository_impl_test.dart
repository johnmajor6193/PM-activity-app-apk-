import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/features/dashboard/data/dashboard_api_client.dart';
import 'package:mobile_app/features/dashboard/data/dashboard_repository_impl.dart';
import 'package:mobile_app/features/dashboard/domain/entities/pop_period_status.dart';

/// Verifies DashboardRepositoryImpl maps the backend's real response
/// shape (see backend/app/schemas/dashboard.py, and the live JSON
/// captured while verifying the backend module) into the Dart domain
/// entities field-for-field — not just that the HTTP call succeeds.
void main() {
  test('getDistrictDashboard maps period and nested per-POP breakdown correctly', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'period_start': '2026-11-16',
          'period_end': '2026-11-30',
          'districts': [
            {
              'district_id': 1,
              'district_name': 'Chennai',
              'total_active_pops': 3,
              'compliant_pops': 1,
              'compliance_percent': 33.3,
              'completed_pops': 2,
              'pending_pops': 1,
              'pops': [
                {
                  'pop_id': 1,
                  'pop_code': 'POP-CHN-001',
                  'pop_name': 'Semmancheri POP 1',
                  'status': 'completed',
                  'is_compliant': true,
                  'latest_visit_id': 'visit-1',
                  'categories_present': [
                    'busbar',
                    'earth_pit_chamber',
                    'earth_pit_open_with_rod',
                    'pop_rack',
                    'ups_battery',
                  ],
                  'categories_missing': [],
                },
                {
                  'pop_id': 4,
                  'pop_code': 'POP-CHN-004',
                  'pop_name': 'Chitlapakkam POP 1',
                  'status': 'pending',
                  'is_compliant': false,
                  'latest_visit_id': null,
                  'categories_present': [],
                  'categories_missing': [
                    'busbar',
                    'earth_pit_chamber',
                    'earth_pit_open_with_rod',
                    'pop_rack',
                    'ups_battery',
                  ],
                },
              ],
            },
          ],
        }),
        200,
      ),
    );

    final repository = DashboardRepositoryImpl(apiClient: DashboardApiClient(httpClient: client));
    final dashboard = await repository.getDistrictDashboard();

    expect(dashboard.periodStart, DateTime(2026, 11, 16));
    expect(dashboard.periodEnd, DateTime(2026, 11, 30));
    expect(dashboard.districts, hasLength(1));

    final chennai = dashboard.districts.single;
    expect(chennai.districtName, 'Chennai');
    expect(chennai.totalActivePops, 3);
    expect(chennai.compliantPops, 1);
    expect(chennai.compliancePercent, 33.3);
    expect(chennai.completedPops, 2);
    expect(chennai.pendingPops, 1);
    expect(chennai.pops, hasLength(2));

    final completed = chennai.pops.first;
    expect(completed.popCode, 'POP-CHN-001');
    expect(completed.status, PopVisitStatus.completed);
    expect(completed.isCompliant, isTrue);
    expect(completed.latestVisitId, 'visit-1');
    expect(completed.categoriesMissing, isEmpty);

    final pending = chennai.pops.last;
    expect(pending.popCode, 'POP-CHN-004');
    expect(pending.status, PopVisitStatus.pending);
    expect(pending.isCompliant, isFalse);
    expect(pending.latestVisitId, isNull);
    expect(pending.categoriesPresent, isEmpty);
    expect(pending.categoriesMissing, hasLength(5));
  });

  test('getDistrictDashboard passes a YYYY-MM-DD date to the API client', () async {
    Uri? requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        jsonEncode({'period_start': '2026-11-01', 'period_end': '2026-11-15', 'districts': []}),
        200,
      );
    });

    final repository = DashboardRepositoryImpl(apiClient: DashboardApiClient(httpClient: client));
    await repository.getDistrictDashboard(date: DateTime(2026, 11, 5));

    expect(requestedUri!.queryParameters['date'], '2026-11-05');
  });

  test('getEngineerDashboard maps every field, including zero-visit employees', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'period_start': '2026-11-16',
          'period_end': '2026-11-30',
          'engineers': [
            {'employee_id': 'ENG001', 'name': 'Dev Test Engineer', 'visits_synced': 2, 'compliant_visits': 1},
            {'employee_id': 'ENG002', 'name': 'Dev Test Engineer Two', 'visits_synced': 0, 'compliant_visits': 0},
          ],
        }),
        200,
      ),
    );

    final repository = DashboardRepositoryImpl(apiClient: DashboardApiClient(httpClient: client));
    final dashboard = await repository.getEngineerDashboard();

    expect(dashboard.engineers, hasLength(2));
    expect(dashboard.engineers[0].employeeId, 'ENG001');
    expect(dashboard.engineers[0].visitsSynced, 2);
    expect(dashboard.engineers[0].compliantVisits, 1);
    expect(dashboard.engineers[1].employeeId, 'ENG002');
    expect(dashboard.engineers[1].visitsSynced, 0);
  });

  test('getPopVisitHistory maps category breakdown and sync timestamps', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode([
          {
            'visit_id': 'visit-1',
            'employee_id': 'ENG001',
            'employee_name': 'Dev Test Engineer',
            'visit_date': '2026-11-17',
            'status': 'completed',
            'photo_count': 3,
            'is_compliant': false,
            'categories_present': ['pop_rack', 'ups_battery', 'busbar'],
            'categories_missing': ['earth_pit_chamber', 'earth_pit_open_with_rod'],
            'first_synced_at': '2026-11-17T10:00:00',
            'last_synced_at': '2026-11-17T10:05:00',
          },
        ]),
        200,
      ),
    );

    final repository = DashboardRepositoryImpl(apiClient: DashboardApiClient(httpClient: client));
    final visits = await repository.getPopVisitHistory(1);

    expect(visits, hasLength(1));
    final visit = visits.single;
    expect(visit.visitId, 'visit-1');
    expect(visit.employeeName, 'Dev Test Engineer');
    expect(visit.visitDate, '2026-11-17');
    expect(visit.status, PopVisitStatus.completed);
    expect(visit.photoCount, 3);
    expect(visit.isCompliant, isFalse);
    expect(visit.categoriesPresent, ['pop_rack', 'ups_battery', 'busbar']);
    expect(visit.categoriesMissing, ['earth_pit_chamber', 'earth_pit_open_with_rod']);
    expect(visit.firstSyncedAt, DateTime(2026, 11, 17, 10, 0, 0));
    expect(visit.lastSyncedAt, DateTime(2026, 11, 17, 10, 5, 0));
  });

  test('getPopVisitHistory returns an empty list for a POP with no visits', () async {
    final client = MockClient((request) async => http.Response(jsonEncode([]), 200));

    final repository = DashboardRepositoryImpl(apiClient: DashboardApiClient(httpClient: client));
    final visits = await repository.getPopVisitHistory(999);

    expect(visits, isEmpty);
  });
}
