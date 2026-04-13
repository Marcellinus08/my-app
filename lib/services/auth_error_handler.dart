import 'package:cloud_firestore/cloud_firestore.dart';

/// Auth Error Handler - Handle various authentication errors
class AuthErrorHandler {
  static String getErrorMessage(dynamic error) {
    final errorString = error.toString();

    // Firebase Auth Exceptions
    if (errorString.contains('user-not-found')) {
      return 'Email tidak terdaftar. Silakan daftar terlebih dahulu.';
    }
    if (errorString.contains('wrong-password')) {
      return 'Password salah. Silakan coba lagi.';
    }
    if (errorString.contains('invalid-email')) {
      return 'Format email tidak valid.';
    }
    if (errorString.contains('user-disabled')) {
      return 'Akun ini telah dinonaktifkan.';
    }
    if (errorString.contains('email-already-in-use')) {
      return 'Email sudah terdaftar. Gunakan email lain.';
    }
    if (errorString.contains('weak-password')) {
      return 'Password terlalu lemah. Gunakan minimal 8 karakter dengan kombinasi huruf dan angka.';
    }
    if (errorString.contains('too-many-requests')) {
      return 'Terlalu banyak percobaan gagal. Coba lagi nanti.';
    }
    if (errorString.contains('network-request-failed')) {
      return 'Koneksi internet tidak stabil. Periksa koneksi Anda.';
    }

    // OTP Errors
    if (errorString.contains('No OTP found')) {
      return 'OTP tidak ditemukan. Silakan minta OTP baru.';
    }
    if (errorString.contains('OTP sudah digunakan')) {
      return 'OTP sudah digunakan sebelumnya. Minta OTP baru.';
    }
    if (errorString.contains('OTP expired')) {
      return 'OTP telah kadaluarsa. Minta OTP baru.';
    }
    if (errorString.contains('OTP salah')) {
      return 'Kode OTP tidak sesuai. Periksa kembali.';
    }
    if (errorString.contains('Terlalu banyak percobaan')) {
      return 'Terlalu banyak percobaan gagal. Minta OTP baru.';
    }

    // Firestore Errors
    if (errorString.contains('PERMISSION_DENIED')) {
      return 'Anda tidak memiliki akses. Hubungi admin.';
    }
    if (errorString.contains('NOT_FOUND')) {
      return 'Data tidak ditemukan.';
    }
    if (errorString.contains('ALREADY_EXISTS')) {
      return 'Data sudah ada. Gunakan data lain.';
    }
    if (errorString.contains('FAILED_PRECONDITION')) {
      return 'Kondisi tidak terpenuhi. Silakan coba lagi.';
    }
    if (errorString.contains('Timeout')) {
      return 'Koneksi timeout. Periksa internet dan coba lagi.';
    }

    // Default error
    return 'Terjadi kesalahan: ${errorString.cleanErrorMessage()}';
  }

  /// Get recovery suggestion
  static String getRecoverySuggestion(dynamic error) {
    final errorString = error.toString();

    if (errorString.contains('network')) {
      return 'Pastikan koneksi internet Anda aktif dan stabil.';
    }
    if (errorString.contains('timeout')) {
      return 'Coba lagi dalam beberapa saat. Server sedang sibuk.';
    }
    if (errorString.contains('too-many-requests')) {
      return 'Tunggu beberapa menit sebelum mencoba lagi.';
    }
    if (errorString.contains('OTP')) {
      return 'Periksa email Anda untuk menerima kode OTP baru.';
    }
    if (errorString.contains('permission')) {
      return 'Hubungi tim support kami untuk membantu.';
    }

    return 'Silakan coba lagi atau hubungi support.';
  }

  /// Check if error is recoverable
  static bool isRecoverable(dynamic error) {
    final errorString = error.toString();

    // Non-recoverable errors
    if (errorString.contains('PERMISSION_DENIED')) return false;
    if (errorString.contains('email-already-in-use')) return false;
    if (errorString.contains('OTP sudah digunakan')) return false;
    if (errorString.contains('user-disabled')) return false;

    // Recoverable errors
    return true;
  }

  /// Categorize error for analytics
  static AuthErrorCategory categorizeError(dynamic error) {
    final errorString = error.toString();

    if (errorString.contains('network') ||
        errorString.contains('timeout') ||
        errorString.contains('connection')) {
      return AuthErrorCategory.network;
    }

    if (errorString.contains('OTP')) {
      return AuthErrorCategory.otp;
    }

    if (errorString.contains('email') || errorString.contains('password')) {
      return AuthErrorCategory.credentials;
    }

    if (errorString.contains('permission') ||
        errorString.contains('security')) {
      return AuthErrorCategory.security;
    }

    return AuthErrorCategory.unknown;
  }
}

/// Auth Error Category types for tracking
enum AuthErrorCategory {
  network,
  otp,
  credentials,
  security,
  unknown,
}

/// Extension for error message cleanup
extension StringExtension on String {
  String cleanErrorMessage() {
    return replaceAll('Exception: ', '').replaceAll('[FirebaseException] ', '');
  }
}

/// Auth Recovery Manager - Handle recovery strategies
class AuthRecoveryManager {
  static final AuthRecoveryManager _instance =
      AuthRecoveryManager._internal();

  factory AuthRecoveryManager() {
    return _instance;
  }

  AuthRecoveryManager._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Track failed login attempts
  Future<void> trackFailedLogin(String email) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      await _firestore
          .collection('auth_logs')
          .doc(email)
          .collection('failed_attempts')
          .add({
        'timestamp': FieldValue.serverTimestamp(),
        'date': today,
        'type': 'login_attempt',
      });

      print('📊 Logged failed login attempt for: $email');
    } catch (e) {
      print('⚠️ Error logging failed attempt: $e');
    }
  }

  /// Get failed attempt count for today
  Future<int> getFailedAttemptCount(String email) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final snapshot = await _firestore
          .collection('auth_logs')
          .doc(email)
          .collection('failed_attempts')
          .where('date', isEqualTo: today)
          .get();

      return snapshot.docs.length;
    } catch (e) {
      print('⚠️ Error getting attempt count: $e');
      return 0;
    }
  }

  /// Check if account should be temporarily locked
  Future<bool> shouldLockAccount(String email) async {
    try {
      final attempts = await getFailedAttemptCount(email);
      return attempts >= 5; // Lock after 5 failed attempts
    } catch (e) {
      print('⚠️ Error checking lock status: $e');
      return false;
    }
  }

  /// Reset failed attempts for email
  Future<void> resetFailedAttempts(String email) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final snapshot = await _firestore
          .collection('auth_logs')
          .doc(email)
          .collection('failed_attempts')
          .where('date', isEqualTo: today)
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }

      print('✅ Reset failed attempts for: $email');
    } catch (e) {
      print('⚠️ Error resetting attempts: $e');
    }
  }

  /// Send security alert email
  Future<void> sendSecurityAlert(String email, String reason) async {
    try {
      await _firestore.collection('security_alerts').add({
        'email': email,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      print('🔒 Security alert created for: $email - Reason: $reason');
    } catch (e) {
      print('⚠️ Error creating security alert: $e');
    }
  }
}
