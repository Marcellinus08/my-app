import 'package:flutter_test/flutter_test.dart';
import 'package:teman_arah/services/sos_service.dart';

void main() {
  group('SosSendResult', () {
    test('melaporkan pengiriman penuh dengan jujur', () {
      const result = SosSendResult(
        sosId: 'sos-1',
        successCount: 2,
        failedCount: 0,
      );

      expect(result.deliveredToAllFamilies, isTrue);
      expect(result.feedbackMessage, contains('berhasil dikirim'));
    });

    test('melaporkan pengiriman parsial', () {
      const result = SosSendResult(
        sosId: 'sos-2',
        successCount: 1,
        failedCount: 1,
      );

      expect(result.deliveredToAnyFamily, isTrue);
      expect(result.deliveredToAllFamilies, isFalse);
      expect(result.feedbackMessage, contains('sebagian keluarga'));
    });

    test('tidak menyebut berhasil ketika seluruh push gagal', () {
      const result = SosSendResult(
        sosId: 'sos-3',
        successCount: 0,
        failedCount: 2,
      );

      expect(result.deliveredToAnyFamily, isFalse);
      expect(result.feedbackMessage, isNot(contains('berhasil')));
      expect(result.spokenMessage, contains('gagal dikirim'));
    });
  });
}
