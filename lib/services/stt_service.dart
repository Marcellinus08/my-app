import 'package:speech_to_text/speech_to_text.dart';

class STTService {
  final SpeechToText _stt = SpeechToText();

  bool isListening = false;

  Future<bool> init() async {
    return await _stt.initialize();
  }

  Future<void> startListening(Function(String) onResult) async {
    bool available = await init();

    if (available) {
      isListening = true;

      _stt.listen(
        localeId: "id_ID",
        onResult: (result) {
          onResult(result.recognizedWords);
        },
      );
    } else {
      print("❌ STT tidak tersedia");
    }
  }

  Future<void> stopListening() async {
    await _stt.stop();
    isListening = false;
  }
}
