import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyLocation {
  final String uid;
  final double latitude;
  final double longitude;
  final double speed; // m/s
  final double battery; // 0-100
  final bool gpsEnabled;
  final bool internetAvailable;
  final String navigationStatus; // e.g., "idle", "walking", "navigating"
  final String? destination;
  final DateTime timestamp;

  FamilyLocation({
    required this.uid,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.battery,
    required this.gpsEnabled,
    required this.internetAvailable,
    required this.navigationStatus,
    this.destination,
    required this.timestamp,
  });

  factory FamilyLocation.fromMap(String uid, Map<dynamic, dynamic> map) {
    final rawTimestamp = map['updatedAt'] ?? map['timestamp'];
    final timestampMilliseconds = rawTimestamp is num
        ? rawTimestamp.round()
        : int.tryParse(rawTimestamp?.toString() ?? '') ?? 0;

    return FamilyLocation(
      uid: uid,
      latitude: _toDouble(map['lat'] ?? map['latitude']),
      longitude: _toDouble(map['lng'] ?? map['longitude']),
      speed: _toDouble(map['speed']),
      battery: _toDouble(map['batteryLevel'] ?? map['battery']),
      gpsEnabled: map['gpsStatus'] == 'gps_live',
      internetAvailable: map['connectionStatus'] == 'online',
      navigationStatus: map['isNavigating'] == true ? 'navigating' : 'idle',
      destination: (map['destinationName'] ?? map['destination'])?.toString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMilliseconds),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory FamilyLocation.fromFirestore(DocumentSnapshot doc) {
    final map = doc.data() as Map<String, dynamic>;
    return FamilyLocation(
      uid: doc.id,
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      speed: (map['speed'] ?? 0).toDouble(),
      battery: (map['battery'] ?? 0).toDouble(),
      gpsEnabled: (map['gpsEnabled'] ?? true) as bool,
      internetAvailable: (map['internetAvailable'] ?? true) as bool,
      navigationStatus: (map['navigationStatus'] ?? 'idle') as String,
      destination: map['destination'] as String?,
      timestamp: (map['timestamp'] is Timestamp)
          ? (map['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
