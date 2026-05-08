import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class NavigationHistoryService {
  NavigationHistoryService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('navigation_history');

  Future<String?> startTrip({
    String originName = 'Lokasi awal',
    required String destinationName,
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    required double totalDistanceMeters,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('[NAV_HISTORY] Cannot start trip: currentUser is null');
        return null;
      }

      final now = Timestamp.now();
      final docRef = await _collection.add({
        'userId': user.uid,
        'startTime': now,
        'endTime': null,
        'durationSeconds': null,
        'originName': originName.isNotEmpty ? originName : 'Lokasi awal',
        'destinationName': destinationName,
        'originLat': originLat,
        'originLng': originLng,
        'destinationLat': destinationLat,
        'destinationLng': destinationLng,
        'totalDistanceMeters': totalDistanceMeters,
        'status': 'ongoing',
        'eventCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return docRef.id;
    } catch (e, st) {
      debugPrint('[NAV_HISTORY] Failed to start trip: $e');
      debugPrintStack(stackTrace: st);
      return null;
    }
  }

  Future<void> finishTrip({
    required String tripId,
    required int durationSeconds,
    required double totalDistanceMeters,
  }) async {
    await _endTrip(
      tripId: tripId,
      durationSeconds: durationSeconds,
      totalDistanceMeters: totalDistanceMeters,
      status: 'completed',
    );
  }

  Future<void> cancelTrip({
    required String tripId,
    required int durationSeconds,
    required double totalDistanceMeters,
  }) async {
    await _endTrip(
      tripId: tripId,
      durationSeconds: durationSeconds,
      totalDistanceMeters: totalDistanceMeters,
      status: 'cancelled',
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getUserTripHistoryStream(
    String userId,
  ) {
    return _collection
        .where('userId', isEqualTo: userId)
        .orderBy('startTime', descending: true)
        .snapshots();
  }

  Future<void> _endTrip({
    required String tripId,
    required int durationSeconds,
    required double totalDistanceMeters,
    required String status,
  }) async {
    if (tripId.isEmpty) {
      debugPrint('[NAV_HISTORY] Cannot end trip: tripId is empty');
      return;
    }

    try {
      await _collection.doc(tripId).update({
        'endTime': FieldValue.serverTimestamp(),
        'durationSeconds': durationSeconds < 0 ? 0 : durationSeconds,
        'totalDistanceMeters': totalDistanceMeters,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      debugPrint('[NAV_HISTORY] Failed to end trip $tripId as $status: $e');
      debugPrintStack(stackTrace: st);
    }
  }
}
