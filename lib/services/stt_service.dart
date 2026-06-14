import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'tts_service.dart';

class STTService {
  static final STTService _instance = STTService._internal();

  factory STTService() => _instance;

  STTService._internal();

  final SpeechToText _stt = SpeechToText();

  bool isListening = false;
  bool _isInitialized = false;
  bool _isStartingListening = false;
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
    Duration pauseFor = const Duration(seconds: 30),
    bool finalResultsOnly = false,
  }) async {
    final ttsService = TTSService();
    await ttsService.beginSttSession();

    try {
      final available = await init(
        onError: (error) {
          isListening = false;
          ttsService.endSttSession();
          onError?.call(error);
        },
        onStatus: (status) {
          isListening = status == 'listening';
          if (!_isStartingListening &&
              (status == 'done' || status == 'notListening')) {
            ttsService.endSttSession();
          }
          onStatus?.call(status);
        },
      );

      if (!available) {
        ttsService.endSttSession();
        debugPrint('STT tidak tersedia');
        return;
      }

      _isStartingListening = true;
      if (_stt.isListening || isListening) {
        await _stt.cancel();
        isListening = false;
      }

      await ttsService.beginSttSession();
      isListening = true;

      await _stt.listen(
        localeId: "id_ID",
        listenFor: const Duration(minutes: 5),
        pauseFor: pauseFor,
        onResult: (result) {
          if (finalResultsOnly && !result.finalResult) return;
          onResult(result.recognizedWords);
        },
      );
    } catch (error, stackTrace) {
      isListening = false;
      ttsService.endSttSession();
      debugPrint('Gagal memulai STT: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isStartingListening = false;
    }
  }

  Future<void> stopListening() async {
    try {
      if (_isInitialized) {
        await _stt.cancel();
        isListening = false;
      }
    } finally {
      TTSService().endSttSession();
    }
  }

  Future<void> finishListening() async {
    try {
      if (_isInitialized && _stt.isListening) {
        await _stt.stop();
        isListening = false;
      }
    } finally {
      TTSService().endSttSession();
    }
  }
}
