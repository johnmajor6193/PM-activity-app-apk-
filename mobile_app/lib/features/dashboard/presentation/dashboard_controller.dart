import 'package:flutter/foundation.dart';

import '../data/dashboard_repository_impl.dart';
import '../domain/dashboard_failure.dart';
import '../domain/entities/district_compliance.dart';
import '../domain/entities/engineer_performance.dart';
import '../domain/repositories/dashboard_repository.dart';

enum DashboardLoadStatus { idle, loading, loaded, error }

/// Drives the Dashboard screen's two tabs (District-wise, Engineer-wise)
/// for a single selected fortnight. Depends only on [DashboardRepository].
///
/// The fortnight itself is never computed here: [selectedDate] is just
/// a date passed through to the backend (`fortnight_bounds`, see
/// backend/app/services/compliance.py), which is the single place that
/// business rule lives. "Previous"/"next fortnight" navigation reuses
/// the `periodStart`/`periodEnd` the backend already returned, rather
/// than re-deriving fortnight boundaries in Dart.
class DashboardController extends ChangeNotifier {
  DashboardController({DashboardRepository? repository})
      : _repository = repository ?? DashboardRepositoryImpl();

  final DashboardRepository _repository;

  DashboardLoadStatus districtStatus = DashboardLoadStatus.idle;
  DashboardLoadStatus engineerStatus = DashboardLoadStatus.idle;
  String? errorMessage;

  DistrictDashboard? districtDashboard;
  EngineerDashboard? engineerDashboard;

  /// null means "today" — the backend's own default.
  DateTime? selectedDate;

  bool get isLoading =>
      districtStatus == DashboardLoadStatus.loading ||
      engineerStatus == DashboardLoadStatus.loading;

  // These are real network calls: if DashboardScreen is popped while
  // one is in flight, the pending load must not call notifyListeners()
  // after this controller is disposed — Flutter throws for that.
  // Guards every notifyListeners() call below.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }

  Future<void> loadAll() {
    return Future.wait([loadDistricts(), loadEngineers()]);
  }

  Future<void> loadDistricts() async {
    districtStatus = DashboardLoadStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      districtDashboard = await _repository.getDistrictDashboard(date: selectedDate);
      districtStatus = DashboardLoadStatus.loaded;
    } on DashboardFailure catch (failure) {
      errorMessage = failure.message;
      districtStatus = DashboardLoadStatus.error;
    }
    notifyListeners();
  }

  Future<void> loadEngineers() async {
    engineerStatus = DashboardLoadStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      engineerDashboard = await _repository.getEngineerDashboard(date: selectedDate);
      engineerStatus = DashboardLoadStatus.loaded;
    } on DashboardFailure catch (failure) {
      errorMessage = failure.message;
      engineerStatus = DashboardLoadStatus.error;
    }
    notifyListeners();
  }

  /// The fortnight currently shown, from whichever of the two
  /// responses has loaded (they always agree, since both are driven
  /// by the same [selectedDate]).
  DateTime? get periodStart => districtDashboard?.periodStart ?? engineerDashboard?.periodStart;
  DateTime? get periodEnd => districtDashboard?.periodEnd ?? engineerDashboard?.periodEnd;

  bool get isShowingToday => selectedDate == null;

  void goToPreviousFortnight() {
    final start = periodStart;
    if (start == null) {
      return;
    }
    selectedDate = start.subtract(const Duration(days: 1));
    loadAll();
  }

  void goToNextFortnight() {
    final end = periodEnd;
    if (end == null) {
      return;
    }
    selectedDate = end.add(const Duration(days: 1));
    loadAll();
  }

  void goToToday() {
    if (isShowingToday) {
      return;
    }
    selectedDate = null;
    loadAll();
  }
}
