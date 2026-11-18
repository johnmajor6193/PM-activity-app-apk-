import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/pm_visit/data/connectivity_service.dart';
import 'package:mobile_app/features/pm_visit/data/sync_manager.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/pm_photo_record.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/pm_visit.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/photo_category.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/visit_sync_status.dart';
import 'package:mobile_app/features/pm_visit/domain/repositories/pm_visit_repository.dart';
import 'package:mobile_app/features/pm_visit/domain/services/drive_upload_service.dart';

/// In-memory stand-in for the real SQLite repository, tracking status
/// changes the same way the real one would.
class _FakeRepository implements PmVisitRepository {
  final Map<String, PmVisit> visits = {};
  final List<VisitSyncStatus> statusHistoryForLastVisit = [];

  void seed(PmVisit visit) => visits[visit.id] = visit;

  @override
  Future<PmVisit> startVisit({
    required String employeeId,
    required int popId,
    required String popCode,
    required String districtName,
    required String blockName,
    required String gpName,
  }) async {
    throw UnimplementedError('not used by these tests');
  }

  @override
  Future<PmVisit?> getResumableVisit(int popId) async => null;

  @override
  Future<PmVisit?> getVisit(String visitId) async => visits[visitId];

  @override
  Future<List<PmVisit>> getVisitsByStatus(List<VisitSyncStatus> statuses) async {
    return visits.values.where((v) => statuses.contains(v.status)).toList();
  }

  @override
  Future<void> updateVisitStatus(String visitId, VisitSyncStatus status) async {
    final current = visits[visitId];
    if (current != null) {
      visits[visitId] = current.copyWithStatus(status);
      statusHistoryForLastVisit.add(status);
    }
  }

  @override
  Future<void> savePhoto(PmPhotoRecord record) async {
    throw UnimplementedError('not used by these tests');
  }

  @override
  Future<Map<PhotoCategory, PmPhotoRecord>> getPhotosForVisit(String visitId) async => {};
}

class _FakeConnectivityService extends ConnectivityService {
  bool online = true;

  @override
  Future<bool> hasConnection() async => online;
}

/// Fails only for visits whose id is in [failForVisitIds], so tests can
/// exercise mixed success/failure across several visits in one call to
/// trySyncPendingVisits.
class _FakeDriveUploadService implements DriveUploadService {
  final Set<String> failForVisitIds = {};
  int callCount = 0;

  @override
  Future<void> uploadVisit(PmVisit visit, List<PmPhotoRecord> photos) async {
    callCount++;
    if (failForVisitIds.contains(visit.id)) {
      throw Exception('Simulated Drive upload failure for ${visit.id}');
    }
  }
}

PmVisit buildVisit({required String id, VisitSyncStatus status = VisitSyncStatus.pendingSync}) {
  return PmVisit(
    id: id,
    employeeId: 'ENG001',
    popId: 7,
    popCode: 'POP-CHN-001',
    districtName: 'Chennai',
    blockName: 'Sholinganallur',
    gpName: 'Semmancheri GP',
    startedAt: DateTime(2026, 2, 1),
    status: status,
  );
}

void main() {
  late _FakeRepository repository;
  late _FakeConnectivityService connectivity;
  late _FakeDriveUploadService driveUploadService;
  late SyncManager syncManager;

  setUp(() {
    repository = _FakeRepository();
    connectivity = _FakeConnectivityService();
    driveUploadService = _FakeDriveUploadService();
    syncManager = SyncManager(
      repository: repository,
      connectivityService: connectivity,
      driveUploadService: driveUploadService,
    );
  });

  test('a visit syncs through SYNCING to SYNCED when upload succeeds', () async {
    final visit = buildVisit(id: 'v1');
    repository.seed(visit);

    final result = await syncManager.syncVisit(visit);

    expect(result.outcome, SyncOutcome.synced);
    expect(repository.visits['v1']!.status, VisitSyncStatus.synced);
    expect(repository.statusHistoryForLastVisit, [
      VisitSyncStatus.syncing,
      VisitSyncStatus.synced,
    ]);
  });

  test('a failed upload leaves the visit as SYNC_FAILED, not deleted or silently reverted', () async {
    final visit = buildVisit(id: 'v1');
    repository.seed(visit);
    driveUploadService.failForVisitIds.add('v1');

    final result = await syncManager.syncVisit(visit);

    expect(result.outcome, SyncOutcome.failed);
    expect(result.message, isNotNull);
    expect(repository.visits['v1'], isNotNull); // never removed
    expect(repository.visits['v1']!.status, VisitSyncStatus.syncFailed);
  });

  test('retrying a SYNC_FAILED visit after the upload succeeds transitions it to SYNCED', () async {
    final visit = buildVisit(id: 'v1');
    repository.seed(visit);
    driveUploadService.failForVisitIds.add('v1');

    final firstAttempt = await syncManager.syncVisit(visit);
    expect(firstAttempt.outcome, SyncOutcome.failed);

    driveUploadService.failForVisitIds.remove('v1');
    final retriedVisit = repository.visits['v1']!;
    final secondAttempt = await syncManager.syncVisit(retriedVisit);

    expect(secondAttempt.outcome, SyncOutcome.synced);
    expect(repository.visits['v1']!.status, VisitSyncStatus.synced);
    expect(driveUploadService.callCount, 2);
  });

  test('without a connection, nothing is attempted and the visit status is untouched', () async {
    final visit = buildVisit(id: 'v1', status: VisitSyncStatus.syncFailed);
    repository.seed(visit);
    connectivity.online = false;

    final result = await syncManager.syncVisit(visit);

    expect(result.outcome, SyncOutcome.skippedNoConnection);
    expect(driveUploadService.callCount, 0);
    expect(repository.visits['v1']!.status, VisitSyncStatus.syncFailed); // unchanged
    expect(repository.statusHistoryForLastVisit, isEmpty); // status was never written to
  });

  test('getVisitsEligibleForSync returns PENDING_SYNC and SYNC_FAILED visits only', () async {
    repository.seed(buildVisit(id: 'pending', status: VisitSyncStatus.pendingSync));
    repository.seed(buildVisit(id: 'failed', status: VisitSyncStatus.syncFailed));
    repository.seed(buildVisit(id: 'local', status: VisitSyncStatus.draft));
    repository.seed(buildVisit(id: 'synced', status: VisitSyncStatus.synced));

    final eligible = await syncManager.getVisitsEligibleForSync();

    expect(eligible.map((v) => v.id), containsAll(<String>['pending', 'failed']));
    expect(eligible.map((v) => v.id), isNot(contains('local')));
    expect(eligible.map((v) => v.id), isNot(contains('synced')));
  });

  test(
    'trySyncPendingVisits attempts every eligible visit, and one failure does not stop the rest',
    () async {
      repository.seed(buildVisit(id: 'will-succeed', status: VisitSyncStatus.pendingSync));
      repository.seed(buildVisit(id: 'will-fail', status: VisitSyncStatus.syncFailed));
      driveUploadService.failForVisitIds.add('will-fail');

      final outcomes = await syncManager.trySyncPendingVisits();

      expect(outcomes.length, 2);
      expect(outcomes['will-succeed']!.outcome, SyncOutcome.synced);
      expect(outcomes['will-fail']!.outcome, SyncOutcome.failed);
      expect(driveUploadService.callCount, 2);
      expect(repository.visits['will-succeed']!.status, VisitSyncStatus.synced);
      expect(repository.visits['will-fail']!.status, VisitSyncStatus.syncFailed);
    },
  );
}
