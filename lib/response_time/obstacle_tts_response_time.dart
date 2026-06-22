// Response time measurement: Obstacle detection -> TTS voice output
//
// Mengukur 5 segmen latency end-to-end:
//   Pi->BLE       : Pi kirim data -> Flutter terima via BLE
//   BLE->TTS call : Flutter terima -> speakSafe() dipanggil (Dart processing, ~0ms)
//   Queue wait    : speakSafe() dipanggil -> giliran TTS tiba (_tts.speak() dipanggil)
//   TTS engine    : _tts.speak() dipanggil -> suara benar-benar keluar dari speaker
//   Total         : Pi -> suara keluar (end-to-end)
//
// HOW TO USE di navigation_screen.dart:
//   initState:
//     TTSService.onSpeechStartHook = ObstacleTtsTimer.onTtsStart;
//     TTSService.onSpeechSendHook  = ObstacleTtsTimer.onTtsSend;
//   dispose:
//     TTSService.onSpeechStartHook = null;
//     TTSService.onSpeechSendHook  = null;
//   sensorDataStream.listen:
//     ObstacleTtsTimer.onBleData(data.status, data.timestamp)
//   _handleSensorTts sebelum speakSafe():
//     ObstacleTtsTimer.onTtsCall(message)
//
// MELIHAT HASIL (terminal kedua saat app berjalan):
//   & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat -c ; & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat flutter:V *:S | Select-String "RT_OBSTACLE"
//
// CATATAN: Akurasi Pi->BLE bergantung pada sinkronisasi NTP antara Pi dan HP.

import 'package:flutter/foundation.dart';

class ObstacleTtsTimer {
  ObstacleTtsTimer._();

  static DateTime? _piTimestamp;
  static DateTime? _bleArrivalTime;
  static DateTime? _ttsCallTime;
  static DateTime? _ttsSendTime;
  static String? _pendingMessage;
  static int? _pendingBleMs;
  static int? _pendingProcessMs;

  static int _sampleCount = 0;
  static int _totalBleMs = 0;
  static int _totalProcessMs = 0;
  static int _totalQueueMs = 0;
  static int _totalEngineMs = 0;
  static int _totalEndToEndMs = 0;
  static int _minEndToEndMs = 999999;
  static int _maxEndToEndMs = 0;

  // Stage 1: data BLE tiba dari Pi
  static void onBleData(String status, DateTime piTimestamp) {
    if (!kDebugMode) return;
    if (status.toLowerCase() == 'safe') return;
    _piTimestamp = piTimestamp;
    _bleArrivalTime = DateTime.now();
  }

  // Stage 2: speakSafe() akan dipanggil
  static void onTtsCall(String message) {
    if (!kDebugMode) return;
    final tBle = _bleArrivalTime;
    final tPi = _piTimestamp;
    if (tBle == null || tPi == null) return;

    final now = DateTime.now();
    _ttsCallTime = now;
    _pendingMessage = message;
    _pendingBleMs = tBle.difference(tPi).inMilliseconds.abs();
    _pendingProcessMs = now.difference(tBle).inMilliseconds;

    _bleArrivalTime = null;
    _piTimestamp = null;
  }

  // Stage 3: _tts.speak() dipanggil (pesan keluar dari antrian TTS)
  static void onTtsSend(String speakingText) {
    if (!kDebugMode) return;
    if (speakingText != _pendingMessage) return;
    _ttsSendTime = DateTime.now();
  }

  // Stage 4: TTS engine mulai bersuara
  static void onTtsStart(String speakingText) {
    if (!kDebugMode) return;
    final tCall = _ttsCallTime;
    final tSend = _ttsSendTime;
    final msg = _pendingMessage;
    final bleMs = _pendingBleMs;
    final processMs = _pendingProcessMs;
    if (tCall == null || tSend == null || msg == null || bleMs == null || processMs == null) return;
    if (speakingText != msg) return;

    final now = DateTime.now();
    final queueMs = tSend.difference(tCall).inMilliseconds;
    final engineMs = now.difference(tSend).inMilliseconds;
    final totalMs = bleMs + processMs + queueMs + engineMs;

    _ttsCallTime = null;
    _ttsSendTime = null;
    _pendingMessage = null;
    _pendingBleMs = null;
    _pendingProcessMs = null;

    _sampleCount++;
    _totalBleMs += bleMs;
    _totalProcessMs += processMs;
    _totalQueueMs += queueMs;
    _totalEngineMs += engineMs;
    _totalEndToEndMs += totalMs;
    if (totalMs < _minEndToEndMs) _minEndToEndMs = totalMs;
    if (totalMs > _maxEndToEndMs) _maxEndToEndMs = totalMs;

    debugPrint(
      '[RT_OBSTACLE] #$_sampleCount | '
      'Pi->BLE: ${bleMs}ms | '
      'BLE->TTS call: ${processMs}ms | '
      'Queue wait: ${queueMs}ms | '
      'TTS engine: ${engineMs}ms | '
      'Total: ${totalMs}ms | '
      'msg: "$msg"',
    );

    if (_sampleCount % 10 == 0) _printSummary();
  }

  static void printSummary() => _printSummary();

  static void _printSummary() {
    if (_sampleCount == 0) {
      debugPrint('[RT_OBSTACLE] Belum ada data.');
      return;
    }
    final avgBle = (_totalBleMs / _sampleCount).round();
    final avgProcess = (_totalProcessMs / _sampleCount).round();
    final avgQueue = (_totalQueueMs / _sampleCount).round();
    final avgEngine = (_totalEngineMs / _sampleCount).round();
    final avgTotal = (_totalEndToEndMs / _sampleCount).round();
    debugPrint('[RT_OBSTACLE] -- SUMMARY ($_sampleCount samples) --');
    debugPrint('[RT_OBSTACLE]   Pi->BLE      : avg ${avgBle}ms');
    debugPrint('[RT_OBSTACLE]   BLE->TTS call: avg ${avgProcess}ms');
    debugPrint('[RT_OBSTACLE]   Queue wait   : avg ${avgQueue}ms');
    debugPrint('[RT_OBSTACLE]   TTS engine   : avg ${avgEngine}ms');
    debugPrint('[RT_OBSTACLE]   Total        : avg ${avgTotal}ms  (min: ${_minEndToEndMs}ms, max: ${_maxEndToEndMs}ms)');
  }

  static void reset() {
    _piTimestamp = null;
    _bleArrivalTime = null;
    _ttsCallTime = null;
    _ttsSendTime = null;
    _pendingMessage = null;
    _pendingBleMs = null;
    _pendingProcessMs = null;
    _sampleCount = 0;
    _totalBleMs = 0;
    _totalProcessMs = 0;
    _totalQueueMs = 0;
    _totalEngineMs = 0;
    _totalEndToEndMs = 0;
    _minEndToEndMs = 999999;
    _maxEndToEndMs = 0;
    debugPrint('[RT_OBSTACLE] Timer direset.');
  }
}
