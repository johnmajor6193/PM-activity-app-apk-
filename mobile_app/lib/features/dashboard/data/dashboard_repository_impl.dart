import '../domain/entities/district_compliance.dart';
import '../domain/entities/engineer_performance.dart';
import '../domain/entities/pop_period_status.dart';
import '../domain/entities/pop_visit_entry.dart';
import '../domain/repositories/dashboard_repository.dart';
import 'dashboard_api_client.dart';

/// [DashboardRepository] backed by the backend's /api/v1/dashboard
/// endpoints.
class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl({DashboardApiClient? apiClient})
      : _apiClient = apiClient ?? DashboardApiClient();

  final DashboardApiClient _apiClient;

  @override
  Future<DistrictDashboard> getDistrictDashboard({DateTime? date}) async {
    final json = await _apiClient.getDistrictDashboard(
      date: date == null ? null : _dateOnly(date),
    );
    return DistrictDashboard(
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      districts: (json['districts'] as List<dynamic>)
          .map((item) => _districtFromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<EngineerDashboard> getEngineerDashboard({DateTime? date}) async {
    final json = await _apiClient.getEngineerDashboard(
      date: date == null ? null : _dateOnly(date),
    );
    return EngineerDashboard(
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      engineers: (json['engineers'] as List<dynamic>)
          .map(
            (item) => EngineerPerformance(
              employeeId: item['employee_id'] as String,
              name: item['name'] as String,
              visitsSynced: item['visits_synced'] as int,
              compliantVisits: item['compliant_visits'] as int,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<List<PopVisitEntry>> getPopVisitHistory(int popId) async {
    final json = await _apiClient.getPopVisitHistory(popId);
    return json.map((item) => _visitFromJson(item as Map<String, dynamic>)).toList();
  }

  DistrictCompliance _districtFromJson(Map<String, dynamic> json) {
    return DistrictCompliance(
      districtId: json['district_id'] as int,
      districtName: json['district_name'] as String,
      totalActivePops: json['total_active_pops'] as int,
      compliantPops: json['compliant_pops'] as int,
      compliancePercent: (json['compliance_percent'] as num).toDouble(),
      completedPops: json['completed_pops'] as int,
      pendingPops: json['pending_pops'] as int,
      pops: (json['pops'] as List<dynamic>)
          .map((item) => _popStatusFromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  PopPeriodStatus _popStatusFromJson(Map<String, dynamic> json) {
    return PopPeriodStatus(
      popId: json['pop_id'] as int,
      popCode: json['pop_code'] as String,
      popName: json['pop_name'] as String?,
      status: popVisitStatusFromWire(json['status'] as String),
      isCompliant: json['is_compliant'] as bool,
      latestVisitId: json['latest_visit_id'] as String?,
      categoriesPresent: (json['categories_present'] as List<dynamic>).cast<String>(),
      categoriesMissing: (json['categories_missing'] as List<dynamic>).cast<String>(),
    );
  }

  PopVisitEntry _visitFromJson(Map<String, dynamic> json) {
    return PopVisitEntry(
      visitId: json['visit_id'] as String,
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String,
      visitDate: json['visit_date'] as String,
      status: popVisitStatusFromWire(json['status'] as String),
      photoCount: json['photo_count'] as int,
      isCompliant: json['is_compliant'] as bool,
      categoriesPresent: (json['categories_present'] as List<dynamic>).cast<String>(),
      categoriesMissing: (json['categories_missing'] as List<dynamic>).cast<String>(),
      firstSyncedAt: DateTime.parse(json['first_synced_at'] as String),
      lastSyncedAt: DateTime.parse(json['last_synced_at'] as String),
    );
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
