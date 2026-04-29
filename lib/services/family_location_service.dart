import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/family_location_model.dart';
import 'analytics_service.dart';

class FamilyLocationService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<DatabaseEvent>? _sub;

  /// Listen to realtime location updates for a given user UID in Realtime DB
  Stream<FamilyLocation> listenToRealtime(
    String uid, {
    bool storeHistory = true,
  }) async* {
    final ref = _db.ref('family_locations/$uid');
    final controller = StreamController<FamilyLocation>();

    _sub = ref.onValue.listen((event) {
      final snapshot = event.snapshot;
      if (snapshot.value != null) {
        try {
          final map = snapshot.value as Map<dynamic, dynamic>;
          final loc = FamilyLocation.fromMap(uid, map);
          // emit
          controller.add(loc);
          if (storeHistory) {
            // store to history (fire-and-forget)
            _firestore.collection('location_history').add({
              'uid': uid,
              'latitude': loc.latitude,
              'longitude': loc.longitude,
              'speed': loc.speed,
              'battery': loc.battery,
              'gpsEnabled': loc.gpsEnabled,
              'internetAvailable': loc.internetAvailable,
              'navigationStatus': loc.navigationStatus,
              'destination': loc.destination,
              'timestamp': Timestamp.fromDate(loc.timestamp),
            });
          }
        } catch (e, st) {
          // ignore parse errors
        }
      }
    });

    controller.onCancel = () {
      _sub?.cancel();
    };

    yield* controller.stream;
  }

  void dispose() {
    _sub?.cancel();
  }

  /// Fetch recent history from Firestore
  Future<List<FamilyLocation>> fetchHistory(String uid, {int limit = 50}) async {
    final qs = await _firestore
        .collection('location_history')
        .where('uid', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();

    return qs.docs.map((d) => FamilyLocation.fromFirestore(d)).toList();
  }

  /// Simple anomaly detection: returns true if stationary for too long or battery low
  bool detectAnomaly(List<FamilyLocation> recent) {
    if (recent.isEmpty) return false;
    final latest = recent.first;
    // battery anomaly
    if (latest.battery <= 10) return true;
    // stationary: if last N points all have speed < 0.5 m/s for > 10 minutes
    final stationaryPoints = recent.where((r) => r.speed < 0.5).toList();
    if (stationaryPoints.length >= 3) {
      final span = latest.timestamp.difference(stationaryPoints.last.timestamp).inMinutes;
      if (span >= 10) return true;
    }
    return false;
  }

  /// Store an alert in Firestore so family members can view it
  Future<void> storeAlert(String familyId, String uid, String message) async {
    await _firestore.collection('alerts').add({
      'familyId': familyId,
      'uid': uid,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
    });
    AnalyticsService().logFamilyAlert(familyId: familyId, uid: uid, message: message);
  }
}
