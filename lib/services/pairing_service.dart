import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service untuk mengelola pairing code antara pengguna & keluarga
class PairingService {
  static final PairingService _instance = PairingService._internal();

  factory PairingService() {
    return _instance;
  }

  PairingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
      await _firestore.collection('users').doc(userId).update({
        'pairingCode': pairingCode,
      });
      print('✅ Pairing code saved: $pairingCode');
    } catch (e) {
      print('❌ Error saving pairing code: $e');
      throw Exception('Gagal menyimpan kode pairing: $e');
    }
  }

  /// Verify pairing code dan dapatkan user info
  Future<Map<String, dynamic>?> verifyPairingCode(String pairingCode) async {
    try {
      print('🔍 Verifying pairing code: $pairingCode');

      final query = await _firestore
          .collection('users')
          .where('pairingCode', isEqualTo: pairingCode)
          .where('userType', isEqualTo: 'tunanetra')
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        throw Exception('Kode pairing tidak ditemukan atau tidak valid');
      }

      final userData = query.docs.first.data();
      print('✅ Pairing code verified for user: ${userData['name']}');

      return {
        'uid': query.docs.first.id,
        'name': userData['name'],
        'email': userData['email'],
        'pairingCode': userData['pairingCode'],
      };
    } catch (e) {
      print('❌ Error verifying pairing code: $e');
      throw Exception(e.toString());
    }
  }

  /// Link family ke tunanetra user (setelah verifikasi)
  Future<void> linkFamilyToUser(
    String familyUid,
    String tunaNetraUid,
    String pairingCode,
  ) async {
    try {
      // Ensure family document has pairing link fields (merge to avoid not-found error).
      await _firestore.collection('users').doc(familyUid).set({
        'pairedUserUid': tunaNetraUid,
        'linkedAt': DateTime.now(),
      }, SetOptions(merge: true));

      // Update tunanetra document dengan family uid (opsional, bisa di subcollection)
      await _firestore
          .collection('users')
          .doc(tunaNetraUid)
          .collection('family_members')
          .doc(familyUid)
          .set({
            'uid': familyUid,
            'name': '', // Will be updated when family data available
            'linkedAt': DateTime.now(),
          });

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
      
      await _firestore
          .collection('users')
          .doc(familyUid)
          .update({
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
      final doc = await _firestore
          .collection('users')
          .doc(familyUid)
          .get();

      if (!doc.exists) {
        return [];
      }

      final data = doc.data() as Map<String, dynamic>;
      
      // Support both pairedUserUid (single) and pairedUserUids (array)
      final pairedUserUids = <String>[];
      
      if (data['pairedUserUids'] is List) {
        pairedUserUids.addAll(
          List<String>.from(data['pairedUserUids'] as List)
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
      
      await _firestore
          .collection('users')
          .doc(familyUid)
          .update({
            'pairedUserUids': FieldValue.arrayRemove([tunaNetraUid]),
          });
      
      // Also remove from family_members subcollection in tunanetra user's document
      await _firestore
          .collection('users')
          .doc(tunaNetraUid)
          .collection('family_members')
          .doc(familyUid)
          .delete();
      
      print('✅ Paired user removed successfully');
    } catch (e) {
      print('❌ Error removing paired user: $e');
      throw Exception('Gagal menghapus pengguna: $e');
    }
  }
}

