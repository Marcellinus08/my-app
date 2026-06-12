import 'package:flutter_test/flutter_test.dart';
import 'package:teman_arah/models/family_location_model.dart';

void main() {
  group('FamilyLocation.fromMap', () {
    test('parses Realtime Database live tracking payload', () {
      final location = FamilyLocation.fromMap('user-1', {
        'lat': -6.977355,
        'lng': 107.632302,
        'speed': 1.25,
        'batteryLevel': 82,
        'gpsStatus': 'gps_live',
        'connectionStatus': 'online',
        'isNavigating': true,
        'destinationName': 'Indomaret',
        'updatedAt': 1781251200000,
      });

      expect(location.uid, 'user-1');
      expect(location.latitude, -6.977355);
      expect(location.longitude, 107.632302);
      expect(location.speed, 1.25);
      expect(location.battery, 82);
      expect(location.gpsEnabled, isTrue);
      expect(location.internetAvailable, isTrue);
      expect(location.navigationStatus, 'navigating');
      expect(location.destination, 'Indomaret');
      expect(
        location.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1781251200000),
      );
    });

    test('accepts numeric strings and missing optional fields', () {
      final location = FamilyLocation.fromMap('user-2', {
        'latitude': '-6.9',
        'longitude': '107.6',
        'battery': '20',
        'timestamp': '1781251200000',
      });

      expect(location.latitude, -6.9);
      expect(location.longitude, 107.6);
      expect(location.battery, 20);
      expect(location.gpsEnabled, isFalse);
      expect(location.internetAvailable, isFalse);
      expect(location.navigationStatus, 'idle');
    });
  });
}
