/// A single fortnightly PM visit to one POP, in progress on this device.
///
/// Submission to the backend is not implemented yet — see
/// PmVisitRepository for why this is local-only for now.
class PmVisit {
  const PmVisit({
    required this.id,
    required this.popId,
    required this.popCode,
    required this.startedAt,
  });

  /// Locally-generated identifier (not a backend ID — there is no
  /// backend visit record yet).
  final String id;
  final int popId;
  final String popCode;
  final DateTime startedAt;
}
