import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'realtime_live_tracking_service.dart';

/// Service untuk mengelola akun keluarga yang terhubung ke pengguna tunanetra
class ConnectedFamilyService {
  static final ConnectedFamilyService _instance =
      ConnectedFamilyService._internal();

  factory ConnectedFamilyService() {
    return _instance;
  }

  ConnectedFamilyService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final RealtimeLiveTrackingService _realtimeTracking =
      RealtimeLiveTrackingService.instance;

  /// Dapatkan daftar keluarga yang terhubung ke pengguna tunanetra
  Future<List<Map<String, dynamic>>> getConnectedFamilies() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User tidak terautentikasi');
      }

      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists) {
        throw Exception('Data pengguna tidak ditemukan');
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final connectedFamilies =
          List<Map<String, dynamic>>.from(userData['connectedFamilies'] ?? []);

      print('✅ Retrieved ${connectedFamilies.length} connected families');
      return connectedFamilies;
    } catch (e) {
      print('❌ Error getting connected families: $e');
      throw Exception('Gagal mengambil daftar keluarga: $e');
    }
  }

  /// Tambah keluarga ke daftar terhubung
  Future<void> addConnectedFamily({
    required String familyUid,
    required String familyEmail,
    required String familyName,
    required String familyPhone,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User tidak terautentikasi');
      }

      final newFamily = {
        'uid': familyUid,
        'email': familyEmail,
        'name': familyName,
        'phone': familyPhone,
        'status': 'Aktif',
        'connectedAt': Timestamp.now(),
      };

      await _firestore.collection('users').doc(userId).update({
        'connectedFamilies': FieldValue.arrayUnion([newFamily]),
      });

      print('✅ Family added to connected list');
    } catch (e) {
      print('❌ Error adding connected family: $e');
      throw Exception('Gagal menambahkan keluarga: $e');
    }
  }

  /// Hapus keluarga dari daftar terhubung
  Future<void> removeConnectedFamily(String familyUid) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User tidak terautentikasi');
      }

      // Ambil data keluarga terlebih dahulu
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() as Map<String, dynamic>;
      final connectedFamilies =
          List<Map<String, dynamic>>.from(userData['connectedFamilies'] ?? []);

      // Cari dan hapus keluarga berdasarkan UID
      connectedFamilies.removeWhere((family) => family['uid'] == familyUid);

      // Update dokumen
      await _firestore.collection('users').doc(userId).update({
        'connectedFamilies': connectedFamilies,
      });
      await _realtimeTracking.revokeFamilyAccess(
        userId: userId,
        familyUid: familyUid,
      );

      print('✅ Family removed from connected list');
    } catch (e) {
      print('❌ Error removing connected family: $e');
      throw Exception('Gagal menghapus keluarga: $e');
    }
  }

  /// Update informasi keluarga yang terhubung
  Future<void> updateConnectedFamily({
    required String familyUid,
    required String familyEmail,
    required String familyName,
    required String familyPhone,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User tidak terautentikasi');
      }

      // Ambil data keluarga terlebih dahulu
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() as Map<String, dynamic>;
      final connectedFamilies =
          List<Map<String, dynamic>>.from(userData['connectedFamilies'] ?? []);

      // Cari dan update keluarga
      for (int i = 0; i < connectedFamilies.length; i++) {
        if (connectedFamilies[i]['uid'] == familyUid) {
          connectedFamilies[i] = {
            'uid': familyUid,
            'email': familyEmail,
            'name': familyName,
            'phone': familyPhone,
            'connectedAt': connectedFamilies[i]['connectedAt'] ?? Timestamp.now(),
          };
          break;
        }
      }

      // Update dokumen
      await _firestore.collection('users').doc(userId).update({
        'connectedFamilies': connectedFamilies,
      });

      print('✅ Family information updated');
    } catch (e) {
      print('❌ Error updating connected family: $e');
      throw Exception('Gagal memperbarui data keluarga: $e');
    }
  }

  /// Dapatkan detail keluarga berdasarkan UID
  Future<Map<String, dynamic>?> getConnectedFamilyDetail(
      String familyUid) async {
    try {
      final families = await getConnectedFamilies();
      return families.firstWhere(
        (family) => family['uid'] == familyUid,
        orElse: () => {},
      );
    } catch (e) {
      print('❌ Error getting family detail: $e');
      return null;
    }
  }

  /// Cek apakah keluarga sudah terhubung
  Future<bool> isFamilyConnected(String familyUid) async {
    try {
      final families = await getConnectedFamilies();
      return families.any((family) => family['uid'] == familyUid);
    } catch (e) {
      print('❌ Error checking family connection: $e');
      return false;
    }
  }

  /// Hitung jumlah keluarga yang terhubung
  Future<int> getConnectedFamilyCount() async {
    try {
      final families = await getConnectedFamilies();
      return families.length;
    } catch (e) {
      print('❌ Error getting family count: $e');
      return 0;
    }
  }

  /// Stream untuk mendengarkan perubahan connected families
  Stream<List<Map<String, dynamic>>> getConnectedFamiliesStream() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return Stream.error('User tidak terautentikasi');
    }

    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) {
        return [];
      }

      final userData = doc.data() as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(userData['connectedFamilies'] ?? []);
    });
  }
}
