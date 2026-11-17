/// The offline-first synchronization lifecycle of a PM visit.
///
/// - [localOnly]: visit started; photos are still being captured.
///   Nothing to sync yet.
/// - [pendingSync]: all 5 mandatory photos are confirmed. Eligible for
///   sync whenever connectivity allows.
/// - [syncing]: a sync attempt is in progress right now.
/// - [synced]: sync completed successfully. Not reachable yet in this
///   module — Google Drive upload isn't implemented (see
///   DriveUploadService) — but the state exists so the real
///   implementation needs no schema/state-machine change later.
/// - [syncFailed]: the most recent sync attempt failed. The visit and
///   its photos are never deleted for this; it stays eligible for retry.
enum VisitSyncStatus { localOnly, pendingSync, syncing, synced, syncFailed }
