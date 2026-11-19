import '../entities/district_compliance.dart';
import '../entities/engineer_performance.dart';
import '../entities/pop_visit_entry.dart';

/// Abstraction over the backend's `/api/v1/dashboard/*` read-only
/// endpoints (already implemented and verified — see
/// docs/data-model.md, "District / Engineer / POP-wise Dashboard").
/// Implemented by DashboardRepositoryImpl (../data/), which requires
/// the same JWT session as every other protected endpoint (see
/// core/network/auth_session.dart) — nothing new is added for auth.
abstract class DashboardRepository {
  /// District-wise compliance for the fortnight containing [date], or
  /// today's fortnight if [date] is omitted.
  Future<DistrictDashboard> getDistrictDashboard({DateTime? date});

  /// Engineer-wise visit counts/compliance for the same fortnight rules.
  Future<EngineerDashboard> getEngineerDashboard({DateTime? date});

  /// Every synced visit for one POP, most recent first — not windowed
  /// to a fortnight.
  Future<List<PopVisitEntry>> getPopVisitHistory(int popId);
}
