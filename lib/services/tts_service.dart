import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  final FlutterTts _tts = FlutterTts();

  bool _isInit = false;

  Future<void> init() async {
    if (_isInit) return;

    await _tts.setLanguage("id-ID");
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);

    _isInit = true;
  }

  Future<void> speak(String text) async {
    await init();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
