import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum TtsPriority { low, normal, navigation, warning, critical }

class TTSService {
  static final TTSService _instance = TTSService._internal();

  factory TTSService() => _instance;

  TTSService._internal();

  final FlutterTts _tts = FlutterTts();
  final List<_TtsRequest> _queue = [];
  final Map<String, DateTime> _recentlyCompleted = {};

  bool _isInit = false;
  bool _isSttActive = false;
  bool _isProcessing = false;
  int _speechGeneration = 0;
  int _requestSequence = 0;
  _TtsRequest? _currentRequest;

  bool get isSttActive => _isSttActive;
  bool get isSpeaking => _currentRequest != null;
  int get speechGeneration => _speechGeneration;

  Future<void> init() async {
    if (_isInit) return;

    await _tts.setLanguage('id-ID');
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);

    _isInit = true;
  }

  Future<void> speak(
    String text, {
    TtsPriority priority = TtsPriority.normal,
    String? deduplicationKey,
    String? replacementKey,
    Duration? maxAge,
    Duration duplicateWindow = const Duration(seconds: 2),
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) return;

    final request = _TtsRequest(
      sequence: _requestSequence++,
      text: normalizedText,
      priority: priority,
      deduplicationKey: deduplicationKey?.trim().isNotEmpty == true
          ? deduplicationKey!.trim()
          : normalizedText.toLowerCase(),
      replacementKey: replacementKey?.trim().isNotEmpty == true
          ? replacementKey!.trim()
          : null,
      expiresAt: DateTime.now().add(maxAge ?? _defaultMaxAge(priority)),
      duplicateWindow: duplicateWindow,
    );

    if (_isSttActive && !_isSafetyPriority(priority)) {
      request.complete();
      return request.done;
    }

    _discardExpiredRequests();
    _removeReplacedRequests(request);

    if (_isDuplicate(request)) {
      request.complete();
      return request.done;
    }

    _queue.add(request);

    if (_shouldInterruptCurrent(request)) {
      await _interruptCurrentSpeech();
    }

    _scheduleProcessing();
    return request.done;
  }

  Future<void> stop({bool clearQueue = true}) async {
    _speechGeneration++;

    if (clearQueue) {
      for (final request in _queue) {
        request.complete();
      }
      _queue.clear();
    }

    await _tts.stop();
  }

  Future<void> cancelByReplacementKey(String replacementKey) async {
    final normalizedKey = replacementKey.trim();
    if (normalizedKey.isEmpty) return;

    for (final request in _queue.where(
      (request) => request.replacementKey == normalizedKey,
    )) {
      request.complete();
    }
    _queue.removeWhere((request) => request.replacementKey == normalizedKey);

    if (_currentRequest?.replacementKey == normalizedKey) {
      await _interruptCurrentSpeech();
    }
  }

  Future<void> beginSttSession() async {
    _isSttActive = true;

    final currentRequest = _currentRequest;
    if (currentRequest != null &&
        _isSafetyPriority(currentRequest.priority) &&
        !currentRequest.isExpired &&
        !_queue.any(
          (request) =>
              request.deduplicationKey == currentRequest.deduplicationKey,
        )) {
      _queue.add(currentRequest.copyForRetry(sequence: _requestSequence++));
    }

    for (final request in _queue.where(
      (request) => !_isSafetyPriority(request.priority),
    )) {
      request.complete();
    }
    _queue.removeWhere((request) => !_isSafetyPriority(request.priority));

    await _interruptCurrentSpeech();
  }

  void endSttSession() {
    if (!_isSttActive) return;
    _isSttActive = false;
    _scheduleProcessing();
  }

  void _scheduleProcessing() {
    if (_isProcessing || _isSttActive) return;
    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      await init();

      while (!_isSttActive) {
        _discardExpiredRequests();
        final request = _takeNextRequest();
        if (request == null) break;

        final generation = _speechGeneration;
        _currentRequest = request;

        try {
          await _tts.stop();
          if (_isSttActive ||
              generation != _speechGeneration ||
              request.isExpired) {
            continue;
          }

          await _tts.speak(request.text);
          if (generation == _speechGeneration && !_isSttActive) {
            _recentlyCompleted[request.deduplicationKey] = DateTime.now();
          }
        } catch (error, stackTrace) {
          debugPrint('[TTS] Gagal membacakan pesan: $error');
          debugPrintStack(stackTrace: stackTrace);
        } finally {
          if (identical(_currentRequest, request)) {
            _currentRequest = null;
          }
          request.complete();
        }
      }
    } finally {
      _isProcessing = false;
      if (!_isSttActive && _queue.isNotEmpty) {
        _scheduleProcessing();
      }
    }
  }

  _TtsRequest? _takeNextRequest() {
    if (_queue.isEmpty) return null;

    var bestIndex = 0;
    for (var index = 1; index < _queue.length; index++) {
      final candidate = _queue[index];
      final currentBest = _queue[bestIndex];
      if (candidate.priority.index > currentBest.priority.index ||
          (candidate.priority == currentBest.priority &&
              candidate.sequence < currentBest.sequence)) {
        bestIndex = index;
      }
    }

    return _queue.removeAt(bestIndex);
  }

  bool _shouldInterruptCurrent(_TtsRequest request) {
    final current = _currentRequest;
    if (current == null) return false;
    if (request.priority == TtsPriority.critical) return true;
    return request.priority == TtsPriority.warning &&
        current.priority.index < TtsPriority.warning.index;
  }

  Future<void> _interruptCurrentSpeech() async {
    if (_currentRequest == null && !_isProcessing) return;
    _speechGeneration++;
    await _tts.stop();
  }

  bool _isDuplicate(_TtsRequest request) {
    if (_currentRequest?.deduplicationKey == request.deduplicationKey) {
      return true;
    }
    if (_queue.any(
      (queued) => queued.deduplicationKey == request.deduplicationKey,
    )) {
      return true;
    }

    final completedAt = _recentlyCompleted[request.deduplicationKey];
    if (completedAt == null) return false;
    return DateTime.now().difference(completedAt) < request.duplicateWindow;
  }

  void _removeReplacedRequests(_TtsRequest incoming) {
    final replacementKey = incoming.replacementKey;
    if (replacementKey == null) return;

    for (final request in _queue.where(
      (request) => request.replacementKey == replacementKey,
    )) {
      request.complete();
    }
    _queue.removeWhere((request) => request.replacementKey == replacementKey);
  }

  void _discardExpiredRequests() {
    final now = DateTime.now();
    _recentlyCompleted.removeWhere(
      (_, completedAt) =>
          now.difference(completedAt) > const Duration(minutes: 1),
    );

    for (final request in _queue.where((request) => request.isExpired)) {
      request.complete();
    }
    _queue.removeWhere((request) => request.isExpired);
  }

  bool _isSafetyPriority(TtsPriority priority) {
    return priority == TtsPriority.warning || priority == TtsPriority.critical;
  }

  Duration _defaultMaxAge(TtsPriority priority) {
    return switch (priority) {
      TtsPriority.low => const Duration(seconds: 8),
      TtsPriority.normal => const Duration(seconds: 12),
      TtsPriority.navigation => const Duration(seconds: 8),
      TtsPriority.warning => const Duration(seconds: 15),
      TtsPriority.critical => const Duration(seconds: 30),
    };
  }
}

class _TtsRequest {
  _TtsRequest({
    required this.sequence,
    required this.text,
    required this.priority,
    required this.deduplicationKey,
    required this.replacementKey,
    required this.expiresAt,
    required this.duplicateWindow,
  });

  final int sequence;
  final String text;
  final TtsPriority priority;
  final String deduplicationKey;
  final String? replacementKey;
  final DateTime expiresAt;
  final Duration duplicateWindow;
  final Completer<void> _completer = Completer<void>();

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  Future<void> get done => _completer.future;

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  _TtsRequest copyForRetry({required int sequence}) {
    return _TtsRequest(
      sequence: sequence,
      text: text,
      priority: priority,
      deduplicationKey: deduplicationKey,
      replacementKey: replacementKey,
      expiresAt: expiresAt,
      duplicateWindow: duplicateWindow,
    );
  }
}
