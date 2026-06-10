import 'package:flutter_test/flutter_test.dart';
import 'package:teman_arah/services/smart_cane_ble_service.dart';

void main() {
  group('SmartCaneSensorData.detectedObjectLabel', () {
    test('translates a direct model label to Indonesian', () {
      final data = SmartCaneSensorData.tryParse(
        '{"status":"warning","left":35,"center":20,"right":42,'
        '"mlLabel":"chair","message":"Hambatan terdeteksi"}',
      );

      expect(data?.detectedObjectLabel, 'kursi');
    });

    test('extracts an object label from the sensor message', () {
      final data = SmartCaneSensorData.tryParse(
        '{"status":"danger","left":15,"center":10,"right":18,'
        '"message":"Objek terdeteksi: person."}',
      );

      expect(data?.detectedObjectLabel, 'orang');
    });

    test('ignores model placeholder labels', () {
      final data = SmartCaneSensorData.tryParse(
        '{"status":"warning","left":35,"center":20,"right":42,'
        '"mlLabel":"no detection","message":"Hambatan terdeteksi"}',
      );

      expect(data?.detectedObjectLabel, isNull);
    });
  });

  group('SmartCaneSensorData.guidanceDecisionText', () {
    test('uses move wording for left and right guidance', () {
      final leftData = SmartCaneSensorData.tryParse(
        '{"status":"warning","left":20,"center":15,"right":50,'
        '"decision":"kiri","message":"Hambatan terdeteksi"}',
      );
      final rightData = SmartCaneSensorData.tryParse(
        '{"status":"warning","left":50,"center":15,"right":20,'
        '"decision":"belok kanan","message":"Hambatan terdeteksi"}',
      );

      expect(leftData?.guidanceDecisionText, 'Pindah ke kiri');
      expect(rightData?.guidanceDecisionText, 'Pindah ke kanan');
      expect(leftData?.displayText, contains('Keputusan: Pindah ke kiri'));
    });

    test('keeps forward and stop guidance concise', () {
      final forwardData = SmartCaneSensorData.tryParse(
        '{"status":"warning","left":50,"center":50,"right":50,'
        '"decision":"maju","message":"Hambatan terdeteksi"}',
      );
      final stopData = SmartCaneSensorData.tryParse(
        '{"status":"danger","left":10,"center":8,"right":9,'
        '"decision":"stop","message":"Hambatan terdeteksi"}',
      );

      expect(forwardData?.guidanceDecisionText, 'Maju');
      expect(stopData?.guidanceDecisionText, 'Berhenti');
    });
  });
}
