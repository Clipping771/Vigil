import 'package:geolocator/geolocator.dart';

import '../models/clock_event.dart';

/// Saves a site QR punch with the given position (null when there is none).
typedef SaveQrPunch = Future<ClockEvent> Function({double? latitude, double? longitude, required String siteCode});

/// The device's position, or null if it cannot be read for any reason: services
/// off, permission refused, or no fix in time. A scan still goes ahead without
/// one, and the database then records it as not on site for a manager to review.
Future<Position?> positionForQrPunch() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 8)));
  } catch (_) {
    return null;
  }
}

/// Records a scan of [siteCode] together with the current position, and returns
/// what to tell the employee.
Future<String> punchWithSiteCode({required String siteCode, required String siteName, required SaveQrPunch save}) async {
  final position = await positionForQrPunch();
  final punch = await save(latitude: position?.latitude, longitude: position?.longitude, siteCode: siteCode);
  return qrPunchMessage(siteName, punch);
}

/// Reports the database's decision on [punch], since a valid code alone no longer
/// means the employee is on site.
String qrPunchMessage(String siteName, ClockEvent punch) {
  if (punch.isGeofenced) return 'Clocked in at $siteName.';
  if (punch.latitude == null || punch.longitude == null) {
    return 'Clocked in, but your location could not be checked. Flagged for manager review.';
  }
  return 'Clocked in, but you are not at $siteName. Flagged for manager review.';
}
