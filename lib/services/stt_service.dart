import 'package:speech_to_text/speech_to_text.dart';

class STTService {
  static final STTService _instance = STTService._internal();

  factory STTService() => _instance;

  STTService._internal();

  final SpeechToText _stt = SpeechToText();

  bool isListening = false;
  bool _isInitialized = false;
  SpeechErrorListener? _activeOnError;
  SpeechStatusListener? _activeOnStatus;

  bool get isActuallyListening => _stt.isListening;

  Future<bool> init({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
  }) async {
    _activeOnError = onError;
    _activeOnStatus = onStatus;

    if (_isInitialized) return true;

    _isInitialized = await _stt.initialize(
      onError: (error) => _activeOnError?.call(error),
      onStatus: (status) {
        isListening = status == 'listening';
        _activeOnStatus?.call(status);
      },
    );

    return _isInitialized;
  }

  Future<void> startListening(
    Function(String) onResult, {
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
  }) async {
    bool available = await init(onError: onError, onStatus: onStatus);

    if (available) {
      if (isListening) {
        await _stt.cancel();
        isListening = false;
      }

      isListening = true;

      await _stt.listen(
        localeId: "id_ID",
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 30),
        onResult: (result) {
          onResult(result.recognizedWords);
        },
      );
    } else {
      print("❌ STT tidak tersedia");
    }
  }

  Future<void> stopListening() async {
    if (!_isInitialized) return;
    await _stt.cancel();
    isListening = false;
  }
}
