import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/constants.dart';

/// Service untuk handle Firebase Authentication
class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Check if user is authenticated
  bool get isAuthenticated => _auth.currentUser != null;

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Get current user email
  String? get currentUserEmail => _auth.currentUser?.email;

  /// Get user by email
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    try {
      email = email.toLowerCase().trim();

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('User lookup timeout'),
          );

      if (userDoc.docs.isEmpty) {
        return null;
      }

      return userDoc.docs.first.data();
    } catch (e) {
      print('❌ Error getting user: $e');
      return null;
    }
  }


  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      print('📧 Sending password reset email to: $email');
      await _auth.sendPasswordResetEmail(email: email.trim());
      print('✅ Password reset email sent');
    } on FirebaseAuthException catch (e) {
      print('❌ Password reset error: ${e.code}');

      if (e.code == 'user-not-found') {
        throw Exception('Email tidak terdaftar');
      }
      throw Exception('Error mengirim email reset: ${e.message}');
    } catch (e) {
      print('❌ Unexpected error during password reset: $e');
      throw Exception('Error tidak terduga: $e');
    }
  }

  /// Delete user account
  Future<void> deleteAccount() async {
    try {
      print('🗑️ Deleting user account...');
      await _auth.currentUser?.delete();
      print('✅ Account deleted');
    } on FirebaseAuthException catch (e) {
      print('❌ Delete account error: ${e.code}');
      throw Exception('Gagal menghapus akun: ${e.message}');
    } catch (e) {
      print('❌ Unexpected error during account deletion: $e');
      throw Exception('Error tidak terduga: $e');
    }
  }

  /// Update email
  Future<void> updateEmail(String newEmail) async {
    try {
      print('📧 Updating email to: $newEmail');
      await _auth.currentUser?.updateEmail(newEmail.trim());
      print('✅ Email updated');
    } on FirebaseAuthException catch (e) {
      print('❌ Update email error: ${e.code}');
      throw Exception('Gagal mengubah email: ${e.message}');
    }
  }

  /// Update password
  Future<void> updatePassword(String newPassword) async {
    try {
      print('🔐 Updating password...');
      if (newPassword.length < 6) {
        throw Exception('Password minimal 6 karakter');
      }
      await _auth.currentUser?.updatePassword(newPassword);
      print('✅ Password updated');
    } on FirebaseAuthException catch (e) {
      print('❌ Update password error: ${e.code}');
      throw Exception('Gagal mengubah password: ${e.message}');
    }
  }

  /// Update password after verifying the current password
  Future<void> updatePasswordWithCurrentPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      print('Reauthenticating before password update...');

      final user = _auth.currentUser;
      final email = user?.email;

      if (user == null || email == null || email.isEmpty) {
        throw Exception('User belum login');
      }

      if (currentPassword.isEmpty || newPassword.isEmpty) {
        throw Exception('Password lama dan password baru harus diisi');
      }

      if (newPassword.length < 6) {
        throw Exception('Password baru minimal 6 karakter');
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
      print('Password updated after reauthentication');
    } on FirebaseAuthException catch (e) {
      print('Update password with reauth error: ${e.code}');

      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          throw Exception('Password lama salah');
        case 'weak-password':
          throw Exception('Password baru terlalu lemah');
        case 'requires-recent-login':
          throw Exception('Silakan login ulang sebelum mengubah password');
        default:
          throw Exception('Gagal mengubah password: ${e.message}');
      }
    }
  }

  /// Logout current user
  Future<void> logout() async {
    try {
      print('Logging out user...');
      await _auth.signOut();
      print('Logout successful');
    } catch (e) {
      print('Logout error: $e');
      throw Exception('Gagal logout: $e');
    }
  }

  /// ========== NEW FLOW: Email + Password ==========

  /// Check if email already exists in Firestore users collection
  Future<bool> emailExists(String email) async {
    try {
      email = email.toLowerCase().trim();

      print('🔍 Checking if email exists: $email');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Email lookup timeout'),
          );

      final exists = userDoc.docs.isNotEmpty;
      print(exists ? '⚠️ Email already registered' : '✅ Email available');

      return exists;
    } catch (e) {
      print('❌ Error checking email: $e');
      rethrow;
    }
  }

  /// NEW LOGIN METHOD: Login with email and password (no OTP)
  Future<UserCredential?> loginWithEmailPasswordNew(
    String email,
    String password,
  ) async {
    try {
      email = email.toLowerCase().trim();

      print('\n╔════════════════════════════════════════════════════════╗');
      print('║ [AUTH SERVICE] LOGIN WITH EMAIL & PASSWORD            ║');
      print('╚════════════════════════════════════════════════════════╝');

      print('\n[LOGIN] STEP 1: Validating inputs');
      if (email.isEmpty || password.isEmpty) {
        throw Exception('Email dan password harus diisi');
      }

      if (!email.contains('@')) {
        throw Exception('Format email tidak valid');
      }

      print('✅ Input valid');

      print('\n[LOGIN] STEP 2: Authenticating with Firebase Auth');
      print('   Email: $email');

      final userCredential = await _auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Login timeout - check network'),
          );

      print('✅ Authentication successful');
      print('   UID: ${userCredential.user?.uid}');
      print('   Email: ${userCredential.user?.email}');

      print('\n✅ [AUTH SERVICE] LOGIN COMPLETE\n');
      return userCredential;
    } on FirebaseAuthException catch (e) {
      print('\n❌ [AUTH SERVICE] Firebase Auth Exception');
      print('   Code: ${e.code}');

      switch (e.code) {
        case 'user-not-found':
          throw Exception('Email tidak terdaftar');
        case 'wrong-password':
          throw Exception('Password salah');
        case 'invalid-email':
          throw Exception('Format email tidak valid');
        case 'user-disabled':
          throw Exception('Akun ini telah dinonaktifkan');
        case 'too-many-requests':
          throw Exception('Terlalu banyak percobaan login. Coba lagi nanti.');
        default:
          throw Exception('Login gagal: ${e.message}');
      }
    } catch (e) {
      print('❌ [AUTH SERVICE] Unexpected Error: $e\n');
      rethrow;
    }
  }

  // ========== EMAIL VERIFICATION METHODS ==========

  /// Register dengan email verification (tanpa OTP)
  /// Langsung kirim verification email ke inbox user
  Future<User?> registerWithEmailPasswordAndVerification({
    required String email,
    required String password,
    required String name,
    required String phoneNumber,
    required UserType userType,
  }) async {
    try {
      email = email.toLowerCase().trim();

      print('\n╔════════════════════════════════════════════════════════╗');
      print('║ [AUTH SERVICE] REGISTER WITH EMAIL VERIFICATION       ║');
      print('╚════════════════════════════════════════════════════════╝');

      print('\n[REGISTER] STEP 1: Validating inputs');
      if (email.isEmpty || password.isEmpty || name.isEmpty) {
        throw Exception('Semua field harus diisi');
      }

      if (!email.contains('@')) {
        throw Exception('Format email tidak valid');
      }

      if (password.length < 6) {
        throw Exception('Password minimal 6 karakter');
      }

      print('✅ Input valid');

      print('\n[REGISTER] STEP 2: Creating Firebase Auth account');
      print('   Email: $email');

      final userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Account creation timeout'),
          );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('Failed to create user account');
      }

      print('✅ Firebase Auth user created');
      print('   UID: ${user.uid}');

      print('\n[REGISTER] STEP 3: Sending verification email');
      try {
        await user.sendEmailVerification().timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception('Email verification send timeout'),
        );
        print('✅ Verification email SENT to: $email');
        print('   User will receive verification link within 5-10 minutes');
        print('   If not received, check spam folder or use "Resend" button');
      } catch (e) {
        print('⚠️  [REGISTER] Warning: Could not send verification email');
        print('   Error: $e');
        print('   User can manually trigger resend from login screen');
        print('   Proceeding with registration anyway...');
      }

      print('\n✅ [AUTH SERVICE] STEP 1 COMPLETE - WAITING FOR VERIFICATION');
      print('   🔗 Verification email dikirim ke: $email');
      print(
        '   ⏳ Data akan disimpan ke Firestore setelah verifikasi berhasil\n',
      );
      return user;
    } on FirebaseAuthException catch (e) {
      print('\n❌ [AUTH SERVICE] Firebase Auth Exception');
      print('   Code: ${e.code}');

      switch (e.code) {
        case 'email-already-in-use':
          throw Exception('Email sudah terdaftar');
        case 'weak-password':
          throw Exception('Password terlalu lemah');
        case 'invalid-email':
          throw Exception('Format email tidak valid');
        default:
          throw Exception('Registrasi gagal: ${e.message}');
      }
    } catch (e) {
      print('❌ [AUTH SERVICE] Unexpected Error: $e\n');
      rethrow;
    }
  }

  /// Step 2: Save user data to Firestore AFTER email verification
  /// Called after user successfully verifies their email
  Future<void> saveUserDataToFirestore({
    required String uid,
    required String email,
    required String name,
    required String phoneNumber,
    required UserType userType,
  }) async {
    try {
      print('\n╔════════════════════════════════════════════════════════╗');
      print('║ [AUTH SERVICE] SAVE TO FIRESTORE (AFTER VERIFICATION) ║');
      print('╚════════════════════════════════════════════════════════╝');

      print('\n[SAVE] Saving user data to Firestore...');
      print('   UID: $uid');
      print('   Email: $email');
      print('   Name: $name');

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'uid': uid,
            'email': email,
            'name': name,
            'phoneNumber': phoneNumber,
            'userType': userType.toString(),
            'createdAt': FieldValue.serverTimestamp(),
            'emailVerified': true,
            'verificationCompletedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Firestore write timeout'),
          );

      print('\n✅ [SAVE] User data saved to Firestore successfully!');
      print('   Document: users/$uid');
      print('   emailVerified: true');
    } on FirebaseException catch (e) {
      print('\n❌ [SAVE] Firestore error: ${e.code}');
      throw Exception('Gagal menyimpan data: ${e.message}');
    } catch (e) {
      print('❌ [SAVE] Error: $e');
      rethrow;
    }
  }

  /// Cek apakah email sudah diverifikasi
  /// Check if current user's email is verified
  /// Automatically refreshes user data from Firebase
  Future<bool> isEmailVerified() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('[AUTH] No user logged in');
        return false;
      }

      // Refresh user untuk dapatkan email verification status terbaru dari Firebase
      print('[AUTH] Refreshing email verification status for: ${user.email}');
      await user.reload();

      final verified = user.emailVerified;
      print('[AUTH] Email verified status: $verified');
      return verified;
    } catch (e) {
      print('❌ [AUTH] Error checking email verification: $e');
      rethrow;
    }
  }

  /// Wait and check for email verification with polling
  /// Shows user when verification is complete
  /// Wait and check for email verification with long polling
  /// Used in registration flow to wait for user to verify email
  /// Returns true when verified, false if timeout
  /// OPTIMIZED: Polling setiap 2 detik untuk deteksi lebih cepat
  Future<bool> waitForEmailVerificationWithLongPolling({
    int maxAttempts = 300, // 10 minutes (300 * 2 seconds)
    Duration checkInterval = const Duration(seconds: 2),
  }) async {
    try {
      print('\n╔════════════════════════════════════════════════════════╗');
      print('║ [AUTH SERVICE] WAITING FOR EMAIL VERIFICATION         ║');
      print('╚════════════════════════════════════════════════════════╝');

      print('\n⏳ Starting email verification polling...');
      print(
        '   ✅ Checking every ${checkInterval.inSeconds}s (OPTIMIZED FOR SPEED)',
      );
      print(
        '   Max wait time: ${maxAttempts * checkInterval.inSeconds ~/ 60} minutes',
      );
      print('   📧 Waiting for user to click verification link...\n');

      for (int i = 0; i < maxAttempts; i++) {
        // Wait before checking
        await Future.delayed(checkInterval);

        // Refresh and check status
        final verified = await isEmailVerified();
        final elapsed = (i + 1) * checkInterval.inSeconds;
        final minutes = elapsed ~/ 60;
        final seconds = elapsed % 60;

        if (verified) {
          print('\n╔════════════════════════════════════════════════════════╗');
          print('║ ✅ EMAIL VERIFICATION SUCCESSFUL!                    ║');
          print('╚════════════════════════════════════════════════════════╝');
          print('✨ Time taken: ${minutes}m ${seconds}s\n');
          return true;
        }

        // Show progress every 30 checks (every 60 seconds)
        if ((i + 1) % 30 == 0) {
          print(
            '[AUTH] Still waiting... (${minutes}m ${seconds}s elapsed) - Check #${i + 1}/$maxAttempts',
          );
        }
      }

      print('\n╔════════════════════════════════════════════════════════╗');
      print('║ ⏱️  VERIFICATION TIMEOUT                              ║');
      print('╚════════════════════════════════════════════════════════╝');
      print(
        'User did not verify email in time (${maxAttempts * checkInterval.inSeconds ~/ 60} minutes)',
      );
      print('User can still manually verify and login later\n');
      return false;
    } catch (e) {
      print('\n❌ [AUTH] Error during verification polling: $e');
      rethrow;
    }
  }

  /// Resend verification email dengan retry logic
  /// Useful jika user tidak menerima email pertama
  Future<void> resendVerificationEmail({int maxRetries = 3}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User tidak login, tidak bisa kirim email');
      }

      if (user.emailVerified) {
        print('⚠️  [AUTH] Email sudah terverifikasi');
        throw Exception('Email sudah terverifikasi sebelumnya');
      }

      print('\n[AUTH] RESEND VERIFICATION EMAIL');
      print('   Target: ${user.email}');
      print('   Attempt: 1/$maxRetries');

      int attempt = 0;
      while (attempt < maxRetries) {
        attempt++;
        try {
          await user.sendEmailVerification().timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
              'Send email timeout',
              const Duration(seconds: 30),
            ),
          );

          print('✅ [AUTH] Verification email SENT successfully');
          print('   Check inbox at: ${user.email}');
          print('   Link valid untuk: 24 jam');
          print('   Jika tidak terima, cek folder spam');
          return;
        } on FirebaseAuthException catch (e) {
          print('⚠️  Attempt $attempt: Firebase error - ${e.code}');
          if (attempt < maxRetries) {
            print('   Retrying in 2 seconds...');
            await Future.delayed(const Duration(seconds: 2));
          } else {
            print('❌ All $maxRetries attempts failed');
            throw Exception(
              'Gagal mengirim email verifikasi setelah $maxRetries coba: ${e.message}',
            );
          }
        } catch (e) {
          print('⚠️  Attempt $attempt: Error - $e');
          if (attempt < maxRetries) {
            print('   Retrying in 2 seconds...');
            await Future.delayed(const Duration(seconds: 2));
          } else {
            print('❌ All $maxRetries attempts failed');
            throw Exception('Gagal mengirim email verifikasi: $e');
          }
        }
      }
    } catch (e) {
      print('❌ [AUTH] Error in resendVerificationEmail: $e');
      rethrow;
    }
  }

  /// Get user type from Firestore
  /// Returns UserType (tunanetra or family) based on user's profile
  Future<UserType?> getUserType() async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        print('⚠️  [AUTH] No user logged in, cannot get user type');
        return null;
      }

      print('[AUTH] Fetching user type for UID: $userId');

      final db = FirebaseFirestore.instance;

      // First check in 'users' collection
      final userDoc = await db.collection('users').doc(userId).get();

      if (userDoc.exists) {
        final userType = userDoc.data()?['userType'] as String?;
        print('✅ [AUTH] User type found: $userType');

        if (userType == 'tunanetra' || userType == 'UserType.tunanetra') {
          return UserType.tunanetra;
        } else if (userType == 'family' || userType == 'UserType.family') {
          return UserType.family;
        }
      }

      // Also check in 'tunanetra_users' collection for backward compatibility
      final tunaDoc = await db.collection('tunanetra_users').doc(userId).get();
      if (tunaDoc.exists) {
        print('✅ [AUTH] User found in tunanetra_users collection');
        return UserType.tunanetra;
      }

      // Check in 'family_users' collection
      final familyDoc = await db.collection('family_users').doc(userId).get();
      if (familyDoc.exists) {
        print('✅ [AUTH] User found in family_users collection');
        return UserType.family;
      }

      print('⚠️  [AUTH] User type not found in any collection');
      return null;
    } catch (e) {
      print('❌ [AUTH] Error getting user type: $e');
      return null;
    }
  }
}
