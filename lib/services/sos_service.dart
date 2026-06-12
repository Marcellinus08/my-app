import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'realtime_live_tracking_service.dart';

class SosSendResult {
  final String sosId;
  final int successCount;
  final int failedCount;

  const SosSendResult({
    required this.sosId,
    required this.successCount,
    required this.failedCount,
  });

  bool get deliveredToAnyFamily => successCount > 0;
  bool get deliveredToAllFamilies => successCount > 0 && failedCount == 0;

  String get feedbackMessage {
    if (deliveredToAllFamilies) {
      return 'SOS berhasil dikirim ke keluarga.';
    }
    if (deliveredToAnyFamily) {
      return 'SOS terkirim ke sebagian keluarga. Beberapa notifikasi belum berhasil dikirim.';
    }
    return 'SOS tersimpan, tetapi notifikasi keluarga belum terkirim. Coba kembali segera.';
  }

  String get spokenMessage {
    if (deliveredToAllFamilies) {
      return 'Status SOS, berhasil dikirim ke keluarga.';
    }
    if (deliveredToAnyFamily) {
      return 'Status SOS, terkirim ke sebagian keluarga.';
    }
    return 'Status SOS, tersimpan tetapi notifikasi keluarga gagal dikirim. Coba kembali segera.';
  }
}

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

  Future<SosSendResult> sendSosAlert() async {
    try {
      debugPrint('[SosService] sendSosAlert started');

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User belum login');
      }

      final idToken = await currentUser.getIdToken();
      if (idToken == null || idToken.trim().isEmpty) {
        throw Exception('Token autentikasi tidak tersedia');
      }
      debugPrint('[SosService] Firebase ID Token berhasil didapat');

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
      final smartCaneBatteryLevel = _readInt(
        liveTracking?['smartCaneBatteryLevel'],
      );
      final currentTripId = _readString(liveTracking?['currentTripId']) ?? '';
      final familyUids = await getConnectedFamilyUids(uid);

      if (familyUids.isEmpty) {
        throw Exception('Belum ada keluarga terhubung');
      }

      final sosId = await saveSosAlert(
        userId: uid,
        userName: userName,
        familyUids: familyUids,
        lat: lat,
        lng: lng,
        batteryLevel: batteryLevel,
        smartCaneBatteryLevel: smartCaneBatteryLevel,
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
          debugPrint('[SosService] Mengirim SOS dengan authorization header');
          final response = await _httpClient
              .post(
                Uri.parse(workerSendSosUrl),
                headers: {
                  'Authorization': 'Bearer $idToken',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'userId': uid,
                  'familyUid': familyUid,
                  'userName': userName,
                  'lat': lat,
                  'lng': lng,
                  'batteryLevel': batteryLevel,
                  'smartCaneBatteryLevel': smartCaneBatteryLevel,
                  'currentTripId': currentTripId,
                  'sosId': sosId,
                }),
              )
              .timeout(const Duration(seconds: 15));

          debugPrint(
            '[SosService] Worker response status: ${response.statusCode}',
          );
          debugPrint('[SosService] Worker response body: ${response.body}');

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
        debugPrint(
          '[SosService] SOS alert already saved, but push delivery failed '
          'for every family device.',
        );
      }

      return SosSendResult(
        sosId: sosId,
        successCount: successCount,
        failedCount: failedCount,
      );
    } catch (e) {
      debugPrint('[SosService] sendSosAlert failed: $e');
      rethrow;
    }
  }

  Future<List<String>> getConnectedFamilyUids(String tunaNetraUid) async {
    final familyUids = <String>{};

    final tunaDoc = await _firestore
        .collection('users')
        .doc(tunaNetraUid)
        .get();
    final tunaData = tunaDoc.data() ?? {};

    final connectedFamilies = tunaData['connectedFamilies'];
    if (connectedFamilies is List) {
      for (final family in connectedFamilies) {
        if (family is Map) {
          final uid = _readString(family['uid']);
          if (uid != null) {
            familyUids.add(uid);
          }
        }
      }
    }

    final familyMembersSnapshot = await _firestore
        .collection('users')
        .doc(tunaNetraUid)
        .collection('family_members')
        .get();

    for (final doc in familyMembersSnapshot.docs) {
      final uid = _readString(doc.data()['uid']) ?? doc.id;
      if (uid.isNotEmpty) {
        familyUids.add(uid);
      }
    }

    final pairedArraySnapshot = await _firestore
        .collection('users')
        .where('userType', whereIn: ['family', 'UserType.family'])
        .where('pairedUserUids', arrayContains: tunaNetraUid)
        .get();

    for (final doc in pairedArraySnapshot.docs) {
      final uid = _readString(doc.data()['uid']) ?? doc.id;
      if (uid.isNotEmpty) {
        familyUids.add(uid);
      }
    }

    final legacySnapshot = await _firestore
        .collection('users')
        .where('userType', whereIn: ['family', 'UserType.family'])
        .where('pairedUserUid', isEqualTo: tunaNetraUid)
        .get();

    for (final doc in legacySnapshot.docs) {
      final uid = _readString(doc.data()['uid']) ?? doc.id;
      if (uid.isNotEmpty) {
        familyUids.add(uid);
      }
    }

    return familyUids.toList();
  }

  Future<Map<String, dynamic>?> getTunaNetraProfile(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    return snapshot.data();
  }

  Future<Map<String, dynamic>?> getLiveTracking(String uid) async {
    return RealtimeLiveTrackingService.instance.get(uid);
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

  Future<String> saveSosAlert({
    required String userId,
    required String userName,
    required List<String> familyUids,
    required double? lat,
    required double? lng,
    required int? batteryLevel,
    required int? smartCaneBatteryLevel,
    required String currentTripId,
  }) async {
    final docRef = await _firestore.collection('sos_alerts').add({
      'userId': userId,
      'userName': userName,
      'familyUids': familyUids,
      'lat': lat,
      'lng': lng,
      'batteryLevel': batteryLevel,
      'smartCaneBatteryLevel': smartCaneBatteryLevel,
      'currentTripId': currentTripId.isEmpty ? null : currentTripId,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'resolvedAt': null,
    });

    debugPrint('[SosService] SOS alert saved to Firestore: ${docRef.id}');
    return docRef.id;
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
