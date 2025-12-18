import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Speech-to-Text Service untuk AI Assistant (voice commands)
class SttService {
  static final SttService _instance = SttService._internal();
  factory SttService() => _instance;
  SttService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _isInitialized = await _speech.initialize(
        onError: (error) => print('STT Error: $error'),
        onStatus: (status) => print('STT Status: $status'),
      );
      return _isInitialized;
    } catch (e) {
      print('Error initializing STT: $e');
      return false;
    }
  }

  Future<void> startListening({
    required Function(String) onResult,
    String localeId = 'id_ID',
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isListening) return;

    try {
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            onResult(result.recognizedWords);
          }
        },
        localeId: localeId,
        listenMode: stt.ListenMode.confirmation,
      );
      _isListening = true;
    } catch (e) {
      print('Error starting listening: $e');
    }
  }

  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _speech.stop();
      _isListening = false;
    } catch (e) {
      print('Error stopping listening: $e');
    }
  }

  Future<void> cancel() async {
    try {
      await _speech.cancel();
      _isListening = false;
    } catch (e) {
      print('Error canceling STT: $e');
    }
  }

  bool get isAvailable => _speech.isAvailable;

  void dispose() {
    _speech.stop();
  }
}
