/// A single live GPS fix taken at the moment a photo was captured.
///
/// This is NOT the POP's own registered location (that master data does
/// not exist yet) — it is only where this specific photo was taken, and
/// nothing in this module compares it against a POP coordinate.
class GpsReading {
  const GpsReading({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
}

extension GpsReadingValidation on GpsReading {
  /// A basic sanity check on the values themselves — not geofence
  /// validation; no POP coordinate is involved, and this never compares
  /// against one. Rejects only structurally-impossible readings (e.g.
  /// NaN, out-of-range latitude/longitude, a negative accuracy), which
  /// could only reach here via corrupted/legacy data, since the normal
  /// capture flow (LocationService) never produces these.
  bool get isPlausible {
    if (latitude.isNaN || longitude.isNaN || accuracyMeters.isNaN) {
      return false;
    }
    if (latitude < -90 || latitude > 90) {
      return false;
    }
    if (longitude < -180 || longitude > 180) {
      return false;
    }
    if (accuracyMeters < 0) {
      return false;
    }
    return true;
  }
}
