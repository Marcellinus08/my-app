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
      return null;
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          throw Exception('Email tidak terdaftar');
        case 'invalid-email':
          throw Exception('Format email tidak valid');
        case 'too-many-requests':
          throw Exception('Terlalu banyak permintaan. Coba lagi nanti.');
        case 'network-request-failed':
          throw Exception('Koneksi internet bermasalah');
        default:
          throw Exception('Email reset belum dapat dikirim');
      }
    } catch (e) {
      throw Exception('Email reset belum dapat dikirim');
    }
  }

  /// Delete user account
  Future<void> deleteAccount() async {
    try {
      await _auth.currentUser?.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception('Silakan masuk kembali sebelum menghapus akun');
      }
      throw Exception('Akun belum dapat dihapus');
    } catch (e) {
      throw Exception('Akun belum dapat dihapus');
    }
  }

  /// Update email
  Future<void> updateEmail(String newEmail) async {
    try {
      await _auth.currentUser?.updateEmail(newEmail.trim());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw Exception('Email tersebut sudah digunakan');
      }
      if (e.code == 'requires-recent-login') {
        throw Exception('Silakan masuk kembali sebelum mengubah email');
      }
      throw Exception('Email belum dapat diubah');
    }
  }

  /// Update password
  Future<void> updatePassword(String newPassword) async {
    try {
      if (newPassword.length < 6) {
        throw Exception('Password minimal 6 karakter');
      }
      await _auth.currentUser?.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception('Silakan masuk kembali sebelum mengubah kata sandi');
      }
      throw Exception('Kata sandi belum dapat diubah');
    }
  }

  /// Update password after verifying the current password
  Future<void> updatePasswordWithCurrentPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
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
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          throw Exception('Password lama salah');
        case 'weak-password':
          throw Exception('Password baru terlalu lemah');
        case 'requires-recent-login':
          throw Exception('Silakan login ulang sebelum mengubah password');
        default:
          throw Exception('Kata sandi belum dapat diubah');
      }
    }
  }

  /// Logout current user
  Future<void> logout() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception('Gagal logout: $e');
    }
  }

  /// ========== NEW FLOW: Email + Password ==========

  /// Check if email already exists in Firestore users collection
  Future<bool> emailExists(String email) async {
    try {
      email = email.toLowerCase().trim();

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Email lookup timeout'),
          );

      return userDoc.docs.isNotEmpty;
    } catch (e) {
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

      if (email.isEmpty || password.isEmpty) {
        throw Exception('Email dan password harus diisi');
      }

      if (!email.contains('@')) {
        throw Exception('Format email tidak valid');
      }

      final userCredential = await _auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Login timeout - check network'),
          );

      return userCredential;
    } on FirebaseAuthException catch (e) {
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
        case 'network-request-failed':
          throw Exception('Koneksi internet bermasalah');
        case 'invalid-credential':
          throw Exception('Email atau kata sandi tidak sesuai');
        default:
          throw Exception('Tidak dapat masuk. Silakan coba lagi.');
      }
    } catch (e) {
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

      if (email.isEmpty || password.isEmpty || name.isEmpty) {
        throw Exception('Semua field harus diisi');
      }

      if (!email.contains('@')) {
        throw Exception('Format email tidak valid');
      }

      if (password.length < 6) {
        throw Exception('Password minimal 6 karakter');
      }

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

      try {
        await user.sendEmailVerification().timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception('Email verification send timeout'),
        );
      } catch (e) {
        try {
          await user.delete();
        } catch (_) {
          // ignore cleanup error
        }
        throw Exception(
          'Email verifikasi belum dapat dikirim. Periksa koneksi lalu coba lagi.',
        );
      }

      return user;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          // Solusi 1: coba login dengan kredensial yang sama
          try {
            final existingCredential = await _auth
                .signInWithEmailAndPassword(email: email, password: password)
                .timeout(const Duration(seconds: 30));
            final existingUser = existingCredential.user;
            if (existingUser != null) {
              await existingUser.reload();
              final profile = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(existingUser.uid)
                  .get()
                  .timeout(const Duration(seconds: 15));

              // Akun belum selesai daftar (Firestore kosong) → hapus dan buat ulang
              if (!profile.exists && !existingUser.emailVerified) {
                await existingUser.delete();
                final newCredential = await _auth
                    .createUserWithEmailAndPassword(
                      email: email,
                      password: password,
                    )
                    .timeout(const Duration(seconds: 30));
                final newUser = newCredential.user;
                if (newUser != null) {
                  await newUser.sendEmailVerification().timeout(
                    const Duration(seconds: 30),
                  );
                  return newUser;
                }
              }
            }
          } catch (_) {
            // ignore recovery error
          }
          throw Exception('Email sudah terdaftar');
        case 'weak-password':
          throw Exception('Password terlalu lemah');
        case 'invalid-email':
          throw Exception('Format email tidak valid');
        case 'network-request-failed':
          throw Exception('Koneksi internet bermasalah');
        default:
          throw Exception('Pendaftaran belum dapat diselesaikan');
      }
    } catch (e) {
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'uid': uid,
            'email': email,
            'username': name,
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
    } on FirebaseException catch (_) {
      throw Exception('Data akun belum dapat disimpan');
    } catch (e) {
      rethrow;
    }
  }

  /// Cek apakah email sudah diverifikasi
  /// Check if current user's email is verified
  /// Automatically refreshes user data from Firebase
  Future<bool> isEmailVerified({int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await _checkEmailVerifiedOnce();
      } on FirebaseAuthException catch (e) {
        if (e.code != 'network-request-failed') rethrow;
      } on TimeoutException {
        // retry on timeout
      }

      if (attempt < maxRetries) {
        await Future.delayed(Duration(seconds: attempt));
      }
    }

    // The polling loop will retry. A foreground network transition must not
    // cancel an otherwise valid registration.
    return false;
  }

  Future<bool> _checkEmailVerifiedOnce() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return false;
      }

      // Refresh user untuk dapatkan email verification status terbaru dari Firebase
      await user.reload().timeout(const Duration(seconds: 15));

      final refreshedUser = _auth.currentUser;
      final verified = refreshedUser?.emailVerified ?? false;
      if (verified) {
        try {
          await refreshedUser
              ?.getIdToken(true)
              .timeout(const Duration(seconds: 15));
        } catch (_) {
          // Verification is already valid. A delayed token refresh must not
          // turn a successful email verification into a failed registration.
        }
      }
      return verified;
    } catch (e) {
      rethrow;
    }
  }

  /// Wait and check for email verification with long polling
  /// Used in registration flow to wait for user to verify email
  /// Returns true when verified, false if timeout
  /// OPTIMIZED: Polling setiap 2 detik untuk deteksi lebih cepat
  Future<bool> waitForEmailVerificationWithLongPolling({
    int maxAttempts = 300, // 10 minutes (300 * 2 seconds)
    Duration checkInterval = const Duration(seconds: 2),
    bool Function()? isCancelled,
  }) async {
    try {
      for (int i = 0; i < maxAttempts; i++) {
        if (isCancelled?.call() ?? false) {
          return false;
        }

        await Future.delayed(checkInterval);

        if (isCancelled?.call() ?? false) {
          return false;
        }

        final verified = await isEmailVerified();

        if (verified) {
          return true;
        }
      }

      return false;
    } catch (e) {
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
        throw Exception('Email sudah terverifikasi sebelumnya');
      }

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
          return;
        } on FirebaseAuthException catch (e) {
          if (attempt < maxRetries) {
            await Future.delayed(const Duration(seconds: 2));
          } else {
            throw Exception(
              'Gagal mengirim email verifikasi setelah $maxRetries coba: ${e.message}',
            );
          }
        } catch (e) {
          if (attempt < maxRetries) {
            await Future.delayed(const Duration(seconds: 2));
          } else {
            throw Exception('Gagal mengirim email verifikasi: $e');
          }
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get user type from Firestore
  /// Returns UserType (tunanetra or family) based on user's profile
  Future<UserType?> getUserType() async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        return null;
      }

      final db = FirebaseFirestore.instance;

      // First check in 'users' collection
      final userDoc = await db.collection('users').doc(userId).get();

      if (userDoc.exists) {
        final userType = userDoc.data()?['userType'] as String?;

        if (userType == 'tunanetra' || userType == 'UserType.tunanetra') {
          return UserType.tunanetra;
        } else if (userType == 'family' || userType == 'UserType.family') {
          return UserType.family;
        }
      }

      // Also check in 'tunanetra_users' collection for backward compatibility
      final tunaDoc = await db.collection('tunanetra_users').doc(userId).get();
      if (tunaDoc.exists) {
        return UserType.tunanetra;
      }

      // Check in 'family_users' collection
      final familyDoc = await db.collection('family_users').doc(userId).get();
      if (familyDoc.exists) {
        return UserType.family;
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
