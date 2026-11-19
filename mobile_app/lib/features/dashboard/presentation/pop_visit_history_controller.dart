import 'package:flutter/foundation.dart';

import '../../location_selection/data/location_repository_impl.dart';
import '../../location_selection/domain/entities/pop_detail.dart';
import '../../location_selection/domain/location_failure.dart';
import '../../location_selection/domain/repositories/location_repository.dart';
import '../data/dashboard_repository_impl.dart';
import '../domain/dashboard_failure.dart';
import '../domain/entities/pop_visit_entry.dart';
import '../domain/repositories/dashboard_repository.dart';
import 'dashboard_controller.dart';

/// Drives the POP visit history screen: the POP's District/Block/GP
/// context (reusing the existing, unchanged [LocationRepository] and
/// its already-implemented `GET /locations/pops/{id}` — not a new
/// endpoint) alongside its synced-visit history from
/// [DashboardRepository]. Neither repository is modified; this
/// controller only combines two already-verified read paths.
class PopVisitHistoryController extends ChangeNotifier {
  PopVisitHistoryController({
    DashboardRepository? dashboardRepository,
    LocationRepository? locationRepository,
  }) : _dashboardRepository = dashboardRepository ?? DashboardRepositoryImpl(),
       _locationRepository = locationRepository ?? LocationRepositoryImpl();

  final DashboardRepository _dashboardRepository;
  final LocationRepository _locationRepository;

  DashboardLoadStatus status = DashboardLoadStatus.idle;
  String? errorMessage;
  PopDetail? popDetail;
  List<PopVisitEntry> visits = [];

  // These are real network calls: if the screen is popped while one is
  // in flight, the pending load must not call notifyListeners() after
  // this controller is disposed — Flutter throws for that. Guards every
  // notifyListeners() call below.
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

  Future<void> load(int popId) async {
    status = DashboardLoadStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _locationRepository.getPopDetail(popId),
        _dashboardRepository.getPopVisitHistory(popId),
      ]);
      popDetail = results[0] as PopDetail;
      visits = results[1] as List<PopVisitEntry>;
      status = DashboardLoadStatus.loaded;
    } on LocationFailure catch (failure) {
      errorMessage = failure.message;
      status = DashboardLoadStatus.error;
    } on DashboardFailure catch (failure) {
      errorMessage = failure.message;
      status = DashboardLoadStatus.error;
    }
    notifyListeners();
  }
}
