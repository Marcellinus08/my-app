import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'realtime_live_tracking_service.dart';

class PairingException implements Exception {
  final String message;
  final String code;

  const PairingException(this.message, {this.code = 'pairing-error'});

  @override
  String toString() => message;
}

/// Service untuk mengelola pairing code antara pengguna & keluarga
class PairingService {
  static final PairingService _instance = PairingService._internal();

  factory PairingService() {
    return _instance;
  }

  PairingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RealtimeLiveTrackingService _realtimeTracking =
      RealtimeLiveTrackingService.instance;

  /// Generate unique pairing code
  /// Format: USER12345 (USER + 5 random digits)
  String generatePairingCode() {
    final random = Random();
    final code = random.nextInt(99999).toString().padLeft(5, '0');
    return 'USER$code';
  }

  /// Save pairing code untuk pengguna
  Future<void> savePairingCode(String userId, String pairingCode) async {
    try {
      final normalizedCode = pairingCode.toUpperCase().trim();
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final oldCode = (userDoc.data()?['pairingCode'] as String?)
          ?.toUpperCase()
          .trim();

      await _firestore.collection('users').doc(userId).update({
        'pairingCode': normalizedCode,
      });
      if (oldCode != null && oldCode.isNotEmpty && oldCode != normalizedCode) {
        final oldCodeRef = _firestore.collection('pairing_codes').doc(oldCode);
        final oldCodeDoc = await oldCodeRef.get();
        if (oldCodeDoc.exists) {
          await oldCodeRef.update({
            'status': 'inactive',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await _firestore.collection('pairing_codes').doc(normalizedCode).set({
        'userId': userId,
        'code': normalizedCode,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print('✅ Pairing code saved: $normalizedCode');
    } catch (e) {
      print('❌ Error saving pairing code: $e');
      throw Exception('Gagal menyimpan kode pairing: $e');
    }
  }

  /// Verify pairing code dan dapatkan user info
  Future<Map<String, dynamic>?> verifyPairingCode(String pairingCode) async {
    try {
      final normalizedCode = pairingCode.toUpperCase().trim();
      print('🔍 Verifying pairing code: $normalizedCode');

      final pairingDoc = await _firestore
          .collection('pairing_codes')
          .doc(normalizedCode)
          .get();

      if (pairingDoc.exists) {
        final pairingData = pairingDoc.data() ?? {};
        final userId = pairingData['userId'] as String?;
        final status = pairingData['status'] as String? ?? 'active';

        if (userId == null || userId.isEmpty || status != 'active') {
          throw const PairingException(
            'Kode pairing ini sudah tidak aktif. Minta pengguna TunaNetra membuat kode baru.',
            code: 'inactive-code',
          );
        }

        DocumentSnapshot<Map<String, dynamic>> userDoc;
        try {
          userDoc = await _firestore.collection('users').doc(userId).get();
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied') {
            return {
              'uid': userId,
              'name': pairingData['userName'],
              'email': null,
              'phoneNumber': null,
              'pairingCode': normalizedCode,
            };
          }
          rethrow;
        }

        if (!userDoc.exists) {
          throw const PairingException(
            'Akun TunaNetra untuk kode ini tidak ditemukan. Periksa kembali kode pairing yang dimasukkan.',
            code: 'user-not-found',
          );
        }

        final userData = userDoc.data() ?? {};
        if (userData['userType'] != 'tunanetra') {
          throw const PairingException(
            'Kode pairing tidak valid untuk akun TunaNetra.',
            code: 'invalid-user-type',
          );
        }

        return {
          'uid': userDoc.id,
          'name': userData['name'],
          'email': userData['email'],
          'phoneNumber': userData['phoneNumber'],
          'pairingCode': normalizedCode,
        };
      }

      final query = await _firestore
          .collection('users')
          .where('pairingCode', isEqualTo: normalizedCode)
          .where('userType', isEqualTo: 'tunanetra')
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        throw const PairingException(
          'Kode pairing tidak ditemukan. Pastikan kode sudah benar dan masih aktif.',
          code: 'code-not-found',
        );
      }

      final userData = query.docs.first.data();
      print('✅ Pairing code verified for user: ${userData['name']}');

      return {
        'uid': query.docs.first.id,
        'name': userData['name'],
        'email': userData['email'],
        'phoneNumber': userData['phoneNumber'],
        'pairingCode': normalizedCode,
      };
    } on PairingException {
      rethrow;
    } catch (e) {
      print('❌ Error verifying pairing code: $e');
      throw const PairingException(
        'Tidak dapat memeriksa kode pairing saat ini. Periksa koneksi lalu coba lagi.',
        code: 'verification-failed',
      );
    }
  }

  Future<String> createPairingRequest({
    required String familyUid,
    required String pairingCode,
  }) async {
    try {
      final targetUser = await verifyPairingCode(pairingCode);
      if (targetUser == null) {
        throw const PairingException(
          'Kode pairing tidak ditemukan. Pastikan kode sudah benar dan masih aktif.',
          code: 'code-not-found',
        );
      }

      final tunaNetraUid = targetUser['uid'] as String;
      if (familyUid == tunaNetraUid) {
        throw const PairingException(
          'Akun keluarga tidak dapat dihubungkan ke akun yang sama.',
          code: 'same-account',
        );
      }

      final isConnected = await isConnectionActive(
        familyUid: familyUid,
        tunaNetraUid: tunaNetraUid,
      );
      if (isConnected) {
        throw const PairingException(
          'Pengguna ini sudah terhubung dengan keluarga Anda.',
          code: 'already-connected',
        );
      }

      final pending = await _firestore
          .collection('pairing_requests')
          .where('familyUid', isEqualTo: familyUid)
          .where('tunaNetraUid', isEqualTo: tunaNetraUid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (pending.docs.isNotEmpty) {
        throw const PairingException(
          'Permintaan koneksi untuk pengguna ini sudah terkirim. Tunggu konfirmasi dari akun TunaNetra.',
          code: 'request-pending',
        );
      }

      final familyDoc = await _firestore
          .collection('users')
          .doc(familyUid)
          .get();
      final familyData = familyDoc.data() ?? {};

      final requestRef = await _firestore.collection('pairing_requests').add({
        'familyUid': familyUid,
        'familyName': familyData['name'] ?? '',
        'familyEmail': familyData['email'] ?? '',
        'familyPhone': familyData['phoneNumber'] ?? '',
        'tunaNetraUid': tunaNetraUid,
        'tunaNetraName': targetUser['name'] ?? '',
        'pairingCode': pairingCode.toUpperCase().trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return requestRef.id;
    } on PairingException {
      rethrow;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const PairingException(
          'Permintaan belum bisa dikirim karena izin database belum aktif. Deploy Firestore rules lalu coba lagi.',
          code: 'permission-denied',
        );
      }
      throw const PairingException(
        'Permintaan belum bisa dikirim. Periksa koneksi lalu coba lagi.',
        code: 'request-failed',
      );
    } catch (e) {
      throw const PairingException(
        'Permintaan belum bisa dikirim. Silakan coba lagi beberapa saat.',
        code: 'request-failed',
      );
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingRequestsForTunaNetra(
    String tunaNetraUid,
  ) {
    return _firestore
        .collection('pairing_requests')
        .where('tunaNetraUid', isEqualTo: tunaNetraUid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  Future<bool> isConnectionActive({
    required String familyUid,
    required String tunaNetraUid,
  }) async {
    try {
      final familyDoc = await _firestore
          .collection('users')
          .doc(familyUid)
          .get();
      final familyData = familyDoc.data() ?? {};
      final pairedUserUids = <String>[];

      if (familyData['pairedUserUids'] is List) {
        pairedUserUids.addAll(
          List<String>.from(familyData['pairedUserUids'] as List),
        );
      }

      if (familyData['pairedUserUid'] is String &&
          !pairedUserUids.contains(familyData['pairedUserUid'])) {
        pairedUserUids.add(familyData['pairedUserUid'] as String);
      }

      if (pairedUserUids.contains(tunaNetraUid)) {
        return true;
      }

      final tunaDoc = await _firestore
          .collection('users')
          .doc(tunaNetraUid)
          .get();
      final data = tunaDoc.data() ?? {};
      final connectedFamilies = data['connectedFamilies'];

      if (connectedFamilies is List) {
        final hasFamily = connectedFamilies.any((family) {
          if (family is Map) {
            return family['uid'] == familyUid;
          }
          return false;
        });
        if (hasFamily) {
          await _removeConnectedFamilyReference(
            familyUid: familyUid,
            tunaNetraUid: tunaNetraUid,
          );
        }
      }

      final memberDoc = await _firestore
          .collection('users')
          .doc(tunaNetraUid)
          .collection('family_members')
          .doc(familyUid)
          .get();

      return memberDoc.exists;
    } catch (e) {
      print('❌ Error checking active connection: $e');
      return false;
    }
  }

  Future<void> respondToPairingRequest({
    required String requestId,
    required bool accepted,
  }) async {
    try {
      final requestRef = _firestore
          .collection('pairing_requests')
          .doc(requestId);
      final requestDoc = await requestRef.get();
      if (!requestDoc.exists) {
        throw Exception('Permintaan pairing tidak ditemukan');
      }

      final data = requestDoc.data() ?? {};
      if (data['status'] != 'pending') {
        throw Exception('Permintaan pairing sudah diproses');
      }

      if (!accepted) {
        await requestRef.update({
          'status': 'rejected',
          'respondedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final familyUid = data['familyUid'] as String? ?? '';
      final tunaNetraUid = data['tunaNetraUid'] as String? ?? '';
      final pairingCode = data['pairingCode'] as String? ?? '';

      if (familyUid.isEmpty || tunaNetraUid.isEmpty) {
        throw Exception('Data permintaan pairing tidak lengkap');
      }

      await linkFamilyToUser(
        familyUid,
        tunaNetraUid,
        pairingCode,
        fallbackName: data['familyName'] as String?,
        fallbackEmail: data['familyEmail'] as String?,
        fallbackPhone: data['familyPhone'] as String?,
      );
      await addPairedUser(familyUid, tunaNetraUid);
      await _realtimeTracking.grantFamilyAccess(
        userId: tunaNetraUid,
        familyUid: familyUid,
      );

      await requestRef.update({
        'status': 'accepted',
        'respondedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Link family ke tunanetra user (setelah verifikasi)
  /// [fallbackName], [fallbackEmail], [fallbackPhone] = data fallback jika Firestore belum updated
  Future<void> linkFamilyToUser(
    String familyUid,
    String tunaNetraUid,
    String pairingCode, {
    String? fallbackName,
    String? fallbackEmail,
    String? fallbackPhone,
  }) async {
    try {
      print('🔗 [PAIRING] Starting linkFamilyToUser');
      print('   Family UID: $familyUid');
      print('   TunaNetra UID: $tunaNetraUid');
      print('   Fallback data provided: ${fallbackName != null}');

      // Keep latest linked timestamp on the family profile.
      await _firestore.collection('users').doc(familyUid).set({
        'linkedAt': DateTime.now(),
      }, SetOptions(merge: true));

      // Get family data dengan retry logic
      DocumentSnapshot<Map<String, dynamic>>? familyDoc;
      Map<String, dynamic>? familyData;

      // Try to get from Firestore dengan retry jika kosong
      for (int retry = 0; retry < 3; retry++) {
        familyDoc = await _firestore.collection('users').doc(familyUid).get();
        familyData = familyDoc.data();

        print('📦 Family data retrieval attempt ${retry + 1}:');
        print('   Email: ${familyData?['email']}');
        print('   Name: ${familyData?['name']}');
        print('   Phone: ${familyData?['phoneNumber']}');

        // Jika nama sudah ada, stop retry
        if ((familyData?['name'] as String?)?.isNotEmpty ?? false) {
          print('   ✅ Data found, proceeding');
          break;
        }

        // Jika masih kosong dan ada fallback, gunakan fallback
        final isEmpty = (familyData?['name'] as String?)?.isEmpty ?? true;
        if (retry < 2 && isEmpty) {
          print('   ⏳ Data kosong, waiting before retry...');
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // Gunakan data dari Firestore, atau fallback jika kosong
      final email = (familyData?['email'] as String?)?.isNotEmpty ?? false
          ? familyData!['email'] as String
          : (fallbackEmail ?? '');

      final name = (familyData?['name'] as String?)?.isNotEmpty ?? false
          ? familyData!['name'] as String
          : (fallbackName ?? '');

      final phone = (familyData?['phoneNumber'] as String?)?.isNotEmpty ?? false
          ? familyData!['phoneNumber'] as String
          : (fallbackPhone ?? '');

      print('📋 Final data to save:');
      print(
        '   Name: $name (from ${(familyData?['name'] as String?)?.isNotEmpty ?? false ? "Firestore" : "fallback"})',
      );
      print('   Email: $email');
      print('   Phone: $phone');

      if (name.isNotEmpty || email.isNotEmpty) {
        await _removeConnectedFamilyReference(
          familyUid: familyUid,
          tunaNetraUid: tunaNetraUid,
        );

        final familyInfo = {
          'uid': familyUid,
          'email': email,
          'name': name,
          'phone': phone,
          'connectedAt': DateTime.now(),
        };

        print('💾 Saving to connectedFamilies array');

        // Add to connectedFamilies array in tunanetra user's document
        await _firestore
            .collection('users')
            .doc(tunaNetraUid)
            .update({
              'connectedFamilies': FieldValue.arrayUnion([familyInfo]),
            })
            .catchError((e) {
              print('⚠️  Update failed, trying merge set: $e');
              // If document doesn't exist or array doesn't exist, create it
              if (e.toString().contains('FAILED_PRECONDITION') ||
                  e.toString().contains('not-found')) {
                return _firestore.collection('users').doc(tunaNetraUid).set({
                  'connectedFamilies': [familyInfo],
                }, SetOptions(merge: true));
              }
              throw e;
            });

        print('💾 Saving to family_members subcollection');

        // Update tunanetra document dengan family uid (subcollection)
        await _firestore
            .collection('users')
            .doc(tunaNetraUid)
            .collection('family_members')
            .doc(familyUid)
            .set({
              'uid': familyUid,
              'email': email,
              'name': name,
              'phone': phone,
              'linkedAt': DateTime.now(),
            });

        print('✅ Data saved to subcollection');
      } else {
        print('⚠️  No valid name or email to save');
      }

      print('✅ Family linked to user successfully');
    } catch (e) {
      print('❌ Error linking family: $e');
      throw Exception('Gagal menghubungkan keluarga: $e');
    }
  }

  /// Check apakah pairing code sudah digunakan
  Future<bool> isPairingCodeUsed(String pairingCode) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('pairingCode', isEqualTo: pairingCode)
          .limit(1)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      print('❌ Error checking pairing code: $e');
      return false;
    }
  }

  /// Get pairing code info (for debugging)
  Future<Map<String, dynamic>?> getPairingCodeInfo(String pairingCode) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('pairingCode', isEqualTo: pairingCode)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return null;
      }

      return query.docs.first.data();
    } catch (e) {
      print('❌ Error getting pairing code info: $e');
      return null;
    }
  }

  /// Add user to family's paired users list (untuk mendukung multiple users)
  Future<void> addPairedUser(String familyUid, String tunaNetraUid) async {
    try {
      print('📌 Adding paired user $tunaNetraUid to family $familyUid');

      await _firestore.collection('users').doc(familyUid).update({
        'pairedUserUids': FieldValue.arrayUnion([tunaNetraUid]),
      });

      print('✅ Paired user added successfully');
    } catch (e) {
      print('❌ Error adding paired user: $e');
      throw Exception('Gagal menambah pengguna: $e');
    }
  }

  /// Get all paired users for a family
  Future<List<String>> getPairedUsers(String familyUid) async {
    try {
      final doc = await _firestore.collection('users').doc(familyUid).get();

      if (!doc.exists) {
        return [];
      }

      final data = doc.data() as Map<String, dynamic>;

      // Support both pairedUserUid (single) and pairedUserUids (array)
      final pairedUserUids = <String>[];

      if (data['pairedUserUids'] is List) {
        pairedUserUids.addAll(
          List<String>.from(data['pairedUserUids'] as List),
        );
      }

      if (data['pairedUserUid'] is String &&
          !pairedUserUids.contains(data['pairedUserUid'])) {
        pairedUserUids.add(data['pairedUserUid'] as String);
      }

      return pairedUserUids;
    } catch (e) {
      print('❌ Error getting paired users: $e');
      return [];
    }
  }

  /// Remove user from family's paired users list
  Future<void> removePairedUser(String familyUid, String tunaNetraUid) async {
    try {
      print('🗑️ Removing paired user $tunaNetraUid from family $familyUid');

      await _firestore.collection('users').doc(familyUid).update({
        'pairedUserUid': FieldValue.delete(),
        'pairedUserUids': FieldValue.arrayRemove([tunaNetraUid]),
      });

      // Also remove from family_members subcollection in tunanetra user's document
      await _firestore
          .collection('users')
          .doc(tunaNetraUid)
          .collection('family_members')
          .doc(familyUid)
          .delete();

      await _removeConnectedFamilyReference(
        familyUid: familyUid,
        tunaNetraUid: tunaNetraUid,
      );
      await _realtimeTracking.revokeFamilyAccess(
        userId: tunaNetraUid,
        familyUid: familyUid,
      );

      print('✅ Paired user removed successfully');
    } catch (e) {
      print('❌ Error removing paired user: $e');
      throw Exception('Gagal menghapus pengguna: $e');
    }
  }

  Future<void> _removeConnectedFamilyReference({
    required String familyUid,
    required String tunaNetraUid,
  }) async {
    final tunaRef = _firestore.collection('users').doc(tunaNetraUid);
    final tunaDoc = await tunaRef.get();
    final tunaData = tunaDoc.data() ?? {};
    final connectedFamilies = tunaData['connectedFamilies'];

    if (connectedFamilies is! List) {
      return;
    }

    final cleanedFamilies = connectedFamilies
        .where((family) => family is! Map || family['uid'] != familyUid)
        .toList();

    if (cleanedFamilies.length == connectedFamilies.length) {
      return;
    }

    await tunaRef.update({'connectedFamilies': cleanedFamilies});
  }
}
