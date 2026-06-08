import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

class NavigationHistoryService {
  NavigationHistoryService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  static const Duration _offlineNavigationTimeout = Duration(seconds: 60);

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
    List<LatLng>? routePolyline,
    List<LatLng>? remainingRoutePolyline,
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
        'routePolyline': _latLngListToMapList(
          routePolyline ?? const <LatLng>[],
        ),
        'remainingRoutePolyline': _latLngListToMapList(
          remainingRoutePolyline ?? routePolyline ?? const <LatLng>[],
        ),
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

  Future<void> updateRemainingRoutePolyline({
    required String? tripId,
    required List<LatLng> remainingRoutePolyline,
  }) async {
    if (tripId == null || tripId.isEmpty) return;

    try {
      await _collection.doc(tripId).update({
        'remainingRoutePolyline': _latLngListToMapList(remainingRoutePolyline),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      debugPrint(
        '[NAV_HISTORY] Failed to update remainingRoutePolyline $tripId: $e',
      );
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> finishTrip({
    required String tripId,
    required int durationSeconds,
    required double totalDistanceMeters,
    double? endLat,
    double? endLng,
  }) async {
    await _endTrip(
      tripId: tripId,
      durationSeconds: durationSeconds,
      totalDistanceMeters: totalDistanceMeters,
      status: 'completed',
      endLat: endLat,
      endLng: endLng,
    );
  }

  Future<void> cancelTrip({
    required String tripId,
    required int durationSeconds,
    required double totalDistanceMeters,
    double? endLat,
    double? endLng,
  }) async {
    await _endTrip(
      tripId: tripId,
      durationSeconds: durationSeconds,
      totalDistanceMeters: totalDistanceMeters,
      status: 'cancelled',
      endLat: endLat,
      endLng: endLng,
    );
  }

  Future<int> cancelOngoingTripsForCurrentUser() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint(
          '[NAV_HISTORY] Cannot cancel ongoing trips: currentUser is null',
        );
        return 0;
      }

      final snapshot = await _collection
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'ongoing')
          .get();

      if (snapshot.docs.isEmpty) return 0;

      final now = Timestamp.now();
      final batch = _firestore.batch();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final startTime = data['startTime'];
        final durationSeconds = startTime is Timestamp
            ? now.toDate().difference(startTime.toDate()).inSeconds
            : 0;

        batch.update(doc.reference, {
          'endTime': now,
          'durationSeconds': durationSeconds < 0 ? 0 : durationSeconds,
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      debugPrint(
        '[NAV_HISTORY] Cancelled ${snapshot.docs.length} stale ongoing trip(s)',
      );
      return snapshot.docs.length;
    } catch (e, st) {
      debugPrint('[NAV_HISTORY] Failed to cancel ongoing trips: $e');
      debugPrintStack(stackTrace: st);
      return 0;
    }
  }

  Future<bool> cancelTripBecauseUserOffline({
    required String tripId,
    required String userId,
  }) async {
    if (tripId.trim().isEmpty || userId.trim().isEmpty) return false;

    try {
      final tripRef = _collection.doc(tripId);
      final liveTrackingRef = _firestore
          .collection('live_tracking')
          .doc(userId);
      final eventRef = tripRef.collection('events').doc();

      return await _firestore.runTransaction((transaction) async {
        final tripSnapshot = await transaction.get(tripRef);
        final liveTrackingSnapshot = await transaction.get(liveTrackingRef);
        if (!tripSnapshot.exists || !liveTrackingSnapshot.exists) return false;

        final tripData = tripSnapshot.data();
        final liveData = liveTrackingSnapshot.data();
        final liveUpdatedAt = liveData?['updatedAt'];
        final isOffline =
            liveUpdatedAt is Timestamp &&
            DateTime.now().difference(liveUpdatedAt.toDate()) >=
                _offlineNavigationTimeout;

        if (tripData == null ||
            tripData['userId'] != userId ||
            tripData['status'] != 'ongoing' ||
            !isOffline) {
          return false;
        }

        final now = Timestamp.now();
        final startTime = tripData['startTime'];
        final durationSeconds = startTime is Timestamp
            ? now.toDate().difference(startTime.toDate()).inSeconds
            : 0;
        final lastLat = liveData?['lat'];
        final lastLng = liveData?['lng'];
        final endLat = lastLat is num ? lastLat.toDouble() : null;
        final endLng = lastLng is num ? lastLng.toDouble() : null;

        final tripUpdate = <String, dynamic>{
          'endTime': now,
          'durationSeconds': durationSeconds < 0 ? 0 : durationSeconds,
          'status': 'cancelled',
          'endReason': 'user_offline',
          'eventCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (endLat != null && endLng != null) {
          tripUpdate['endLat'] = endLat;
          tripUpdate['endLng'] = endLng;
        }

        transaction.update(tripRef, tripUpdate);
        transaction.set(eventRef, {
          'type': 'navigation_cancelled',
          'title': 'Navigasi dibatalkan',
          'description': 'Navigasi dibatalkan karena pengguna offline',
          'lat': endLat,
          'lng': endLng,
          'timestamp': now,
          'createdAt': now,
        });
        transaction.set(liveTrackingRef, {
          'isNavigating': false,
          'currentTripId': null,
          'destinationName': null,
          'connectionStatus': 'offline',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        return true;
      });
    } catch (e, st) {
      debugPrint('[NAV_HISTORY] Failed to cancel offline trip $tripId: $e');
      debugPrintStack(stackTrace: st);
      return false;
    }
  }

  Future<int> cancelOngoingTripsBecauseUserOffline({
    required String userId,
    String? preferredTripId,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return 0;

    try {
      final tripIds = <String>{};
      final normalizedPreferredTripId = preferredTripId?.trim() ?? '';
      if (normalizedPreferredTripId.isNotEmpty) {
        tripIds.add(normalizedPreferredTripId);
      }

      final snapshot = await _collection
          .where('userId', isEqualTo: normalizedUserId)
          .where('status', isEqualTo: 'ongoing')
          .get();
      tripIds.addAll(snapshot.docs.map((doc) => doc.id));

      var cancelledCount = 0;
      for (final tripId in tripIds) {
        final cancelled = await cancelTripBecauseUserOffline(
          tripId: tripId,
          userId: normalizedUserId,
        );
        if (cancelled) cancelledCount += 1;
      }

      return cancelledCount;
    } catch (e, st) {
      debugPrint(
        '[NAV_HISTORY] Failed to find offline ongoing trips for '
        '$normalizedUserId: $e',
      );
      debugPrintStack(stackTrace: st);
      return 0;
    }
  }

  Future<void> addRoutePoint({
    required String tripId,
    required double lat,
    required double lng,
    required double heading,
    required double speed,
    required double accuracy,
    required bool isPredicted,
  }) async {
    if (tripId.isEmpty) {
      debugPrint('[NAV_HISTORY] Cannot add route point: tripId is empty');
      return;
    }

    try {
      final tripRef = _collection.doc(tripId);
      final pointRef = tripRef.collection('route_points').doc();
      final serverTimestamp = FieldValue.serverTimestamp();

      final batch = _firestore.batch();
      batch.set(pointRef, {
        'lat': lat,
        'lng': lng,
        'heading': heading,
        'speed': speed,
        'accuracy': accuracy,
        'isPredicted': isPredicted,
        'gpsStatus': isPredicted ? 'predicted' : 'gps_live',
        'timestamp': serverTimestamp,
        'createdAt': serverTimestamp,
      });
      batch.update(tripRef, {'updatedAt': serverTimestamp});

      await batch.commit();
    } catch (e, st) {
      debugPrint('[NAV_HISTORY] Failed to add route point for $tripId: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> addTripEvent({
    required String? tripId,
    required String type,
    String? title,
    String? description,
    double? lat,
    double? lng,
  }) async {
    if (tripId == null || tripId.isEmpty) {
      debugPrint('[NAV_HISTORY] Cannot add trip event: tripId is empty');
      return;
    }

    try {
      final tripRef = _collection.doc(tripId);
      final eventRef = tripRef.collection('events').doc();
      final serverTimestamp = FieldValue.serverTimestamp();

      final eventData = <String, dynamic>{
        'type': type,
        'title': title ?? getEventTitle(type),
        'description': description ?? getEventDescription(type),
        'lat': lat,
        'lng': lng,
        'timestamp': serverTimestamp,
        'createdAt': serverTimestamp,
      };

      final batch = _firestore.batch();
      batch.set(eventRef, eventData);
      batch.update(tripRef, {
        'eventCount': FieldValue.increment(1),
        'updatedAt': serverTimestamp,
      });

      await batch.commit();
    } catch (e, st) {
      debugPrint('[NAV_HISTORY] Failed to add trip event $type: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  String getEventTitle(String type) {
    switch (type) {
      case 'navigation_started':
        return 'Navigasi dimulai';
      case 'navigation_completed':
        return 'Navigasi selesai';
      case 'navigation_cancelled':
        return 'Navigasi dibatalkan';
      case 'off_route':
        return 'Keluar rute';
      case 'back_to_route':
        return 'Kembali ke rute';
      case 'sos_pressed':
        return 'SOS ditekan';
      case 'arrived':
        return 'Sampai tujuan';
      default:
        return 'Event perjalanan';
    }
  }

  String getEventDescription(String type) {
    switch (type) {
      case 'navigation_started':
        return 'Pengguna mulai melakukan navigasi';
      case 'navigation_completed':
        return 'Pengguna sampai di tujuan';
      case 'navigation_cancelled':
        return 'Pengguna menghentikan navigasi sebelum sampai tujuan';
      case 'off_route':
        return 'Pengguna terdeteksi keluar dari jalur navigasi';
      case 'back_to_route':
        return 'Pengguna kembali ke jalur navigasi';
      case 'sos_pressed':
        return 'Pengguna menekan tombol darurat';
      case 'arrived':
        return 'Pengguna telah tiba di lokasi tujuan';
      default:
        return 'Terjadi event selama perjalanan';
    }
  }

  List<Map<String, double>> _latLngListToMapList(List<LatLng> points) {
    return points
        .map((point) => {'lat': point.latitude, 'lng': point.longitude})
        .toList();
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
    double? endLat,
    double? endLng,
  }) async {
    if (tripId.isEmpty) {
      debugPrint('[NAV_HISTORY] Cannot end trip: tripId is empty');
      return;
    }

    try {
      final updateData = {
        'endTime': FieldValue.serverTimestamp(),
        'durationSeconds': durationSeconds < 0 ? 0 : durationSeconds,
        'totalDistanceMeters': totalDistanceMeters,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (endLat != null) updateData['endLat'] = endLat;
      if (endLng != null) updateData['endLng'] = endLng;

      await _collection.doc(tripId).update(updateData);
    } catch (e, st) {
      debugPrint('[NAV_HISTORY] Failed to end trip $tripId as $status: $e');
      debugPrintStack(stackTrace: st);
    }
  }
}
