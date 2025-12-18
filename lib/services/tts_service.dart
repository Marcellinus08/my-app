import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-Speech Service untuk memberikan feedback audio ke pengguna tunanetra
class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Set language to Indonesian
      await _flutterTts.setLanguage('id-ID');
      
      // Set speech rate (kecepatan bicara)
      await _flutterTts.setSpeechRate(0.5); // 0.5 = normal, bisa disesuaikan
      
      // Set volume
      await _flutterTts.setVolume(1.0);
      
      // Set pitch
      await _flutterTts.setPitch(1.0);

      _isInitialized = true;
      print('TTS Service initialized');
    } catch (e) {
      print('Error initializing TTS: $e');
    }
  }

  Future<void> speak(String text) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      await _flutterTts.speak(text);
    } catch (e) {
      print('Error speaking: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      print('Error stopping TTS: $e');
    }
  }

  // Helper methods untuk announce umum
  Future<void> announceNavigation(String instruction) async {
    await speak('Navigasi: $instruction');
  }

  Future<void> announceButton(String buttonName) async {
    await speak('Tombol $buttonName');
  }

  Future<void> announceError(String errorMessage) async {
    await speak('Peringatan: $errorMessage');
  }

  Future<void> announceSuccess(String message) async {
    await speak('Berhasil: $message');
  }

  Future<void> announceBluetoothStatus(bool isConnected) async {
    if (isConnected) {
      await speak('Bluetooth terhubung dengan tongkat pintar');
    } else {
      await speak('Bluetooth terputus');
    }
  }

  void dispose() {
    _flutterTts.stop();
  }
}
