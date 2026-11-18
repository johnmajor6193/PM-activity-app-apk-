/// The full lifecycle of a PM visit, from first capture through a
/// confirmed Google Drive upload.
///
/// ```
/// draft -> inProgress -> readyForSubmission -> pendingSync -> syncing -> synced -> submitted
///                                                                 \-> syncFailed (retry-safe)
/// ```
///
/// - [draft]: visit started; no photo confirmed yet.
/// - [inProgress]: at least one, but fewer than all 5, mandatory photos
///   confirmed.
/// - [readyForSubmission]: all 5 mandatory photos confirmed and valid
///   (see PmPhotoRecordValidation.isValidForSubmission) — not yet sent
///   for sync. The engineer reviews and explicitly submits from here;
///   see PmVisitSubmissionScreen.
/// - [pendingSync]: submission requested; eligible for sync whenever
///   connectivity allows (see SyncManager — unchanged from the
///   Offline Storage & Synchronization module).
/// - [syncing]: a sync attempt is in progress right now.
/// - [synced]: the Google Drive upload succeeded.
/// - [submitted]: the terminal state — set immediately after [synced]
///   (see PmVisitController.submitVisit) so there is one unambiguous
///   "fully done" status, and so a second submission can be refused
///   (submission is only allowed from [readyForSubmission] or
///   [syncFailed]).
/// - [syncFailed]: the most recent sync attempt failed. The visit and
///   its photos are **never** deleted for this; it stays eligible for
///   retry from the submission screen.
enum VisitSyncStatus {
  draft,
  inProgress,
  readyForSubmission,
  pendingSync,
  syncing,
  synced,
  submitted,
  syncFailed,
}

extension VisitSyncStatusX on VisitSyncStatus {
  String get label {
    switch (this) {
      case VisitSyncStatus.draft:
        return 'Draft';
      case VisitSyncStatus.inProgress:
        return 'In Progress';
      case VisitSyncStatus.readyForSubmission:
        return 'Ready for Submission';
      case VisitSyncStatus.pendingSync:
        return 'Pending Sync';
      case VisitSyncStatus.syncing:
        return 'Syncing…';
      case VisitSyncStatus.synced:
        return 'Synced';
      case VisitSyncStatus.submitted:
        return 'Submitted';
      case VisitSyncStatus.syncFailed:
        return 'Sync Failed';
    }
  }
}
