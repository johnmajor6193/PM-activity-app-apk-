import 'pop_period_status.dart';

/// One District's compliance summary for a single fortnight — mirrors
/// the backend's `DistrictComplianceOut` exactly.
///
/// [compliantPops]/[compliancePercent] mean "5/5 mandatory categories
/// synced" specifically; [completedPops]/[pendingPops] are the
/// broader "had any synced visit at all" count — see
/// [PopPeriodStatus] for why these are different axes.
class DistrictCompliance {
  const DistrictCompliance({
    required this.districtId,
    required this.districtName,
    required this.totalActivePops,
    required this.compliantPops,
    required this.compliancePercent,
    required this.completedPops,
    required this.pendingPops,
    required this.pops,
  });

  final int districtId;
  final String districtName;
  final int totalActivePops;
  final int compliantPops;
  final double compliancePercent;
  final int completedPops;
  final int pendingPops;
  final List<PopPeriodStatus> pops;
}

/// The full response from `GET /api/v1/dashboard/districts`.
class DistrictDashboard {
  const DistrictDashboard({
    required this.periodStart,
    required this.periodEnd,
    required this.districts,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final List<DistrictCompliance> districts;
}
