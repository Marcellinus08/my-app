import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/constants.dart';
import 'otp_service.dart';

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

  /// Login with email and password
  // DEPRECATED - Use loginWithOtp instead
  Future<UserCredential?> loginWithEmailPassword(
    String email,
    String password,
  ) async {
    try {
      print('🔐 Attempting login with email: $email');
      
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      
      print('✅ Login successful for user: ${userCredential.user?.email}');
      return userCredential;
    } on FirebaseAuthException catch (e) {
      print('❌ Login error: ${e.code} - ${e.message}');
      
      switch (e.code) {
        case 'user-not-found':
          throw Exception('Email tidak terdaftar');
        case 'wrong-password':
          throw Exception('Password salah');
        case 'invalid-email':
          throw Exception('Email tidak valid');
        case 'user-disabled':
          throw Exception('Akun ini telah dinonaktifkan');
        default:
          throw Exception('Login gagal: ${e.message}');
      }
    } catch (e) {
      print('❌ Unexpected error during login: $e');
      throw Exception('Error tidak terduga: $e');
    }
  }

  /// Request OTP for registration
  /// Generates and sends OTP code to user's email
  /// Throws exception if OTP sending failed
  Future<bool> requestRegistrationOtp(String email) async {
    try {
      email = email.toLowerCase().trim();
      
      print('\n╔════════════════════════════════════════════════════════╗');
      print('║ [AUTH SERVICE] REQUEST REGISTRATION OTP                ║');
      print('╚════════════════════════════════════════════════════════╝');
      
      print('\n[AUTH] STEP 1: Validating input');
      if (email.isEmpty) {
        throw Exception('Email tidak boleh kosong');
      }

      if (!email.contains('@')) {
        throw Exception('Format email tidak valid');
      }
      
      print('✅ Email format valid: $email');

      print('\n[AUTH] STEP 2: Creating OTP Service instance');
      final otpService = OtpService();
      print('✅ OTP Service created');
      
      print('\n[AUTH] STEP 3: Calling OTP Service sendOtpToEmail()');
      final success = await otpService.sendOtpToEmail(email);
      
      if (!success) {
        throw Exception('OTP Service returned false');
      }

      print('\n[AUTH] STEP 4: Request completed successfully');
      print('✅ OTP request successful for: $email');
      print('╔════════════════════════════════════════════════════════╗');
      print('║ USER akan menerima OTP ke email mereka                 ║');
      print('╚════════════════════════════════════════════════════════╝\n');
      return true;
      
    } catch (e) {
      print('\n❌ [AUTH SERVICE] REQUEST FAILED');
      print('Error: $e');
      print('╔════════════════════════════════════════════════════════╗\n');
      rethrow;
    }
  }

  /// Verify OTP and create user account
  /// After OTP is verified, creates a new user in Firebase Auth
  /// Then saves user data to Firestore
  Future<User?> registerWithOtp(
    String email,
    String otp,
    String username,
    UserType userType,
  ) async {
    try {
      email = email.toLowerCase().trim();
      
      print('\n╔════════════════════════════════════════════════════════╗');
      print('║ [AUTH SERVICE] registerWithOtp()                      ║');
      print('╚════════════════════════════════════════════════════════╝');
      
      print('\n[AUTH] SUBSTEP 1: Validating input parameters');
      print('   Email: $email');
      print('   Username: $username');
      print('   User Type: $userType');
      
      if (email.isEmpty || username.isEmpty) {
        throw Exception('Email atau username kosong');
      }

      print('\n[AUTH] SUBSTEP 2: Creating OTP Service instance');
      final otpService = OtpService();
      print('   ✅ OTP Service created');

      print('\n[AUTH] SUBSTEP 3: Verifying OTP code');
      print('   Calling otpService.verifyOtp($email, $otp)');
      final startTime = DateTime.now();
      
      final verifiedEmail = await otpService.verifyOtp(email, otp);
      
      final duration = DateTime.now().difference(startTime).inSeconds;
      print('   ⏱️  OTP verification took ${duration}s');
      
      if (verifiedEmail == null) {
        throw Exception('OTP verification failed - returned null');
      }

      print('   ✅ OTP verified successfully');

      print('\n[AUTH] SUBSTEP 4: Creating Firestore user document');
      print('   Collection: users');
      print('   Auto-generating document ID');
      
      // Generate a random UID using Firestore doc ID
      final usersRef = FirebaseFirestore.instance.collection('users');
      final newUserDoc = usersRef.doc();
      final uid = newUserDoc.id;
      
      print('   Generated UID: $uid');

      print('\n[AUTH] SUBSTEP 5: Writing user document to Firestore');
      print('   Data: {uid, email, username, userType, timestamps, verified}');
      print('   ⏱️  Starting write operation...');
      
      final writeStart = DateTime.now();
      
      await newUserDoc.set({
        'uid': uid,
        'email': email,
        'username': username,
        'userType': userType.toString(),
        'createdAt': FieldValue.serverTimestamp(),
        'verified': true,
        'verifiedVia': 'otp',
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('User creation timeout - Firestore write not responding'),
      );
      
      final writeDuration = DateTime.now().difference(writeStart).inSeconds;
      print('   ✅ Write completed in ${writeDuration}s');

      print('\n[AUTH] SUBSTEP 6: Verifying user was created');
      final verify = await newUserDoc.get();
      if (!verify.exists) {
        throw Exception('User document created but could not verify - read failed');
      }
      print('   ✅ User document verified - data exists in Firestore');

      print('\n✅ [AUTH SERVICE] registerWithOtp() COMPLETE\n');
      return null; // We'll return null and handle differently in app
      
    } on FirebaseAuthException catch (e) {
      print('\n❌ [AUTH SERVICE] Firebase Auth Exception');
      print('   Code: ${e.code}');
      print('   Message: ${e.message}\n');
      throw Exception('Firebase Auth: ${e.message}');
      
    } on TimeoutException catch (te) {
      print('\n❌ [AUTH SERVICE] Timeout Exception');
      print('   Message: ${te.message}\n');
      throw Exception('⏱️ Operation timed out - check network connection');
      
    } catch (e) {
      print('\n❌ [AUTH SERVICE] Unexpected Error');
      print('   Type: ${e.runtimeType}');
      print('   Message: $e\n');
      rethrow;
    }
  }

  /// Request OTP for login
  Future<bool> requestLoginOtp(String email) async {
    try {
      email = email.toLowerCase().trim();
      
      if (email.isEmpty) {
        throw Exception('Email tidak boleh kosong');
      }

      print('📧 Requesting OTP for login: $email');

      // Check if user exists
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
        throw Exception('Email tidak terdaftar');
      }

      // Send OTP
      final otpService = OtpService();
      final success = await otpService.sendOtpToEmail(email);
      
      if (!success) {
        throw Exception('Gagal mengirim OTP');
      }

      print('✅ OTP sent to: $email');
      return true;
    } catch (e) {
      print('❌ Error requesting login OTP: $e');
      rethrow;
    }
  }

  /// Verify OTP and login user
  Future<String?> loginWithOtp(String email, String otp) async {
    try {
      email = email.toLowerCase().trim();
      
      print('🔐 Verifying OTP for login: $email');

      // Verify OTP
      final otpService = OtpService();
      final verifiedEmail = await otpService.verifyOtp(email, otp);
      
      if (verifiedEmail == null) {
        throw Exception('OTP verification gagal');
      }

      // Get user data from Firestore
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
        throw Exception('User not found');
      }

      final uid = userDoc.docs.first.id;
      print('✅ Login successful: $email (UID: $uid)');
      
      return uid; // Return UID for app logic
    } catch (e) {
      print('❌ Login error: $e');
      rethrow;
    }
  }

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

  /// Register with email and password
  // DEPRECATED - Use registerWithOtp instead
  Future<UserCredential?> registerWithEmailPassword(
    String email,
    String password,
    String confirmPassword,
    String username,
    UserType userType,
  ) async {
    try {
      // Validate inputs
      if (email.isEmpty || password.isEmpty) {
        throw Exception('Email dan password tidak boleh kosong');
      }

      if (password != confirmPassword) {
        throw Exception('Password tidak sesuai');
      }

      if (password.length < 6) {
        throw Exception('Password minimal 6 karakter');
      }

      if (username.length < 3) {
        throw Exception('Username minimal 3 karakter');
      }

      print('📝 Attempting registration for: $email');
      print('   Firebase Auth instance: ${_auth.toString()}');

      // Add detailed logging for the auth operation
      print('📡 Creating user with email and password...');
      final startTime = DateTime.now();
      
      UserCredential? userCredential;
      try {
        userCredential = await _auth
            .createUserWithEmailAndPassword(
              email: email.trim(),
              password: password,
            )
            .timeout(
              const Duration(seconds: 90),
              onTimeout: () {
                print('❌ createUserWithEmailAndPassword timed out after 90s');
                print('   Firebase Auth is not responding');
                print('   CRITICAL: This usually means:');
                print('   1. ⚠️ Email/Password provider NOT enabled in Firebase Console');
                print('   2. ⚠️ Network connectivity issue on device');
                print('   3. ⚠️ Google Services misconfiguration');
                print('   ');
                print('   TO FIX:');
                print('   → Go to Firebase Console: https://console.firebase.google.com/');
                print('   → Select project: smarthcane-11b47');
                print('   → Go to Authentication → Sign-in method');
                print('   → Enable Email/Password provider');
                print('   → Ensure Android app is registered with package: com.example.my_app');
                throw TimeoutException('Firebase Auth timeout (90s) - Email/Password provider may not be enabled', const Duration(seconds: 90));
              },
            );
      } catch (e) {
        print('❌ Firebase Auth error: $e');
        rethrow;
      }

      final authTime = DateTime.now().difference(startTime).inSeconds;
      print('✅ User created in ${authTime}s: ${userCredential.user?.email}');

      // Update user profile
      await userCredential.user?.updateDisplayName(username);

      // Store additional user data in Firestore (optional here, will be done in UserService)
      print('✅ Registration successful for user: ${userCredential.user?.email}');
      
      return userCredential;
    } on FirebaseAuthException catch (e) {
      print('❌ Registration error: ${e.code} - ${e.message}');
      
      switch (e.code) {
        case 'weak-password':
          throw Exception('Password terlalu lemah, gunakan kombinasi huruf dan angka');
        case 'email-already-in-use':
          throw Exception('Email sudah terdaftar');
        case 'invalid-email':
          throw Exception('Email tidak valid');
        default:
          throw Exception('Registrasi gagal: ${e.message}');
      }
    } catch (e) {
      print('❌ Unexpected error during registration: $e');
      throw Exception('Error tidak terduga: $e');
    }
  }

  /// Logout
  Future<void> logout() async {
    try {
      print('🚪 Logging out...');
      await _auth.signOut();
      print('✅ Logout successful');
    } catch (e) {
      print('❌ Logout error: $e');
      throw Exception('Logout gagal: $e');
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
      
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      ).timeout(
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

  /// NEW REGISTER METHOD: Register with email, password, and OTP verification
  /// Flow: 1. Check email tidak ada 2. Kirim OTP 3. Verify OTP 4. Create account
  Future<User?> registerWithEmailPasswordAndOtp({
    required String email,
    required String password,
    required String otp,
    required String name,
    required String phoneNumber,
    required UserType userType,
  }) async {
    try {
      email = email.toLowerCase().trim();
      
      print('\n╔════════════════════════════════════════════════════════╗');
      print('║ [AUTH SERVICE] REGISTER WITH EMAIL, PASSWORD & OTP    ║');
      print('╚════════════════════════════════════════════════════════╝');
      
      print('\n[REGISTER] STEP 1: Validating inputs');
      if (email.isEmpty || password.isEmpty || otp.isEmpty || name.isEmpty) {
        throw Exception('Semua field harus diisi');
      }
      
      if (!email.contains('@')) {
        throw Exception('Format email tidak valid');
      }
      
      if (password.length < 6) {
        throw Exception('Password minimal 6 karakter');
      }
      
      print('✅ Input valid');

      print('\n[REGISTER] STEP 2: Verifying OTP');
      final otpService = OtpService();
      final verifiedEmail = await otpService.verifyOtp(email, otp);
      
      if (verifiedEmail == null) {
        throw Exception('OTP verification failed');
      }
      print('✅ OTP verified');

      print('\n[REGISTER] STEP 3: Creating Firebase Auth account');
      print('   Email: $email');
      
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Account creation timeout'),
      );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('Failed to create user account');
      }

      print('✅ Firebase Auth user created');
      print('   UID: ${user.uid}');

      print('\n[REGISTER] STEP 4: Saving user profile to Firestore');
      print('   Collection: users');
      print('   Document ID: ${user.uid}');
      
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
            'uid': user.uid,
            'email': email,
            'name': name,
            'phoneNumber': phoneNumber,
            'userType': userType.toString(),
            'createdAt': FieldValue.serverTimestamp(),
            'verified': true,
            'verifiedVia': 'otp',
          })
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Firestore write timeout'),
          );

      print('✅ User profile saved to Firestore');

      print('\n✅ [AUTH SERVICE] REGISTER COMPLETE\n');
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
      
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      ).timeout(
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
      print('   ⏳ Data akan disimpan ke Firestore setelah verifikasi berhasil\n');
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
      print('   ✅ Checking every ${checkInterval.inSeconds}s (OPTIMIZED FOR SPEED)');
      print('   Max wait time: ${maxAttempts * checkInterval.inSeconds ~/ 60} minutes');
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
          print('[AUTH] Still waiting... (${minutes}m ${seconds}s elapsed) - Check #${i + 1}/$maxAttempts');
        }
      }
      
      print('\n╔════════════════════════════════════════════════════════╗');
      print('║ ⏱️  VERIFICATION TIMEOUT                              ║');
      print('╚════════════════════════════════════════════════════════╝');
      print('User did not verify email in time (${maxAttempts * checkInterval.inSeconds ~/ 60} minutes)');
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
            onTimeout: () => throw TimeoutException('Send email timeout', const Duration(seconds: 30)),
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
            throw Exception('Gagal mengirim email verifikasi setelah $maxRetries coba: ${e.message}');
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
        
        if (userType == 'UserType.tunanetra') {
          return UserType.tunanetra;
        } else if (userType == 'UserType.family') {
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


