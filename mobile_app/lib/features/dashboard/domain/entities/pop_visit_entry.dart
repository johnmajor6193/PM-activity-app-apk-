import 'pop_period_status.dart';

/// One synced visit for a POP, as returned by
/// `GET /api/v1/dashboard/pops/{pop_id}/visits` — mirrors the
/// backend's `PopVisitOut` exactly.
///
/// [visitDate] is the plain `YYYY-MM-DD` the backend stores — there is
/// deliberately no visit-level time-of-day field here: the mobile
/// app's sync payload never sends one (only each photo's own
/// `captured_at` has a time), and this stays honest about that rather
/// than fabricating one. [firstSyncedAt]/[lastSyncedAt] are full
/// timestamps, but they record when the backend received the sync,
/// not when the visit itself happened.
class PopVisitEntry {
  const PopVisitEntry({
    required this.visitId,
    required this.employeeId,
    required this.employeeName,
    required this.visitDate,
    required this.status,
    required this.photoCount,
    required this.isCompliant,
    required this.categoriesPresent,
    required this.categoriesMissing,
    required this.firstSyncedAt,
    required this.lastSyncedAt,
  });

  final String visitId;
  final String employeeId;
  final String employeeName;
  final String visitDate;

  /// Always [PopVisitStatus.completed] in practice — a visit only
  /// ever appears here because it was successfully synced; kept
  /// explicit rather than assumed from a row's mere presence.
  final PopVisitStatus status;
  final int photoCount;
  final bool isCompliant;
  final List<String> categoriesPresent;
  final List<String> categoriesMissing;
  final DateTime firstSyncedAt;
  final DateTime lastSyncedAt;
}
