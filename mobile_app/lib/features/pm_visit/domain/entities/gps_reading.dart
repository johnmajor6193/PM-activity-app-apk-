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
