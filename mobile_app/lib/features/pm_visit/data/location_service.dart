import 'package:geolocator/geolocator.dart';

import '../domain/entities/gps_reading.dart';
import '../domain/pm_visit_failure.dart';

/// Captures a fresh, live GPS fix at the moment of each photograph.
///
/// This is called once per photo (by PmVisitController), not once per
/// visit — see requirement that GPS is captured at the time of each
/// photograph. It never compares the result against a POP's registered
/// coordinates: no such master data exists yet, and no geofence check
/// happens here or anywhere else in this module.
class LocationService {
  Future<GpsReading> getCurrentGpsReading() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const PmVisitFailure(
        'Turn on location services on this device to capture GPS for this photo.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw const PmVisitFailure(
        'Location permission is required to capture GPS for this photo.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    return GpsReading(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
    );
  }
}
