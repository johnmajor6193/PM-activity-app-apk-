/// Error raised by [DashboardRepository] calls, carrying a message
/// safe to show to the user.
class DashboardFailure implements Exception {
  const DashboardFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
