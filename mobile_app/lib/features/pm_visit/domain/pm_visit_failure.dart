/// Error raised by the PM visit camera/location/repository calls,
/// carrying a message safe to show to the user.
class PmVisitFailure implements Exception {
  const PmVisitFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
