import 'package:geolocator/geolocator.dart';

/// Best-effort GPS fix for tagging a report. Never throws; returns null if unavailable.
class LocationService {
  LocationService._();

  static Future<Position?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return await Geolocator.getLastKnownPosition();
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }
}
