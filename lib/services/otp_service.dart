import 'dart:math';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service untuk handle OTP (One Time Password) generation dan verification
class OtpService {
  static final OtpService _instance = OtpService._internal();

  factory OtpService() {
    return _instance;
  }

  OtpService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _otpCollection = 'otp_codes';
  static const int _otpLength = 6;
  static const int _otpValidityMinutes = 10; // OTP valid for 10 minutes

  /// Generate random 6-digit OTP
  String generateOtp() {
    final random = Random();
    String otp = '';
    for (int i = 0; i < _otpLength; i++) {
      otp += random.nextInt(10).toString();
    }
    print('✅ Generated OTP: $otp');
    return otp;
  }

  /// Send OTP to email (store in Firestore)
  /// Throws exception if OTP was not saved successfully
  Future<bool> sendOtpToEmail(String email) async {
    try {
      email = email.toLowerCase().trim();
      
      print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📧 [OTP SERVICE] STEP 1: Validating email');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      if (email.isEmpty) {
        throw Exception('Email tidak boleh kosong');
      }
      
      print('✅ Email valid: $email');
      
      print('\n📝 [OTP SERVICE] STEP 2: Generating OTP code');
      final otp = generateOtp();
      print('✅ OTP generated: $otp');
      
      print('\n⏰ [OTP SERVICE] STEP 3: Calculating expiry time');
      final now = DateTime.now();
      final expiresAt = now.add(Duration(minutes: _otpValidityMinutes));
      print('✅ OTP expires at: ${expiresAt.toString().split('.')[0]}');
      print('   Valid duration: $_otpValidityMinutes minutes');
      
      print('\n🔥 [OTP SERVICE] STEP 4: Saving OTP to Firestore');
      print('   Collection: $_otpCollection');
      print('   Document ID: $email');
      print('   Data: {email, otp, timestamps, attempts counter}');
      
      try {
        final startTime = DateTime.now();
        print('   ⏱️  Firestore write started...');
        
        await _firestore
            .collection(_otpCollection)
            .doc(email)
            .set(
              {
                'email': email,
                'otp': otp,
                'createdAt': FieldValue.serverTimestamp(),
                'expiresAt': Timestamp.fromDate(expiresAt),
                'attempts': 0,
                'maxAttempts': 5,
                'verified': false,
              },
              SetOptions(merge: true),
            )
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                print('   ⏱️  TIMEOUT after 15 seconds!');
                throw Exception('💥 Firestore write timeout (15s) - Backend tidak merespons');
              },
            );
        
        final duration = DateTime.now().difference(startTime).inSeconds;
        print('   ✅ Firestore write SUCCESS in ${duration}s');
        
      } on FirebaseException catch (fe) {
        print('   ❌ Firebase Exception: ${fe.code}');
        print('   Message: ${fe.message}');
        throw Exception('❌ Firebase: ${fe.message ?? fe.code}');
      } on TimeoutException catch (te) {
        print('   ❌ Timeout Exception: ${te.message}');
        throw Exception('💥 Network timeout - check internet connection');
      }

      print('\n✅ [OTP SERVICE] COMPLETE');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('OTP berhasil dikirim ke: $email\n');
      return true;
      
    } catch (e) {
      print('\n❌ [OTP SERVICE] ERROR');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('Error type: ${e.runtimeType}');
      print('Error: $e');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      rethrow;
    }
  }

  /// Verify OTP code
  /// Returns email if OTP is valid, null if invalid/expired
  Future<String?> verifyOtp(String email, String otp) async {
    try {
      print('\n╔════════════════════════════════════════════════════════╗');
      print('║ [OTP SERVICE] verifyOtp()                             ║');
      print('╚════════════════════════════════════════════════════════╝');
      
      print('\n[OTP] SUBSTEP 1: Normalizing input');
      email = email.toLowerCase().trim();
      otp = otp.trim();
      print('   Email: $email');
      print('   OTP Input: $otp');
      
      print('\n[OTP] SUBSTEP 2: Fetching OTP document from Firestore');
      print('   Collection: $_otpCollection');
      print('   Document ID: $email');
      print('   ⏱️  Reading from Firestore...');
      
      final fetchStart = DateTime.now();
      final docSnapshot = await _firestore
          .collection(_otpCollection)
          .doc(email)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('⏱️ OTP document fetch timeout'),
          );
      
      final fetchDuration = DateTime.now().difference(fetchStart).inSeconds;
      print('   Fetched in ${fetchDuration}s');

      if (!docSnapshot.exists) {
        throw Exception('❌ No OTP found for this email');
      }
      
      print('   ✅ OTP document found in Firestore');

      print('\n[OTP] SUBSTEP 3: Parsing OTP data');
      final data = docSnapshot.data() as Map<String, dynamic>;
      final storedOtp = data['otp'] as String?;
      final expiresAt = data['expiresAt'] as Timestamp?;
      final attempts = data['attempts'] as int? ?? 0;
      final maxAttempts = data['maxAttempts'] as int? ?? 5;
      final verified = data['verified'] as bool? ?? false;
      
      print('   Stored OTP: $storedOtp');
      print('   Expires At: ${expiresAt?.toDate()}');
      print('   Attempts: $attempts/$maxAttempts');
      print('   Already Verified: $verified');

      print('\n[OTP] SUBSTEP 4: Checking if OTP already verified');
      if (verified) {
        throw Exception('❌ OTP sudah digunakan sebelumnya');
      }
      print('   ✅ OTP belum diverifikasi');

      print('\n[OTP] SUBSTEP 5: Checking max attempts');
      if (attempts >= maxAttempts) {
        throw Exception('❌ Terlalu banyak percobaan gagal (${maxAttempts}x). Minta OTP baru.');
      }
      print('   ✅ Attempts valid ($attempts/$maxAttempts)');

      print('\n[OTP] SUBSTEP 6: Checking OTP expiry');
      if (expiresAt != null) {
        final now = DateTime.now();
        final expiryTime = expiresAt.toDate();
        final minutesRemaining = expiryTime.difference(now).inMinutes;
        
        if (now.isAfter(expiryTime)) {
          throw Exception('❌ OTP expired. Minta OTP baru.');
        }
        print('   ✅ OTP masih valid ($minutesRemaining menit tersisa)');
      }

      print('\n[OTP] SUBSTEP 7: Comparing OTP codes');
      print('   Stored OTP: $storedOtp');
      print('   User Input: $otp');
      
      if (storedOtp != otp) {
        print('   ❌ OTP tidak cocok!');
        
        print('\n[OTP] SUBSTEP 7b: Incrementing failed attempts');
        await _firestore
            .collection(_otpCollection)
            .doc(email)
            .update({
              'attempts': FieldValue.increment(1),
            })
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw Exception('Update attempts timeout'),
            );
        
        final newAttempts = attempts + 1;
        final remainingAttempts = maxAttempts - newAttempts;
        print('   Attempts updated: $newAttempts/$maxAttempts');
        throw Exception('❌ OTP salah ($remainingAttempts percobaan tersisa)');
      }
      
      print('   ✅ OTP cocok!');

      print('\n[OTP] SUBSTEP 8: Marking OTP as verified in Firestore');
      await _firestore
          .collection(_otpCollection)
          .doc(email)
          .update({
            'verified': true,
            'verifiedAt': FieldValue.serverTimestamp(),
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Verify update timeout'),
          );
      
      print('   ✅ OTP marked as verified');

      print('\n✅ [OTP SERVICE] verifyOtp() COMPLETE - OTP VALID\n');
      return email;
      
    } on FirebaseException catch (fe) {
      print('\n❌ [OTP SERVICE] Firebase Exception');
      print('   Code: ${fe.code}');
      print('   Message: ${fe.message}\n');
      rethrow;
      
    } on TimeoutException catch (te) {
      print('\n❌ [OTP SERVICE] Timeout Exception');
      print('   Message: ${te.message}\n');
      rethrow;
      
    } catch (e) {
      print('\n❌ [OTP SERVICE] OTP Verification Error');
      print('   Type: ${e.runtimeType}');
      print('   Message: $e\n');
      rethrow;
    }
  }

  /// Resend OTP to email (generates new OTP)
  Future<bool> resendOtp(String email) async {
    try {
      print('🔄 Resending OTP to email: $email');
      
      email = email.toLowerCase().trim();

      // Check if email has recent OTP (prevent spam)
      final docSnapshot = await _firestore
          .collection(_otpCollection)
          .doc(email)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('OTP fetch timeout'),
          );

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        final createdAt = data['createdAt'] as Timestamp?;
        
        if (createdAt != null) {
          final now = DateTime.now();
          final timeSinceCreation = now.difference(createdAt.toDate()).inSeconds;
          
          // Prevent resend within 30 seconds
          if (timeSinceCreation < 30) {
            print('⚠️ OTP resend limited. Wait 30s before resending.');
            throw Exception('Tunggu 30 detik sebelum meminta OTP baru');
          }
        }
      }

      // Generate and send new OTP
      return await sendOtpToEmail(email);
    } catch (e) {
      print('❌ Error resending OTP: $e');
      rethrow;
    }
  }

  /// Clean up expired OTPs (optional maintenance)
  /// Run this periodically to clean up database
  Future<void> cleanupExpiredOtps() async {
    try {
      print('🧹 Cleaning up expired OTPs...');
      
      final now = DateTime.now();
      final querySnapshot = await _firestore
          .collection(_otpCollection)
          .where('expiresAt', isLessThan: Timestamp.fromDate(now))
          .get()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Cleanup query timeout'),
          );

      int deletedCount = 0;
      for (final doc in querySnapshot.docs) {
        await doc.reference.delete();
        deletedCount++;
      }

      print('✅ Cleaned up $deletedCount expired OTPs');
    } catch (e) {
      print('⚠️ Error during OTP cleanup: $e');
      // Don't throw - this is maintenance function
    }
  }
}
