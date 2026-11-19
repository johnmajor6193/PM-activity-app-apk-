/// Whether a POP has a successfully synced visit for the fortnight
/// being reported on.
///
/// `completed` means only "at least one visit was successfully synced
/// this period" — it says nothing about whether that visit had all 5
/// mandatory categories (see [PopPeriodStatus.isCompliant] for that).
/// `pending` means only "no synced visit yet this period" — it cannot
/// distinguish an engineer currently out at this POP from one who
/// hasn't started, because the mobile app's draft/inProgress/
/// pendingSync/syncFailed states are never sent to the backend at all
/// (see backend/app/services/compliance.py and docs/data-model.md,
/// "Completed vs pending"). Nothing here infers or fakes that
/// distinction.
enum PopVisitStatus { completed, pending }

PopVisitStatus popVisitStatusFromWire(String value) {
  switch (value) {
    case 'completed':
      return PopVisitStatus.completed;
    case 'pending':
      return PopVisitStatus.pending;
    default:
      throw ArgumentError('Unknown POP visit status from backend: $value');
  }
}

/// One active POP's status for a single fortnight — mirrors the
/// backend's `PopPeriodStatusOut` (backend/app/schemas/dashboard.py)
/// exactly; no fields added or inferred beyond what the API returns.
class PopPeriodStatus {
  const PopPeriodStatus({
    required this.popId,
    required this.popCode,
    required this.popName,
    required this.status,
    required this.isCompliant,
    required this.latestVisitId,
    required this.categoriesPresent,
    required this.categoriesMissing,
  });

  final int popId;
  final String popCode;
  final String? popName;
  final PopVisitStatus status;

  /// Only meaningful when [status] is `completed` — always `false`
  /// when `pending`, since there is no visit to be compliant.
  final bool isCompliant;

  /// The visit this status/category breakdown was computed from, or
  /// null when [status] is `pending`.
  final String? latestVisitId;

  /// The mandatory photo categories (storage-key spelling, e.g.
  /// `pop_rack`) found for [latestVisitId] — empty when `pending`.
  final List<String> categoriesPresent;

  /// The mandatory categories *not* found — all 5 when `pending`.
  final List<String> categoriesMissing;
}
