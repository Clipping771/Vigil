import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vigil/models/clock_event.dart';
import 'package:vigil/services/qr_punch.dart';

/// A device whose location services, permission and fix the test controls.
class _FakeGeolocator extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission answerToRequest = LocationPermission.denied;
  Object? fixError;
  int permissionRequests = 0;
  int fixRequests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return answerToRequest;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    fixRequests++;
    if (fixError != null) throw fixError!;
    return Position(
      latitude: -33.87,
      longitude: 151.21,
      timestamp: DateTime(2026),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

ClockEvent _punch({bool onSite = false, double? lat, double? lng}) => ClockEvent(
      id: 'p',
      organizationId: 'org-1',
      employeeId: 'e-1',
      eventType: 'clock_in',
      eventTime: DateTime(2026),
      latitude: lat,
      longitude: lng,
      isGeofenced: onSite,
      createdAt: DateTime(2026),
    );

void main() {
  late _FakeGeolocator device;

  setUp(() {
    device = _FakeGeolocator();
    GeolocatorPlatform.instance = device;
  });

  group('Position for a QR punch', () {
    test('is read when location is available', () async {
      final position = await positionForQrPunch();
      expect(position?.latitude, -33.87);
      expect(position?.longitude, 151.21);
      expect(device.permissionRequests, 0);
    });

    test('asks for permission the first time, then reads it', () async {
      device
        ..permission = LocationPermission.denied
        ..answerToRequest = LocationPermission.whileInUse;
      expect(await positionForQrPunch(), isNotNull);
      expect(device.permissionRequests, 1);
    });

    test('is null with location services off', () async {
      device.serviceEnabled = false;
      expect(await positionForQrPunch(), isNull);
      expect(device.fixRequests, 0);
    });

    test('is null when permission is refused', () async {
      device.permission = LocationPermission.denied;
      expect(await positionForQrPunch(), isNull);
      expect(device.fixRequests, 0);
    });

    test('is null when permission is permanently refused, without asking again', () async {
      device.permission = LocationPermission.deniedForever;
      expect(await positionForQrPunch(), isNull);
      expect(device.permissionRequests, 0);
      expect(device.fixRequests, 0);
    });

    test('is null when no fix arrives in time', () async {
      device.fixError = TimeoutException('no fix');
      expect(await positionForQrPunch(), isNull);
    });
  });

  group('Scanning a site QR code', () {
    Future<(String, Map<String, Object?>)> scan(ClockEvent saved) async {
      final sent = <String, Object?>{};
      final message = await punchWithSiteCode(
        siteCode: 'vigil:site:zone-1:secret',
        siteName: 'Depot',
        save: ({latitude, longitude, required siteCode}) async {
          sent.addAll({'latitude': latitude, 'longitude': longitude, 'siteCode': siteCode});
          return saved;
        },
      );
      return (message, sent);
    }

    test('sends the code together with the position', () async {
      final (_, sent) = await scan(_punch(onSite: true, lat: -33.87, lng: 151.21));
      expect(sent, {'latitude': -33.87, 'longitude': 151.21, 'siteCode': 'vigil:site:zone-1:secret'});
    });

    test('still punches when location is unavailable, and says it will be reviewed', () async {
      device.serviceEnabled = false;
      final (message, sent) = await scan(_punch());
      expect(sent, {'latitude': null, 'longitude': null, 'siteCode': 'vigil:site:zone-1:secret'});
      expect(message, contains('could not be checked'));
      expect(message, contains('manager review'));
    });

    test('a failed save reaches the caller', () async {
      await expectLater(
        punchWithSiteCode(
          siteCode: 'bad',
          siteName: 'Depot',
          save: ({latitude, longitude, required siteCode}) async => throw StateError('invalid site code'),
        ),
        throwsStateError,
      );
    });
  });

  group('Message after a QR punch', () {
    test('names the site only when the database put the punch on site', () {
      expect(qrPunchMessage('Depot', _punch(onSite: true, lat: -33.87, lng: 151.21)), 'Clocked in at Depot.');
    });

    test('says the employee is not at the site when the position is elsewhere', () {
      final message = qrPunchMessage('Depot', _punch(lat: -34.5, lng: 150.5));
      expect(message, contains('not at Depot'));
      expect(message, contains('manager review'));
    });

    test('says the location could not be checked when there is none', () {
      final message = qrPunchMessage('Depot', _punch());
      expect(message, contains('could not be checked'));
      expect(message, isNot(contains('Clocked in at Depot')));
    });
  });
}
