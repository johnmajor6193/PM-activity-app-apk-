/// One active Employee's visit count/compliance for a single
/// fortnight — mirrors the backend's `EngineerComplianceOut` exactly.
/// Every active employee is included, even with zero visits.
class EngineerPerformance {
  const EngineerPerformance({
    required this.employeeId,
    required this.name,
    required this.visitsSynced,
    required this.compliantVisits,
  });

  final String employeeId;
  final String name;
  final int visitsSynced;
  final int compliantVisits;
}

/// The full response from `GET /api/v1/dashboard/engineers`.
class EngineerDashboard {
  const EngineerDashboard({
    required this.periodStart,
    required this.periodEnd,
    required this.engineers,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final List<EngineerPerformance> engineers;
}
