import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/constants.dart';
import 'smart_cane_ble_service.dart';
import 'tts_service.dart';

enum _SmartCaneRuntimeState { disconnected, connecting, waiting, ready }

enum _SmartCaneHazardLevel { safe, warning, danger }

class SmartCaneStatusNotificationService {
  SmartCaneStatusNotificationService({
    required this.scaffoldMessengerKey,
    SmartCaneBleService? bleService,
    TTSService? ttsService,
  }) : _bleService = bleService ?? SmartCaneBleService.instance,
       _ttsService = ttsService ?? TTSService();

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  final SmartCaneBleService _bleService;
  final TTSService _ttsService;

  Timer? _statusTimer;
  Timer? _startupTimeoutTimer;
  _SmartCaneRuntimeState? _lastState;
  Future<void> _announcementQueue = Future<void>.value();
  int _announcementGeneration = 0;
  bool _isStarted = false;
  bool _isStartupFlowActive = false;
  bool _hasAnnouncedConnecting = false;
  _SmartCaneHazardLevel _lastHazardLevel = _SmartCaneHazardLevel.safe;
  DateTime? _lastHazardAnnouncementAt;

  void start() {
    if (_isStarted) return;
    _isStarted = true;
    _lastState = _currentState;
    _bleService.addListener(_evaluateStatus);
    _statusTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _evaluateStatus(),
    );
  }

  void beginStartupFlow({Duration timeout = const Duration(seconds: 30)}) {
    if (!_isStarted || _isStartupFlowActive) return;

    _isStartupFlowActive = true;
    _hasAnnouncedConnecting = false;
    _lastState = _currentState;
    _announcePreparing();

    if (_lastState == _SmartCaneRuntimeState.ready) {
      _finishStartupFlow();
      _announceReady();
      return;
    }

    if (_lastState == _SmartCaneRuntimeState.waiting) {
      _announceConnected();
    } else if (_lastState == _SmartCaneRuntimeState.connecting) {
      _announceConnecting();
    }

    if (_isStartupFlowActive) {
      _startupTimeoutTimer?.cancel();
      _startupTimeoutTimer = Timer(timeout, _handleStartupTimeout);
    }
  }

  void stop() {
    if (!_isStarted) return;
    _isStarted = false;
    _statusTimer?.cancel();
    _statusTimer = null;
    _startupTimeoutTimer?.cancel();
    _startupTimeoutTimer = null;
    _bleService.removeListener(_evaluateStatus);
    _lastState = null;
    _isStartupFlowActive = false;
    _hasAnnouncedConnecting = false;
    _lastHazardLevel = _SmartCaneHazardLevel.safe;
    _lastHazardAnnouncementAt = null;
  }

  _SmartCaneRuntimeState get _currentState {
    if (!_bleService.isConnected) {
      if (_bleService.isConnecting || _bleService.isAutoConnecting) {
        return _SmartCaneRuntimeState.connecting;
      }
      return _SmartCaneRuntimeState.disconnected;
    }
    if (_bleService.isSmartCaneReady) {
      return _SmartCaneRuntimeState.ready;
    }
    return _SmartCaneRuntimeState.waiting;
  }

  void _evaluateStatus() {
    if (!_isStarted) return;

    _evaluateHazardAlert();

    final currentState = _currentState;
    final previousState = _lastState;
    if (currentState == previousState) return;

    _lastState = currentState;

    if (currentState == _SmartCaneRuntimeState.connecting) {
      if (_isStartupFlowActive) {
        _announceConnecting();
      }
      return;
    }

    if (currentState == _SmartCaneRuntimeState.waiting) {
      _announceConnected();
      return;
    }

    if (currentState == _SmartCaneRuntimeState.ready) {
      _finishStartupFlow();
      _announceReady();
      return;
    }

    if (currentState == _SmartCaneRuntimeState.disconnected &&
        previousState != null &&
        previousState != _SmartCaneRuntimeState.disconnected &&
        previousState != _SmartCaneRuntimeState.connecting) {
      _announceDisconnected();
    }
  }

  void _evaluateHazardAlert() {
    final sensorData = _bleService.latestSensorData;
    if (!_bleService.isConnected ||
        !_bleService.isSensorRunning ||
        sensorData == null) {
      _resetHazardState();
      return;
    }

    final currentLevel = sensorData.isDanger
        ? _SmartCaneHazardLevel.danger
        : sensorData.isWarning
        ? _SmartCaneHazardLevel.warning
        : _SmartCaneHazardLevel.safe;

    if (currentLevel == _SmartCaneHazardLevel.safe) {
      _resetHazardState();
      return;
    }

    final now = DateTime.now();
    final levelChanged = currentLevel != _lastHazardLevel;
    final lastAnnouncementAt = _lastHazardAnnouncementAt;
    final repeatIntervalElapsed =
        lastAnnouncementAt == null ||
        now.difference(lastAnnouncementAt) >= const Duration(seconds: 8);

    if (!levelChanged && !repeatIntervalElapsed) return;

    _lastHazardLevel = currentLevel;
    _lastHazardAnnouncementAt = now;

    _queueTts(
      currentLevel == _SmartCaneHazardLevel.danger
          ? 'Bahaya, hambatan terdeteksi.'
          : 'Hati-hati, hambatan terdeteksi.',
      interrupt: true,
    );
  }

  void _resetHazardState() {
    _lastHazardLevel = _SmartCaneHazardLevel.safe;
    _lastHazardAnnouncementAt = null;
  }

  void _announcePreparing() {
    const message = 'Menyiapkan SmartCane.';
    _showSnackBar(
      message: 'Menyiapkan SmartCane...',
      color: AppColors.primary,
      icon: Icons.settings_input_antenna_rounded,
    );
    _queueTts(message);
  }

  void _announceConnecting() {
    if (_hasAnnouncedConnecting) return;
    _hasAnnouncedConnecting = true;

    const message = 'Menghubungkan ke SmartCane.';
    _showSnackBar(
      message: 'Menghubungkan ke SmartCane...',
      color: AppColors.primary,
      icon: Icons.bluetooth_searching_rounded,
    );
    _queueTts(message);
  }

  void _announceConnected() {
    const message = 'SmartCane terhubung. Menunggu sistem siap.';
    _showSnackBar(
      message: message,
      color: AppColors.primary,
      icon: Icons.bluetooth_connected_rounded,
    );
    _queueTts(message);
  }

  void _announceReady() {
    const message = 'SmartCane siap digunakan.';
    _showSnackBar(
      message: message,
      color: AppColors.success,
      icon: Icons.check_circle_rounded,
    );
    _queueTts(message);
  }

  void _announceDisconnected() {
    const message = 'Koneksi SmartCane terputus.';
    _showSnackBar(
      message: message,
      color: AppColors.error,
      icon: Icons.bluetooth_disabled_rounded,
    );
    _queueTts(message);
  }

  void _handleStartupTimeout() {
    if (!_isStarted ||
        !_isStartupFlowActive ||
        _currentState == _SmartCaneRuntimeState.ready) {
      return;
    }

    _finishStartupFlow();

    final isConnected = _bleService.isConnected;
    final message = isConnected
        ? 'SmartCane belum siap. Pastikan sensor dan model berjalan.'
        : 'SmartCane belum terhubung. Pastikan tongkat aktif dan berada di dekat Anda.';

    _showSnackBar(
      message: message,
      color: AppColors.warning,
      icon: Icons.warning_amber_rounded,
    );
    _queueTts(message);
  }

  void _finishStartupFlow() {
    _isStartupFlowActive = false;
    _startupTimeoutTimer?.cancel();
    _startupTimeoutTimer = null;
  }

  void _queueTts(String message, {bool interrupt = false}) {
    if (interrupt) {
      _announcementGeneration++;
      _announcementQueue = Future<void>.value();
    }

    final generation = _announcementGeneration;
    _announcementQueue = _announcementQueue
        .then((_) {
          if (generation != _announcementGeneration) {
            return Future<void>.value();
          }
          return _ttsService.speak(message);
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[SMARTCANE-STATUS] TTS gagal: $error');
        });
  }

  void _showSnackBar({
    required String message,
    required Color color,
    required IconData icon,
  }) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: color,
          duration: const Duration(seconds: 4),
        ),
      );
  }
}
