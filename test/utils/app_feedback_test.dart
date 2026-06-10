import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teman_arah/utils/app_feedback.dart';

void main() {
  group('AppErrorMessage', () {
    test('maps invalid Firebase credentials to a safe Indonesian message', () {
      final error = FirebaseAuthException(
        code: 'invalid-credential',
        message:
            'The supplied auth credential is incorrect, malformed or has expired.',
      );

      expect(
        AppErrorMessage.from(error),
        'Email atau kata sandi tidak sesuai.',
      );
    });

    test('maps network failures to an actionable message', () {
      final error = FirebaseAuthException(
        code: 'network-request-failed',
        message: 'A network error has occurred.',
      );

      expect(
        AppErrorMessage.from(error),
        'Koneksi internet bermasalah. Periksa jaringan lalu coba lagi.',
      );
    });

    test('does not expose an unknown technical exception', () {
      final error = Exception('INTERNAL ASSERTION FAILED at auth_handler.cc');

      expect(
        AppErrorMessage.from(error, fallback: 'Proses belum dapat dilakukan.'),
        'Proses belum dapat dilakukan.',
      );
    });
  });
}
