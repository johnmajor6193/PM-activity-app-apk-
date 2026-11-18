import 'visit_sync_status.dart';

/// A single fortnightly PM visit to one POP, moving through its full
/// lifecycle on this device — see VisitSyncStatus for the state
/// machine (draft -> ... -> submitted, or -> syncFailed).
///
/// Submission to a backend visit-record table is not implemented;
/// "submission" here means the local lifecycle (requirement: the
/// engineer explicitly submits once ready) that triggers the existing
/// Google Drive sync — see PmVisitController.submitVisit and
/// SyncManager, both otherwise unchanged by this.
class PmVisit {
  const PmVisit({
    required this.id,
    required this.employeeId,
    required this.popId,
    required this.popCode,
    required this.districtName,
    required this.blockName,
    required this.gpName,
    required this.startedAt,
    this.status = VisitSyncStatus.draft,
  });

  /// Locally-generated identifier (not a backend ID — there is no
  /// backend visit record yet).
  final String id;
  final String employeeId;
  final int popId;
  final String popCode;
  final String districtName;
  final String blockName;
  final String gpName;
  final DateTime startedAt;
  final VisitSyncStatus status;

  /// Returns a copy with [status] replaced. Used as photos are
  /// confirmed, when the engineer submits, and by the sync engine.
  PmVisit copyWithStatus(VisitSyncStatus status) {
    return PmVisit(
      id: id,
      employeeId: employeeId,
      popId: popId,
      popCode: popCode,
      districtName: districtName,
      blockName: blockName,
      gpName: gpName,
      startedAt: startedAt,
      status: status,
    );
  }
}
