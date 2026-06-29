import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class RealtimeLiveTrackingService {
  RealtimeLiveTrackingService._();

  // Response time measurement hook — set oleh GpsRtTimer, null di production
  static void Function()? onRtdbWriteDone;

  static const String databaseUrl =
      'https://smarthcane-11b47-default-rtdb.asia-southeast1.firebasedatabase.app';

  static final RealtimeLiveTrackingService instance =
      RealtimeLiveTrackingService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: databaseUrl,
  );
  StreamSubscription<DatabaseEvent>? _connectionSubscription;
  String? _connectionListenerUid;

  DatabaseReference _trackingRef(String userId) =>
      _database.ref('live_tracking/$userId');

  Stream<Map<String, dynamic>?> watch(String userId) {
    return _trackingRef(userId).onValue.map((event) {
      final data = _asStringMap(event.snapshot.value);
      final clientSentAtMs = data?['clientSentAtMs'];
      if (clientSentAtMs is num) {
        final delayMs =
            DateTime.now().millisecondsSinceEpoch - clientSentAtMs.round();
        if (delayMs >= 0 && delayMs <= 2000) {
          // ignore: avoid_print
          print('[DELAY_TRACKING] $delayMs ms');
        }
      }
      return data;
    });
  }

  Future<Map<String, dynamic>?> get(String userId) async {
    final snapshot = await _trackingRef(userId).get();
    return _asStringMap(snapshot.value);
  }

  Future<void> setOwnTracking(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final ref = _trackingRef(user.uid);
    await ref.update({
      'userId': user.uid,
      ...data,
      'updatedAt': ServerValue.timestamp,
      'clientSentAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    onRtdbWriteDone?.call();
    _ensureDisconnectHandler(user.uid);
  }

  Future<void> updateOwnTripState({
    required String? currentTripId,
    required bool isNavigating,
  }) async {
    await setOwnTracking({
      'isNavigating': isNavigating,
      'currentTripId': isNavigating ? currentTripId : null,
    });
  }

  Future<void> grantFamilyAccess({
    required String userId,
    required String familyUid,
  }) async {
    await _database.ref('live_tracking_access/$userId/$familyUid').set(true);
  }

  Future<void> revokeFamilyAccess({
    required String userId,
    required String familyUid,
  }) async {
    await _database.ref('live_tracking_access/$userId/$familyUid').remove();
  }

  Future<void> syncFamilyAccess({
    required String userId,
    required Iterable<String> familyUids,
  }) async {
    final access = <String, bool>{
      for (final uid in familyUids)
        if (uid.trim().isNotEmpty) uid.trim(): true,
    };
    await _database.ref('live_tracking_access/$userId').set(access);
  }

  Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, entry) => MapEntry(key.toString(), entry));
  }

  void _ensureDisconnectHandler(String userId) {
    if (_connectionListenerUid == userId && _connectionSubscription != null) {
      return;
    }

    unawaited(_connectionSubscription?.cancel());
    _connectionListenerUid = userId;
    _connectionSubscription = _database.ref('.info/connected').onValue.listen((
      event,
    ) {
      if (event.snapshot.value != true || _auth.currentUser?.uid != userId) {
        return;
      }

      unawaited(
        _trackingRef(userId).onDisconnect().update({
          'connectionStatus': 'offline',
          'isNavigating': false,
          'currentTripId': null,
          'destinationName': null,
          'gpsStatus': null,
          'updatedAt': ServerValue.timestamp,
        }),
      );
    });
  }
}
