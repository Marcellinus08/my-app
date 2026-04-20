import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../models/user_models.dart';
import '../utils/constants.dart';

/// Service untuk mengelola user data di Firestore
class UserService {
  static final UserService _instance = UserService._internal();

  factory UserService() {
    return _instance;
  }

  UserService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ========== SAVE TUNANETRA USER ==========
  /// Simpan data TunaNetra user ke Firestore
  Future<void> saveTunaNetraUser({
    required String uid,
    required String email,
    required String name,
    required String phoneNumber,
    required String pairingCode,
    required List<FamilyContact> familyContacts,
  }) async {
    try {
      print('\n╔════════════════════════════════════════════════════════╗');
      print('║ [USER SERVICE] saveTunaNetraUser()                    ║');
      print('╚════════════════════════════════════════════════════════╝');
      
      print('\n[USER] SUBSTEP 1: Creating user object');
      final user = TunaNetraUser(
        uid: uid,
        email: email,
        name: name,
        phoneNumber: phoneNumber,
        pairingCode: pairingCode,
        familyContacts: familyContacts,
        createdAt: DateTime.now(),
      );
      print('   ✅ TunaNetraUser object created');

      print('\n[USER] SUBSTEP 2: Converting user to map (toMap)');
      final userMap = user.toMap();
      print('   ✅ User converted to Firestore-compatible map');
      print('   Data keys: ${userMap.keys.join(', ')}');

      print('\n[USER] SUBSTEP 3: Preparing Firestore write operation');
      print('   Collection: users');
      print('   Document ID: $uid');
      print('   Email: $email');
      print('   Name: $name');
      print('   Phone: $phoneNumber');
      print('   Pairing Code: $pairingCode');
      print('   Family Contacts: ${familyContacts.length}');
      
      print('\n[USER] SUBSTEP 4: Writing user document to Firestore');
      print('   ⏱️  Starting write operation...');
      final uploadStart = DateTime.now();
      
      await _firestore
          .collection('users')
          .doc(uid)
          .set(userMap)
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              final duration = DateTime.now().difference(uploadStart).inSeconds;
              print('   ⏱️  TIMEOUT after ${duration}s!');
              throw Exception('💥 Firestore write timeout (60s) - backend tidak merespons');
            },
          );
      
      final uploadTime = DateTime.now().difference(uploadStart).inSeconds;
      print('   ✅ Write completed in ${uploadTime}s');

      print('\n[USER] SUBSTEP 5: Verifying document was created');
      final verifyDoc = await _firestore.collection('users').doc(uid).get();
      if (!verifyDoc.exists) {
        throw Exception('Document write returned success but document not found');
      }
      print('   ✅ Document verified in Firestore');

      print('\n✅ [USER SERVICE] saveTunaNetraUser() COMPLETE');
      print('   Document path: users/$uid\n');
      
    } on FirebaseException catch (fe) {
      print('\n❌ [USER SERVICE] Firebase Exception');
      print('   Code: ${fe.code}');
      print('   Message: ${fe.message}');
      print('   Possible causes:');
      print('   - Firestore database not created');
      print('   - Security rules blocking write');
      print('   - Network connectivity issue\n');
      throw Exception('Firestore error: ${fe.message ?? fe.code}');
      
    } on TimeoutException catch (te) {
      print('\n❌ [USER SERVICE] Timeout Exception');
      print('   Message: ${te.message}');
      print('   Possible causes:');
      print('   - Firestore backend not responding');
      print('   - Network too slow or unstable\n');
      throw Exception('Write timeout - check network connection');
      
    } catch (e) {
      print('\n❌ [USER SERVICE] Unexpected Error');
      print('   Type: ${e.runtimeType}');
      print('   Message: $e\n');
      rethrow;
    }
  }

  // ========== SAVE FAMILY USER ==========
  /// Simpan data Family user ke Firestore
  Future<void> saveFamilyUser({
    required String uid,
    required String email,
    required String name,
    required String phoneNumber,
    required String pairingCode,
    required String pairedUserUid,
  }) async {
    try {
      final user = FamilyUser(
        uid: uid,
        email: email,
        name: name,
        phoneNumber: phoneNumber,
        pairingCode: pairingCode,
        pairedUserUid: pairedUserUid,
        createdAt: DateTime.now(),
      );

      print('📦 Preparing Family user data for Firestore...');
      print('   uid: $uid');
      print('   email: $email');
      print('   name: $name');
      print('   pairedUserUid: $pairedUserUid');
      
      print('📤 Uploading to Firestore (collection: users, doc: $uid)...');
      final uploadStart = DateTime.now();
      
      await _firestore
          .collection('users')
          .doc(uid)
          .set(user.toMap())
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              final duration = DateTime.now().difference(uploadStart).inSeconds;
              print('⏱️ Firestore upload timed out after ${duration}s');
              throw Exception('Firestore save timeout (60s) - connection issue');
            },
          );
      
      final uploadTime = DateTime.now().difference(uploadStart).inSeconds;
      print('✅ Family user saved in ${uploadTime}s: $uid');
      print('   Document path: users/$uid');
    } catch (e) {
      print('❌ Error saving Family user: $e');
      print('   Error type: ${e.runtimeType}');
      print('   Possible causes:');
      print('   - Firestore database not created in Firebase Console');
      print('   - Network connectivity issue');
      print('   - Security rules blocking write operation');
      print('   - User document already exists');
      throw Exception('Gagal menyimpan data keluarga ke Firestore: ${e.toString()}');
    }
  }

  // ========== GET USER DATA ==========
  /// Ambil data user dari Firestore
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      
      if (doc.exists) {
        print('✅ User data retrieved: $uid');
        return doc.data();
      } else {
        print('⚠️ User not found: $uid');
        return null;
      }
    } catch (e) {
      print('❌ Error retrieving user data: $e');
      throw Exception('Gagal mengambil data pengguna: ${e.toString()}');
    }
  }

  // ========== GET TUNANETRA USER ==========
  /// Ambil TunaNetra user object dari Firestore
  Future<TunaNetraUser?> getTunaNetraUser(String uid) async {
    try {
      final data = await getUserData(uid);
      
      if (data != null && data['userType'] == 'tunanetra') {
        return TunaNetraUser.fromMap(data);
      }
      return null;
    } catch (e) {
      print('❌ Error retrieving TunaNetra user: $e');
      return null;
    }
  }

  // ========== GET FAMILY USER ==========
  /// Ambil Family user object dari Firestore
  Future<FamilyUser?> getFamilyUser(String uid) async {
    try {
      final data = await getUserData(uid);
      
      if (data != null && data['userType'] == 'family') {
        return FamilyUser.fromMap(data);
      }
      return null;
    } catch (e) {
      print('❌ Error retrieving Family user: $e');
      return null;
    }
  }

  // ========== UPDATE TUNANETRA USER ==========
  /// Update data TunaNetra user
  Future<void> updateTunaNetraUser(
    String uid, {
    String? name,
    String? phoneNumber,
    List<FamilyContact>? familyContacts,
    bool? isEmailVerified,
    String? pairingCode,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      
      if (name != null) updateData['name'] = name;
      if (phoneNumber != null) updateData['phoneNumber'] = phoneNumber;
      if (familyContacts != null) {
        updateData['familyContacts'] = 
            familyContacts.map((c) => c.toMap()).toList();
      }
      if (isEmailVerified != null) updateData['isEmailVerified'] = isEmailVerified;
      if (pairingCode != null) updateData['pairingCode'] = pairingCode;

      if (updateData.isNotEmpty) {
        await _firestore.collection('users').doc(uid).update(updateData);
        print('✅ TunaNetra user updated: $uid');
      }
    } catch (e) {
      print('❌ Error updating TunaNetra user: $e');
      throw Exception('Gagal update data pengguna: ${e.toString()}');
    }
  }

  // ========== UPDATE FAMILY USER ==========
  /// Update data Family user
  Future<void> updateFamilyUser(
    String uid, {
    String? name,
    String? phoneNumber,
    bool? isEmailVerified,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      
      if (name != null) updateData['name'] = name;
      if (phoneNumber != null) updateData['phoneNumber'] = phoneNumber;
      if (isEmailVerified != null) updateData['isEmailVerified'] = isEmailVerified;

      if (updateData.isNotEmpty) {
        await _firestore.collection('users').doc(uid).update(updateData);
        print('✅ Family user updated: $uid');
      }
    } catch (e) {
      print('❌ Error updating Family user: $e');
      throw Exception('Gagal update data keluarga: ${e.toString()}');
    }
  }

  // ========== VERIFY EMAIL ==========
  /// Update email verification status
  Future<void> verifyEmail(String uid) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .update({'isEmailVerified': true});
      
      print('✅ Email verified: $uid');
    } catch (e) {
      print('❌ Error verifying email: $e');
      throw Exception('Gagal verifikasi email: ${e.toString()}');
    }
  }

  // ========== DELETE USER ==========
  /// Hapus user data dari Firestore (untuk cleanup)
  Future<void> deleteUser(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).delete();
      print('✅ User deleted: $uid');
    } catch (e) {
      print('❌ Error deleting user: $e');
      throw Exception('Gagal menghapus user: ${e.toString()}');
    }
  }

  // ========== GET PAIRED FAMILY FOR TUNANETRA ==========
  /// Ambil semua family user yang linked ke TunaNetra user tertentu
  Future<List<FamilyUser>> getPairedFamilies(String tunaNetraUid) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('pairedUserUid', isEqualTo: tunaNetraUid)
          .where('userType', isEqualTo: 'family')
          .get();

      final familyUsers = snapshot.docs
          .map((doc) => FamilyUser.fromMap(doc.data()))
          .toList();

      print('✅ Found ${familyUsers.length} paired families for: $tunaNetraUid');
      return familyUsers;
    } catch (e) {
      print('❌ Error getting paired families: $e');
      throw Exception('Gagal mengambil data keluarga: ${e.toString()}');
    }
  }

  // ========== GET USER TYPE ==========
  /// Dapatkan tipe user (tunanetra atau family)
  Future<UserType?> getUserType(String uid) async {
    try {
      final data = await getUserData(uid);
      
      if (data != null) {
        final userType = data['userType'];
        if (userType == 'tunanetra') {
          return UserType.tunanetra;
        } else if (userType == 'family') {
          return UserType.family;
        }
      }
      return null;
    } catch (e) {
      print('❌ Error getting user type: $e');
      return null;
    }
  }

  // ========== CHECK USER EXISTS ==========
  /// Cek apakah user sudah ada di Firestore
  Future<bool> userExists(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.exists;
    } catch (e) {
      print('❌ Error checking user existence: $e');
      return false;
    }
  }

  // ========== DIAGNOSTIC / TEST ==========
  /// Test Firestore connection with simple write
  Future<bool> testFirestoreConnection() async {
    try {
      print('🔍 Testing Firestore connection...');
      final testStart = DateTime.now();
      
      // Try a simple write
      final testDocId = 'test_${DateTime.now().millisecondsSinceEpoch}';
      print('   Writing test document: $testDocId');
      
      await _firestore
          .collection('_test')
          .doc(testDocId)
          .set({'timestamp': DateTime.now().toIso8601String()})
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Write timeout'),
          );
      
      final writeTime = DateTime.now().difference(testStart).inSeconds;
      print('✅ Firestore write test successful in ${writeTime}s');
      
      // Try a read
      final readStart = DateTime.now();
      final snap = await _firestore.collection('_test').doc(testDocId).get();
      final readTime = DateTime.now().difference(readStart).inMilliseconds;
      print('✅ Firestore read test successful in ${readTime}ms');
      
      return true;
    } catch (e) {
      print('❌ Firestore connection test FAILED: $e');
      print('   This indicates Firestore is not accessible');
      print('   Check: 1) Firestore database exists');
      print('         2) Security rules allow writes');
      print('         3) Network connection is stable');
      return false;
    }
  }
}

