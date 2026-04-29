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
    return FamilyLocation(
      uid: uid,
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      speed: (map['speed'] ?? 0).toDouble(),
      battery: (map['battery'] ?? 0).toDouble(),
      gpsEnabled: (map['gpsEnabled'] ?? true) as bool,
      internetAvailable: (map['internetAvailable'] ?? true) as bool,
      navigationStatus: (map['navigationStatus'] ?? 'idle') as String,
      destination: map['destination'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch((map['timestamp'] ?? 0) as int),
    );
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
