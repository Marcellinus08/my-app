import 'package:flutter_test/flutter_test.dart';
import 'package:teman_arah/services/tunanetra_voice_command_service.dart';

void main() {
  group('TunaNetraVoiceCommands.isSosCommand', () {
    test('menerima perintah SOS yang eksplisit', () {
      expect(TunaNetraVoiceCommands.isSosCommand('kirim SOS'), isTrue);
      expect(
        TunaNetraVoiceCommands.isSosCommand('aktifkan sos darurat'),
        isTrue,
      );
      expect(
        TunaNetraVoiceCommands.isSosCommand('saya butuh bantuan darurat'),
        isTrue,
      );
    });

    test('menolak kata bantuan biasa yang bukan kondisi darurat', () {
      expect(
        TunaNetraVoiceCommands.isSosCommand('buka buku panduan bantuan'),
        isFalse,
      );
      expect(
        TunaNetraVoiceCommands.isSosCommand('tolong buka navigasi'),
        isFalse,
      );
      expect(TunaNetraVoiceCommands.isSosCommand('menu bantuan'), isFalse);
    });
  });
}
