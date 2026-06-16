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
      return 'SOS berhasil terkirim ke sebagian keluarga.';
    }
    return 'SOS tersimpan, tetapi notifikasi keluarga belum terkirim. Coba kembali segera.';
  }

  String get spokenMessage {
    if (deliveredToAllFamilies) {
      return 'SOS berhasil terkirim ke keluarga.';
    }
    if (deliveredToAnyFamily) {
      return 'SOS berhasil terkirim ke keluarga.';
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

      debugPrint(
        '[SosService] Mengirim SOS ke ${familyUids.length} keluarga',
      );

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

      // Kirim notifikasi ke semua keluarga secara paralel
      final deliveryResults = await Future.wait(
        familyUids.map(
          (familyUid) => _sendNotificationToFamily(
            idToken: idToken,
            familyUid: familyUid,
            userId: uid,
            userName: userName,
            lat: lat,
            lng: lng,
            batteryLevel: batteryLevel,
            smartCaneBatteryLevel: smartCaneBatteryLevel,
            currentTripId: currentTripId,
            sosId: sosId,
          ),
        ),
      );

      var successCount = 0;
      var failedCount = 0;
      for (final result in deliveryResults) {
        successCount += result[0];
        failedCount += result[1];
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

  // Mengirim notifikasi push ke satu keluarga. Mengembalikan [sentCount, failedCount].
  Future<List<int>> _sendNotificationToFamily({
    required String idToken,
    required String familyUid,
    required String userId,
    required String userName,
    required double? lat,
    required double? lng,
    required int? batteryLevel,
    required int? smartCaneBatteryLevel,
    required String currentTripId,
    required String sosId,
  }) async {
    debugPrint('[SosService] _sendNotificationToFamily → familyUid=$familyUid');
    try {
      final response = await _httpClient
          .post(
            Uri.parse(workerSendSosUrl),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'userId': userId,
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

      final responseBody = _decodeJsonObject(response.body);
      final success =
          response.statusCode == 200 && responseBody?['success'] == true;

      // TODO(debug): hapus setelah masalah partial delivery teridentifikasi
      debugPrint(
        '[SosService] familyUid=$familyUid '
        'status=${response.statusCode} '
        'success=$success '
        'body=${response.body}',
      );

      if (success) {
        return [1, 0];
      } else {
        return [0, 1];
      }
    } catch (e) {
      // TODO(debug): hapus setelah masalah partial delivery teridentifikasi
      debugPrint('[SosService] familyUid=$familyUid exception: $e');
      return [0, 1];
    }
  }

  /// Mengumpulkan semua family UID yang terhubung dengan tunaNetra user.
  /// Membaca dari beberapa sumber secara resilient — satu sumber gagal tidak
  /// memblokir sumber lainnya.
  Future<List<String>> getConnectedFamilyUids(String tunaNetraUid) async {
    final familyUids = <String>{};

    // Sumber 1: connectedFamilies array di dokumen tunaNetra
    try {
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
            if (uid != null) familyUids.add(uid);
          }
        }
      }
    } catch (e) {
      debugPrint('[SosService] getConnectedFamilyUids source1 error: $e');
    }

    // Sumber 2: family_members subcollection di dokumen tunaNetra
    try {
      final familyMembersSnapshot = await _firestore
          .collection('users')
          .doc(tunaNetraUid)
          .collection('family_members')
          .get();
      for (final doc in familyMembersSnapshot.docs) {
        final uid = _readString(doc.data()['uid']) ?? doc.id;
        if (uid.isNotEmpty) familyUids.add(uid);
      }
    } catch (e) {
      debugPrint('[SosService] getConnectedFamilyUids source2 error: $e');
    }

    // Sumber 3 & 4: reverse lookup pada family users — dijalankan paralel
    await Future.wait([
      // Sumber 3: pairedUserUids array di dokumen keluarga
      _firestore
          .collection('users')
          .where('userType', whereIn: ['family', 'UserType.family'])
          .where('pairedUserUids', arrayContains: tunaNetraUid)
          .get()
          .then((snapshot) {
            for (final doc in snapshot.docs) {
              final uid = _readString(doc.data()['uid']) ?? doc.id;
              if (uid.isNotEmpty) familyUids.add(uid);
            }
          })
          .catchError((Object e) {
            debugPrint(
              '[SosService] getConnectedFamilyUids source3 error: $e',
            );
          }),

      // Sumber 4: pairedUserUid (legacy, single) di dokumen keluarga
      _firestore
          .collection('users')
          .where('userType', whereIn: ['family', 'UserType.family'])
          .where('pairedUserUid', isEqualTo: tunaNetraUid)
          .get()
          .then((snapshot) {
            for (final doc in snapshot.docs) {
              final uid = _readString(doc.data()['uid']) ?? doc.id;
              if (uid.isNotEmpty) familyUids.add(uid);
            }
          })
          .catchError((Object e) {
            debugPrint(
              '[SosService] getConnectedFamilyUids source4 error: $e',
            );
          }),
    ]);

    debugPrint(
      '[SosService] Connected family UIDs ditemukan: ${familyUids.length}',
    );
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
