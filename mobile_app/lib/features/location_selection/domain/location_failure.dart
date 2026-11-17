/// Error raised by [LocationRepository] calls (see
/// repositories/location_repository.dart), carrying a message safe to
/// show to the user.
class LocationFailure implements Exception {
  const LocationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
