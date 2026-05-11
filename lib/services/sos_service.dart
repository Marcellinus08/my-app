import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class SosService {
  static const String workerSendSosUrl =
      'https://teman-arah-sos-worker.teman-arah.workers.dev/send-sos';

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final http.Client _httpClient;

  SosService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    http.Client? httpClient,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _httpClient = httpClient ?? http.Client();

  Future<void> sendSosAlert() async {
    try {
      debugPrint('[SosService] sendSosAlert started');

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User belum login');
      }

      final uid = currentUser.uid;
      final profile = await getTunaNetraProfile(uid);
      if (profile == null) {
        throw Exception('Profil pengguna tidak ditemukan');
      }

      final userType = profile['userType'] as String?;
      if (!_isTunaNetraUserType(userType)) {
        throw Exception('SOS hanya dapat dikirim oleh pengguna tuna netra');
      }

      final userName = _readString(profile['name']) ?? 'Pengguna';
      final liveTracking = await getLiveTracking(uid);

      double? lat = _readDouble(liveTracking?['lat']);
      double? lng = _readDouble(liveTracking?['lng']);

      if (lat == null || lng == null) {
        final fallbackLocation = await getCurrentLocationFallback();
        lat ??= fallbackLocation?.latitude;
        lng ??= fallbackLocation?.longitude;
      }

      final batteryLevel = _readInt(liveTracking?['batteryLevel']);
      final currentTripId = _readString(liveTracking?['currentTripId']) ?? '';
      final familyUids = await getConnectedFamilyUids(uid);

      if (familyUids.isEmpty) {
        throw Exception('Belum ada keluarga terhubung');
      }

      await saveSosAlert(
        userId: uid,
        userName: userName,
        familyUids: familyUids,
        lat: lat,
        lng: lng,
        batteryLevel: batteryLevel,
        currentTripId: currentTripId,
      );

      if (currentTripId.isNotEmpty) {
        await saveSosTripEvent(
          currentTripId: currentTripId,
          lat: lat,
          lng: lng,
        );
      }

      var successCount = 0;
      var failedCount = 0;

      for (final familyUid in familyUids) {
        try {
          final response = await _httpClient
              .post(
                Uri.parse(workerSendSosUrl),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'userId': uid,
                  'familyUid': familyUid,
                  'userName': userName,
                  'lat': lat,
                  'lng': lng,
                  'batteryLevel': batteryLevel,
                  'currentTripId': currentTripId,
                }),
              )
              .timeout(const Duration(seconds: 15));

          final responseBody = _decodeJsonObject(response.body);
          final success =
              response.statusCode == 200 && responseBody?['success'] == true;

          if (success) {
            successCount += 1;
            debugPrint('[SosService] SOS sent to familyUid: $familyUid');
          } else {
            failedCount += 1;
            debugPrint(
              '[SosService] SOS failed for familyUid=$familyUid '
              'status=${response.statusCode} body=${response.body}',
            );
          }
        } catch (e) {
          failedCount += 1;
          debugPrint('[SosService] SOS error for familyUid=$familyUid: $e');
        }
      }

      debugPrint(
        '[SosService] SOS result successCount=$successCount '
        'failedCount=$failedCount',
      );

      if (successCount == 0) {
        throw Exception('SOS gagal dikirim ke semua keluarga');
      }
    } catch (e) {
      debugPrint('[SosService] sendSosAlert failed: $e');
      rethrow;
    }
  }

  Future<List<String>> getConnectedFamilyUids(String tunaNetraUid) async {
    final snapshot = await _firestore
        .collection('users')
        .where('userType', whereIn: ['family', 'UserType.family'])
        .where('pairedUserUid', isEqualTo: tunaNetraUid)
        .get();

    final familyUids = <String>[];
    for (final doc in snapshot.docs) {
      final uid = _readString(doc.data()['uid']) ?? doc.id;
      if (uid.isNotEmpty) {
        familyUids.add(uid);
      }
    }

    return familyUids.toSet().toList();
  }

  Future<Map<String, dynamic>?> getTunaNetraProfile(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    return snapshot.data();
  }

  Future<Map<String, dynamic>?> getLiveTracking(String uid) async {
    final snapshot = await _firestore
        .collection('live_tracking')
        .doc(uid)
        .get();
    return snapshot.data();
  }

  Future<LatLng?> getCurrentLocationFallback() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[SosService] Location service disabled');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('[SosService] Location permission denied: $permission');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('[SosService] Location fallback failed: $e');
      return null;
    }
  }

  Future<void> saveSosAlert({
    required String userId,
    required String userName,
    required List<String> familyUids,
    required double? lat,
    required double? lng,
    required int? batteryLevel,
    required String currentTripId,
  }) async {
    await _firestore.collection('sos_alerts').add({
      'userId': userId,
      'userName': userName,
      'familyUids': familyUids,
      'lat': lat,
      'lng': lng,
      'batteryLevel': batteryLevel,
      'currentTripId': currentTripId.isEmpty ? null : currentTripId,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'resolvedAt': null,
    });

    debugPrint('[SosService] SOS alert saved to Firestore');
  }

  Future<void> saveSosTripEvent({
    required String currentTripId,
    required double? lat,
    required double? lng,
  }) async {
    await _firestore
        .collection('navigation_history')
        .doc(currentTripId)
        .collection('events')
        .add({
          'type': 'sos_pressed',
          'title': 'SOS ditekan',
          'description': 'Pengguna menekan tombol darurat',
          'lat': lat,
          'lng': lng,
          'timestamp': FieldValue.serverTimestamp(),
        });

    debugPrint('[SosService] SOS trip event saved: $currentTripId');
  }

  bool _isTunaNetraUserType(String? userType) {
    return userType == 'tunanetra' || userType == 'UserType.tunanetra';
  }

  String? _readString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic>? _decodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
