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

      // Ensure family document has pairing link fields (merge to avoid not-found error).
      await _firestore.collection('users').doc(familyUid).set({
        'pairedUserUid': tunaNetraUid,
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
      print('   Name: $name (from ${(familyData?['name'] as String?)?.isNotEmpty ?? false ? "Firestore" : "fallback"})');
      print('   Email: $email');
      print('   Phone: $phone');
      
      if (name.isNotEmpty || email.isNotEmpty) {
        final familyInfo = {
          'uid': familyUid,
          'email': email,
          'name': name,
          'phone': phone,
          'status': 'Aktif',
          'connectedAt': DateTime.now(),
        };

        print('💾 Saving to connectedFamilies array');

        // Add to connectedFamilies array in tunanetra user's document
        await _firestore
            .collection('users')
            .doc(tunaNetraUid)
            .update({
          'connectedFamilies': FieldValue.arrayUnion([familyInfo]),
        }).catchError((e) {
          print('⚠️  Update failed, trying merge set: $e');
          // If document doesn't exist or array doesn't exist, create it
          if (e.toString().contains('FAILED_PRECONDITION') || 
              e.toString().contains('not-found')) {
            return _firestore
                .collection('users')
                .doc(tunaNetraUid)
                .set({
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

