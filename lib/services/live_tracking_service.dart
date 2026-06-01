import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'smart_cane_ble_service.dart';

class LiveTrackingService {
  static final LiveTrackingService _instance = LiveTrackingService._internal();
  factory LiveTrackingService() => _instance;
  LiveTrackingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Battery _battery = Battery();

  StreamSubscription<Position>? _homeSubscription;
  StreamSubscription<Position>? _navigationSubscription;
  Timer? _homeRefreshTimer;
  Timer? _navigationThrottleTimer;

  DateTime? _lastNavigationUpdateTime;
  Map<String, dynamic>? _pendingNavigationData;
  Position? _lastHomePosition;
  Position? _lastNavigationPosition;
  bool _isStartingHomeTracking = false;
  bool _isStartingNavigationTracking = false;
  int _homeStartToken = 0;

  static const Duration _navigationThrottleDuration = Duration(seconds: 2);
  static const Duration _homeRefreshInterval = Duration(seconds: 10);

  Future<void> startHomeLocationTracking() async {
    if (_isStartingHomeTracking ||
        _homeSubscription != null ||
        _homeRefreshTimer != null) {
      return;
    }
    _isStartingHomeTracking = true;
    final startToken = ++_homeStartToken;

    _homeRefreshTimer = Timer.periodic(_homeRefreshInterval, (_) {
      unawaited(_refreshHomeTracking(startStreamIfNeeded: true));
    });

    try {
      await _refreshHomeTracking(
        startStreamIfNeeded: true,
        startToken: startToken,
      );
    } catch (_) {
      await updateInactiveTracking();
      return;
    } finally {
      _isStartingHomeTracking = false;
    }
  }

  void _startHomePositionStream() {
    if (_homeSubscription != null) return;

    _homeSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen(
          (position) {
            _lastHomePosition = position;
            unawaited(updateHomeLocationOnly(position: position));
          },
          onError: (_) {
            unawaited(updateInactiveTracking());
          },
        );
  }

  Future<void> _refreshHomeTracking({
    required bool startStreamIfNeeded,
    int? startToken,
  }) async {
    if (startToken != null && startToken != _homeStartToken) return;
    if (_navigationSubscription != null || _isStartingNavigationTracking)
      return;

    final canTrackNow = await _ensureLocationReady();
    if (startToken != null && startToken != _homeStartToken) return;
    if (!canTrackNow) {
      await _homeSubscription?.cancel();
      _homeSubscription = null;
      await updateInactiveTracking();
      return;
    }

    if (startStreamIfNeeded) {
      _startHomePositionStream();
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (startToken != null && startToken != _homeStartToken) return;
      _lastHomePosition = position;
      await updateHomeLocationOnly(position: position);
    } catch (_) {
      await _homeSubscription?.cancel();
      _homeSubscription = null;
      await updateInactiveTracking();
    }
  }

  Future<void> stopHomeLocationTracking() async {
    _homeStartToken++;
    await _homeSubscription?.cancel();
    _homeSubscription = null;
    _homeRefreshTimer?.cancel();
    _homeRefreshTimer = null;
  }

  Future<void> startNavigationTracking({
    required String? destinationName,
    required void Function(Position position) onPosition,
    void Function(Object error)? onError,
  }) async {
    if (_isStartingNavigationTracking || _navigationSubscription != null) {
      return;
    }
    _isStartingNavigationTracking = true;

    await stopHomeLocationTracking();

    try {
      final canTrack = await _ensureLocationReady();
      if (!canTrack) {
        await updateInactiveTracking();
        return;
      }

      _navigationSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 1,
            ),
          ).listen(
            (position) {
              _lastNavigationPosition = position;
              onPosition(position);
              unawaited(
                updateLiveTracking(
                  position: position,
                  isNavigating: true,
                  isPredicted: false,
                  gpsStatus: 'gps_live',
                  connectionStatus: 'online',
                  destinationName: destinationName,
                  speed: position.speed.isFinite ? position.speed : null,
                  throttle: true,
                ),
              );
            },
            onError: (error) {
              unawaited(updateInactiveTracking());
              onError?.call(error);
            },
          );
    } finally {
      _isStartingNavigationTracking = false;
    }
  }

  Future<void> stopNavigationTracking({bool resumeHomeTracking = true}) async {
    await _navigationSubscription?.cancel();
    _navigationSubscription = null;
    _navigationThrottleTimer?.cancel();
    _navigationThrottleTimer = null;
    _pendingNavigationData = null;
    _lastNavigationUpdateTime = null;

    final lastPosition = _lastNavigationPosition ?? _lastHomePosition;
    if (lastPosition != null) {
      await updateHomeLocationOnly(position: lastPosition);
    } else {
      await updateInactiveTracking();
    }

    if (resumeHomeTracking) {
      await startHomeLocationTracking();
    }
  }

  Future<void> updateLiveTracking({
    required Position position,
    required bool isNavigating,
    required bool isPredicted,
    required String gpsStatus,
    required String connectionStatus,
    String? destinationName,
    String? currentTripId,
    double? heading,
    double? speed,
    double? accuracy,
    bool throttle = false,
  }) async {
    final data = {
      'lat': position.latitude,
      'lng': position.longitude,
      'heading': heading ?? (position.heading >= 0 ? position.heading : 0.0),
      'speed': speed ?? (position.speed.isFinite ? position.speed : 0.0),
      'accuracy': accuracy ?? position.accuracy,
      'isNavigating': isNavigating,
      if (currentTripId != null) 'currentTripId': currentTripId,
      'isPredicted': isPredicted,
      'gpsStatus': gpsStatus,
      'connectionStatus': connectionStatus,
      'destinationName': destinationName,
    };

    if (!throttle) {
      await _performUpdate(data);
      return;
    }

    final now = DateTime.now();
    final lastUpdate = _lastNavigationUpdateTime;
    if (lastUpdate == null ||
        now.difference(lastUpdate) >= _navigationThrottleDuration) {
      await _performUpdate(data);
      _lastNavigationUpdateTime = now;
      return;
    }

    _pendingNavigationData = data;
    if (_navigationThrottleTimer?.isActive == true) return;

    final wait = _navigationThrottleDuration - now.difference(lastUpdate);
    _navigationThrottleTimer = Timer(wait, () async {
      final pendingData = _pendingNavigationData;
      if (pendingData == null) return;

      await _performUpdate(pendingData);
      _lastNavigationUpdateTime = DateTime.now();
      _pendingNavigationData = null;
    });
  }

  Future<void> updateHomeLocationOnly({required Position position}) async {
    final user = _auth.currentUser;
    if (user == null) {
      print('[LIVE_TRACKING] Home update skipped: currentUser is null');
      return;
    }

    try {
      final batteryLevel = await _battery.batteryLevel;
      final smartCaneBatteryLevel =
          SmartCaneBleService.instance.latestBatteryData?.percentage;

      await _firestore.collection('live_tracking').doc(user.uid).set({
        'userId': user.uid,
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': null,
        'destinationName': null,
        'heading': null,
        'speed': null,
        'isNavigating': false,
        'currentTripId': null,
        'isPredicted': false,
        'gpsStatus': 'gps_live',
        'connectionStatus': 'online',
        'batteryLevel': batteryLevel,
        'smartCaneBatteryLevel': smartCaneBatteryLevel,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print(
        '[LIVE_TRACKING] Home location updated: ${position.latitude}, ${position.longitude}, battery: $batteryLevel%, caneBattery: ${smartCaneBatteryLevel ?? '-'}%',
      );
    } catch (e) {
      print('[LIVE_TRACKING] Home update failed: $e');
    }
  }

  Future<void> updateInactiveTracking() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('live_tracking').doc(user.uid).set({
      'userId': user.uid,
      'batteryLevel': null,
      'smartCaneBatteryLevel': null,
      'lat': null,
      'lng': null,
      'accuracy': null,
      'destinationName': null,
      'heading': null,
      'speed': null,
      'isNavigating': false,
      'currentTripId': null,
      'isPredicted': false,
      'gpsStatus': null,
      'connectionStatus': 'offline',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _performUpdate(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final batteryLevel = await _battery.batteryLevel;
    final smartCaneBatteryLevel =
        SmartCaneBleService.instance.latestBatteryData?.percentage;

    await _firestore.collection('live_tracking').doc(user.uid).set({
      'userId': user.uid,
      ...data,
      'batteryLevel': batteryLevel,
      'smartCaneBatteryLevel': smartCaneBatteryLevel,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateNavigationTripState({
    required String? currentTripId,
    required bool isNavigating,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('live_tracking').doc(user.uid).set({
        'userId': user.uid,
        'isNavigating': isNavigating,
        'currentTripId': isNavigating ? currentTripId : null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('[LIVE_TRACKING] Failed to update navigation trip state: $e');
    }
  }

  Future<bool> _ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> dispose() async {
    await stopHomeLocationTracking();
    await stopNavigationTracking(resumeHomeTracking: false);
  }
}
