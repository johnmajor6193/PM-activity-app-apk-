import 'visit_sync_status.dart';

/// A single fortnightly PM visit to one POP, in progress (or completed
/// and pending sync) on this device.
///
/// Submission to a backend is not implemented yet. Google Drive upload
/// is not implemented yet either — [status] models the offline-first
/// sync lifecycle so that whichever is built first can use it without a
/// schema change; see VisitSyncStatus and SyncManager.
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
    this.status = VisitSyncStatus.localOnly,
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

  /// Returns a copy with [status] replaced. Used when all 5 photos are
  /// confirmed (-> pendingSync) or by the sync engine.
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
