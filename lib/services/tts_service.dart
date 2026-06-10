import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  static final TTSService _instance = TTSService._internal();

  factory TTSService() => _instance;

  TTSService._internal();

  final FlutterTts _tts = FlutterTts();

  bool _isInit = false;
  bool _isSttActive = false;
  int _speechGeneration = 0;

  bool get isSttActive => _isSttActive;
  int get speechGeneration => _speechGeneration;

  Future<void> init() async {
    if (_isInit) return;

    await _tts.setLanguage("id-ID");
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);

    _isInit = true;
  }

  Future<void> speak(String text) async {
    if (_isSttActive || text.trim().isEmpty) return;

    final generation = _speechGeneration;
    await init();
    if (_isSttActive || generation != _speechGeneration) return;

    await _tts.stop();
    if (_isSttActive || generation != _speechGeneration) return;

    await _tts.speak(text);
  }

  Future<void> stop() async {
    _speechGeneration++;
    await _tts.stop();
  }

  Future<void> beginSttSession() async {
    _isSttActive = true;
    await stop();
  }

  void endSttSession() {
    _isSttActive = false;
  }
}
