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
      final user = TunaNetraUser(
        uid: uid,
        email: email,
        name: name,
        phoneNumber: phoneNumber,
        pairingCode: pairingCode,
        familyContacts: familyContacts,
        createdAt: DateTime.now(),
      );

      final userMap = user.toMap();
      // Jika tidak ada family contacts, jangan sertakan field tersebut di Firestore
      if (familyContacts.isEmpty) {
        userMap.remove('familyContacts');
      }

      final uploadStart = DateTime.now();

      await _firestore
          .collection('users')
          .doc(uid)
          .set(userMap)
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              final duration = DateTime.now().difference(uploadStart).inSeconds;
              throw Exception(
                'Firestore write timeout (${duration}s) - backend tidak merespons',
              );
            },
          );

      final verifyDoc = await _firestore.collection('users').doc(uid).get();
      if (!verifyDoc.exists) {
        throw Exception(
          'Document write returned success but document not found',
        );
      }
    } on FirebaseException catch (fe) {
      throw Exception('Firestore error: ${fe.message ?? fe.code}');
    } on TimeoutException catch (_) {
      throw Exception('Write timeout - check network connection');
    } catch (e) {
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
    bool isEmailVerified = false,
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
        isEmailVerified: isEmailVerified,
      );

      final uploadStart = DateTime.now();

      await _firestore
          .collection('users')
          .doc(uid)
          .set(user.toMap())
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              final duration = DateTime.now().difference(uploadStart).inSeconds;
              throw Exception(
                'Firestore save timeout (${duration}s) - connection issue',
              );
            },
          );
    } catch (e) {
      throw Exception(
        'Gagal menyimpan data keluarga ke Firestore: ${e.toString()}',
      );
    }
  }

  // ========== GET USER DATA ==========
  /// Ambil data user dari Firestore
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();

      if (doc.exists) {
        return doc.data();
      } else {
        return null;
      }
    } catch (e) {
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
        updateData['familyContacts'] = familyContacts
            .map((c) => c.toMap())
            .toList();
      }
      if (isEmailVerified != null)
        updateData['isEmailVerified'] = isEmailVerified;
      if (pairingCode != null) updateData['pairingCode'] = pairingCode;

      if (updateData.isNotEmpty) {
        await _firestore.collection('users').doc(uid).update(updateData);
      }
    } catch (e) {
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
      if (isEmailVerified != null)
        updateData['isEmailVerified'] = isEmailVerified;

      if (updateData.isNotEmpty) {
        await _firestore.collection('users').doc(uid).update(updateData);
        await _syncFamilyInfoToConnectedUsers(
          familyUid: uid,
          familyName: name,
          familyPhone: phoneNumber,
        );
      }
    } catch (e) {
      throw Exception('Gagal update data keluarga: ${e.toString()}');
    }
  }

  Future<void> _syncFamilyInfoToConnectedUsers({
    required String familyUid,
    String? familyName,
    String? familyPhone,
  }) async {
    if (familyName == null && familyPhone == null) return;

    final connectedUsers = await getTunaNetraUsersByFamilyId(familyUid);
    if (connectedUsers.isEmpty) {
      return;
    }

    final batch = _firestore.batch();
    var updatesCount = 0;

    for (final user in connectedUsers) {
      final userUid = user['uid']?.toString().trim();
      if (userUid == null || userUid.isEmpty) continue;

      final userRef = _firestore.collection('users').doc(userUid);
      final userDoc = await userRef.get();
      if (!userDoc.exists) continue;

      final userData = userDoc.data() as Map<String, dynamic>?;
      final connectedFamiliesRaw = userData?['connectedFamilies'];
      if (connectedFamiliesRaw is! List) continue;

      var changed = false;
      final updatedFamilies = connectedFamiliesRaw.map((family) {
        if (family is! Map) return family;

        final familyMap = Map<String, dynamic>.from(family as Map);
        final isTargetFamily = familyMap['uid']?.toString().trim() == familyUid;
        if (!isTargetFamily) return familyMap;

        if (familyName != null) {
          familyMap['name'] = familyName;
          changed = true;
        }

        if (familyPhone != null) {
          familyMap['phone'] = familyPhone;
          changed = true;
        }

        return familyMap;
      }).toList();

      if (changed) {
        batch.update(userRef, {'connectedFamilies': updatedFamilies});
        updatesCount++;
      }
    }

    if (updatesCount > 0) {
      await batch.commit();
    }
  }

  // ========== VERIFY EMAIL ==========
  /// Update email verification status
  Future<void> verifyEmail(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'isEmailVerified': true,
      });
    } catch (e) {
      throw Exception('Gagal verifikasi email: ${e.toString()}');
    }
  }

  // ========== DELETE USER ==========
  /// Hapus user data dari Firestore (untuk cleanup)
  Future<void> deleteUser(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).delete();
    } catch (e) {
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

      return snapshot.docs
          .map((doc) => FamilyUser.fromMap(doc.data()))
          .toList();
    } catch (e) {
      throw Exception('Gagal mengambil data keluarga: ${e.toString()}');
    }
  }

  // ========== GET TUNANETRA USERS BY PAIRING CODE ==========
  /// Ambil semua TunaNetra users yang memiliki pairing code tertentu
  /// Digunakan untuk mengambil pengguna yang akan dimonitor oleh family berdasarkan pairing code
  Future<List<Map<String, dynamic>>> getTunaNetraUsersByPairingCode(
    String familyPairingCode,
  ) async {
    try {
      // Normalize pairing code (uppercase untuk konsistensi)
      final normalizedCode = familyPairingCode.toUpperCase().trim();

      // Ambil semua tuna netra users dengan pairing code yang cocok
      final snapshot = await _firestore
          .collection('users')
          .where('userType', isEqualTo: 'tunanetra')
          .where('pairingCode', isEqualTo: normalizedCode)
          .get();

      final users = snapshot.docs.map((doc) {
        final data = doc.data();

        // Parse createdAt
        DateTime createdAt = DateTime.now();
        if (data['createdAt'] != null) {
          if (data['createdAt'] is String) {
            createdAt = DateTime.parse(data['createdAt'] as String);
          } else if (data['createdAt'] is DateTime) {
            createdAt = data['createdAt'] as DateTime;
          }
        }

        return {
          'uid': doc.id,
          'name': data['name'] ?? 'Unknown',
          'email': data['email'] ?? '',
          'phoneNumber': data['phoneNumber'] ?? '',
          'pairingCode': data['pairingCode'] ?? '',
          'createdAt': createdAt,
          'isEmailVerified': data['isEmailVerified'] ?? false,
          'familyContacts': data['familyContacts'] ?? [],
        };
      }).toList();

      return users;
    } catch (e) {
      throw Exception('Gagal mengambil data pengguna: ${e.toString()}');
    }
  }

  // ========== GET TUNANETRA USERS BY FAMILY ID (CORRECT WAY) ==========
  /// Ambil semua TunaNetra users yang terhubung dengan family user
  /// Menggunakan pairedUserUid atau pairedUserUids dari family user
  Future<List<Map<String, dynamic>>> getTunaNetraUsersByFamilyId(
    String familyId,
  ) async {
    try {
      // Ambil family user document
      final familyDoc = await _firestore
          .collection('users')
          .doc(familyId)
          .get();

      if (!familyDoc.exists) {
        return [];
      }

      final familyData = familyDoc.data() as Map<String, dynamic>;

      // Ambil pairedUserUid atau pairedUserUids
      final pairedUserUids = <String>[];
      final seenPairedUserUids = <String>{};

      // Support single pairedUserUid
      if (familyData['pairedUserUid'] is String) {
        final uid = familyData['pairedUserUid'] as String;
        if (uid.isNotEmpty && seenPairedUserUids.add(uid)) {
          pairedUserUids.add(uid);
        }
      }

      // Support array pairedUserUids
      if (familyData['pairedUserUids'] is List) {
        final uids = List<String>.from(familyData['pairedUserUids'] as List);
        for (final uid in uids) {
          if (uid.isNotEmpty && seenPairedUserUids.add(uid)) {
            pairedUserUids.add(uid);
          }
        }
      }

      if (pairedUserUids.isEmpty) {
        return [];
      }

      // Ambil semua TunaNetra users berdasarkan UIDs
      final users = <Map<String, dynamic>>[];

      for (int i = 0; i < pairedUserUids.length; i++) {
        final uid = pairedUserUids[i];

        final userDoc = await _firestore.collection('users').doc(uid).get();

        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;

          // Verify it's tunanetra user
          if (userData['userType'] == 'tunanetra') {
            final connectedFamiliesRaw = userData['connectedFamilies'];
            final isStillConnected =
                connectedFamiliesRaw is List &&
                connectedFamiliesRaw.any((family) {
                  if (family is Map) {
                    return family['uid'] == familyId;
                  }
                  return false;
                });

            if (!isStillConnected) {
              continue;
            }

            // Parse createdAt
            DateTime createdAt = DateTime.now();
            if (userData['createdAt'] != null) {
              if (userData['createdAt'] is String) {
                createdAt = DateTime.parse(userData['createdAt'] as String);
              } else if (userData['createdAt'] is DateTime) {
                createdAt = userData['createdAt'] as DateTime;
              }
            }

            users.add({
              'uid': uid,
              'name': userData['name'] ?? 'Unknown',
              'email': userData['email'] ?? '',
              'phoneNumber': userData['phoneNumber'] ?? '',
              'pairingCode': userData['pairingCode'] ?? '',
              'createdAt': createdAt,
              'isEmailVerified': userData['isEmailVerified'] ?? false,
              'familyContacts': userData['familyContacts'] ?? [],
            });
          }
        }
      }

      return users;
    } catch (e) {
      throw Exception('Gagal mengambil data pengguna: ${e.toString()}');
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
      return false;
    }
  }

  // ========== DIAGNOSTIC / TEST ==========
  /// Test Firestore connection with simple write
  Future<bool> testFirestoreConnection() async {
    try {
      final testStart = DateTime.now();

      // Try a simple write
      final testDocId = 'test_${DateTime.now().millisecondsSinceEpoch}';

      await _firestore
          .collection('_test')
          .doc(testDocId)
          .set({'timestamp': DateTime.now().toIso8601String()})
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Write timeout'),
          );

      final _ = DateTime.now().difference(testStart).inSeconds;

      // Try a read
      await _firestore.collection('_test').doc(testDocId).get();

      return true;
    } catch (e) {
      return false;
    }
  }

  // ========== FAMILY DEVICE TRACKING ==========
  /// Register device ketika family user login
  /// Disimpan di subcollection: users/{tunanetraUid}/connected_family_devices/{deviceId}
  Future<String> registerFamilyDevice({
    required String tunanetraUid,
    required String familyUid,
    required String familyName,
    required String deviceId,
    String? deviceName,
    required String deviceType, // 'android', 'ios', 'web'
  }) async {
    try {
      final now = DateTime.now();
      final device = FamilyDevice(
        deviceId: deviceId,
        familyUid: familyUid,
        familyName: familyName,
        deviceName: deviceName,
        deviceType: deviceType,
        firstConnectedAt: now,
        lastSeen: now,
      );

      // Simpan ke subcollection connected_family_devices
      await _firestore
          .collection('users')
          .doc(tunanetraUid)
          .collection('connected_family_devices')
          .doc(deviceId)
          .set(device.toMap());

      return deviceId;
    } catch (e) {
      throw Exception('Gagal mendaftar device: $e');
    }
  }

  /// Update last seen timestamp & status device
  Future<void> updateDeviceLastSeen(
    String tunanetraUid,
    String deviceId,
  ) async {
    try {
      final updateData = <String, dynamic>{
        'lastSeen': DateTime.now().toIso8601String(),
      };

      await _firestore
          .collection('users')
          .doc(tunanetraUid)
          .collection('connected_family_devices')
          .doc(deviceId)
          .update(updateData);
    } catch (e) {
      // Don't throw - ini background task
    }
  }

  /// Get semua connected family devices untuk tunanetra user
  Future<List<FamilyDevice>> getConnectedFamilyDevices(
    String tunanetraUid,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(tunanetraUid)
          .collection('connected_family_devices')
          .orderBy('lastSeen', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        return FamilyDevice.fromMap(doc.data());
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get stream untuk monitor devices (real-time)
  Stream<List<FamilyDevice>> getConnectedFamilyDevicesStream(
    String tunanetraUid,
  ) {
    return _firestore
        .collection('users')
        .doc(tunanetraUid)
        .collection('connected_family_devices')
        .orderBy('lastSeen', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => FamilyDevice.fromMap(doc.data()))
              .toList(),
        );
  }

  /// Disconnect/remove device
  Future<void> removeConnectedDevice(
    String tunanetraUid,
    String deviceId,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(tunanetraUid)
          .collection('connected_family_devices')
          .doc(deviceId)
          .delete();
    } catch (e) {
      throw Exception('Gagal menghapus device: $e');
    }
  }

  /// Update device name
  Future<void> updateDeviceName(
    String tunanetraUid,
    String deviceId,
    String newName,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(tunanetraUid)
          .collection('connected_family_devices')
          .doc(deviceId)
          .update({'deviceName': newName});
    } catch (e) {
      throw Exception('Gagal mengubah nama device: $e');
    }
  }
}
