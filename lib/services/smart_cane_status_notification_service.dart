import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/constants.dart';
import 'smart_cane_ble_service.dart';
import 'tts_service.dart';

enum _SmartCaneRuntimeState { disconnected, connecting, waiting, ready }

enum _SmartCaneHazardLevel { safe, warning, danger }

enum _SmartCaneBatteryLevel { normal, low, critical }

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
  String? _lastAnnouncedHazardObject;
  String? _lastAnnouncedGuidanceDecision;
  DateTime? _safePathDetectedAt;
  bool _wasNavigationHazardAnnouncementsEnabled = false;
  _SmartCaneBatteryLevel _lastBatteryLevel = _SmartCaneBatteryLevel.normal;

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

  Future<void> beginStartupFlow({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isStarted || _isStartupFlowActive) return;

    _isStartupFlowActive = true;
    _hasAnnouncedConnecting = false;
    _lastState = _currentState;

    if (_lastState == _SmartCaneRuntimeState.ready) {
      _finishStartupFlow();
      return;
    }

    if (_lastState == _SmartCaneRuntimeState.waiting) {
      _announceConnected();
    } else if (_lastState == _SmartCaneRuntimeState.connecting) {
      _announceConnecting();
    } else {
      final rememberedCaneRemoteId = await _bleService
          .getRememberedCaneRemoteId();
      if (!_isStartupFlowActive) return;

      if (rememberedCaneRemoteId == null) {
        _finishStartupFlow();
        _announceNoRememberedCane();
        return;
      }

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
    _lastAnnouncedHazardObject = null;
    _lastAnnouncedGuidanceDecision = null;
    _safePathDetectedAt = null;
    _wasNavigationHazardAnnouncementsEnabled = false;
    _lastBatteryLevel = _SmartCaneBatteryLevel.normal;
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
    _evaluateBatteryAlert();

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
      if (_isStartupFlowActive) {
        _announceConnected();
      }
      return;
    }

    if (currentState == _SmartCaneRuntimeState.ready) {
      final shouldAnnounceReady = _isStartupFlowActive;
      _finishStartupFlow();
      if (shouldAnnounceReady) {
        _announceReady();
      }
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
    final announcementsEnabled =
        _bleService.navigationHazardAnnouncementsEnabled;
    if (!announcementsEnabled || !_bleService.isSmartCaneReady) {
      if (_wasNavigationHazardAnnouncementsEnabled) {
        unawaited(_ttsService.cancelByReplacementKey('smart-cane-hazard'));
      }
      _wasNavigationHazardAnnouncementsEnabled = false;
      _resetHazardState();
      return;
    }

    _wasNavigationHazardAnnouncementsEnabled = true;
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
      _announceSafePathWhenStable();
      return;
    }

    _safePathDetectedAt = null;
    final now = DateTime.now();
    final objectLabel = sensorData.detectedObjectLabel;
    final guidanceDecision = sensorData.guidanceDecisionText;
    final levelChanged = currentLevel != _lastHazardLevel;
    final objectChanged =
        objectLabel != null && objectLabel != _lastAnnouncedHazardObject;
    final decisionChanged =
        guidanceDecision != null &&
        guidanceDecision != _lastAnnouncedGuidanceDecision;
    final lastAnnouncementAt = _lastHazardAnnouncementAt;
    final repeatIntervalElapsed =
        lastAnnouncementAt == null ||
        now.difference(lastAnnouncementAt) >= const Duration(seconds: 8);

    if (!levelChanged &&
        !objectChanged &&
        !decisionChanged &&
        !repeatIntervalElapsed) {
      return;
    }

    _lastHazardLevel = currentLevel;
    _lastHazardAnnouncementAt = now;
    _lastAnnouncedHazardObject = objectLabel;
    _lastAnnouncedGuidanceDecision = guidanceDecision;

    _queueTts(
      _hazardAnnouncement(currentLevel, objectLabel, guidanceDecision),
      priority: currentLevel == _SmartCaneHazardLevel.danger
          ? TtsPriority.critical
          : TtsPriority.warning,
      replacementKey: 'smart-cane-hazard',
    );
  }

  void _evaluateBatteryAlert() {
    final batteryData = _bleService.latestBatteryData;
    if (!_bleService.isConnected || batteryData == null) {
      _lastBatteryLevel = _SmartCaneBatteryLevel.normal;
      return;
    }

    final percentage = batteryData.percentage;
    final currentLevel = percentage <= 10
        ? _SmartCaneBatteryLevel.critical
        : percentage <= 20
        ? _SmartCaneBatteryLevel.low
        : _SmartCaneBatteryLevel.normal;

    if (currentLevel == _SmartCaneBatteryLevel.normal) {
      if (percentage >= 25) {
        _lastBatteryLevel = _SmartCaneBatteryLevel.normal;
      }
      return;
    }

    if (currentLevel.index <= _lastBatteryLevel.index) return;
    _lastBatteryLevel = currentLevel;

    final isCritical = currentLevel == _SmartCaneBatteryLevel.critical;
    final message = isCritical
        ? 'Baterai SmartCane tersisa $percentage persen. Segera lakukan pengisian daya.'
        : 'Baterai SmartCane rendah, tersisa $percentage persen. Segera lakukan pengisian daya.';

    _showSnackBar(
      message: message,
      color: isCritical ? AppColors.error : AppColors.warning,
      icon: isCritical
          ? Icons.battery_alert_rounded
          : Icons.battery_2_bar_rounded,
    );
    _queueTts(
      message,
      priority: isCritical ? TtsPriority.critical : TtsPriority.warning,
      replacementKey: 'smart-cane-battery',
    );
  }

  String _hazardAnnouncement(
    _SmartCaneHazardLevel level,
    String? objectLabel,
    String? guidanceDecision,
  ) {
    final prefix = level == _SmartCaneHazardLevel.danger
        ? 'Bahaya'
        : 'Hati-hati';
    final hazardMessage = objectLabel == null
        ? '$prefix, hambatan terdeteksi.'
        : '$prefix, $objectLabel terdeteksi sebagai hambatan.';
    if (guidanceDecision == null) return hazardMessage;
    return '$hazardMessage $guidanceDecision.';
  }

  void _announceSafePathWhenStable() {
    if (_lastHazardLevel == _SmartCaneHazardLevel.safe) {
      _safePathDetectedAt = null;
      return;
    }

    final now = DateTime.now();
    final safePathDetectedAt = _safePathDetectedAt;
    if (safePathDetectedAt == null) {
      _safePathDetectedAt = now;
      return;
    }

    if (now.difference(safePathDetectedAt) <
        const Duration(milliseconds: 1500)) {
      return;
    }

    _resetHazardState();
    _queueTts(
      'Jalur sudah aman. Silakan lanjutkan perjalanan.',
      priority: TtsPriority.warning,
      replacementKey: 'smart-cane-hazard',
    );
  }

  void _resetHazardState() {
    _lastHazardLevel = _SmartCaneHazardLevel.safe;
    _lastHazardAnnouncementAt = null;
    _lastAnnouncedHazardObject = null;
    _lastAnnouncedGuidanceDecision = null;
    _safePathDetectedAt = null;
  }

  void _announceNoRememberedCane() {
    const message =
        'SmartCane belum terhubung. Buka menu Koneksi untuk menghubungkan SmartCane.';
    _showSnackBar(
      message:
          'SmartCane belum terhubung. Buka menu Koneksi untuk menghubungkan SmartCane.',
      color: AppColors.warning,
      icon: Icons.bluetooth_disabled_rounded,
    );
    _queueTts(message);
  }

  void _announceConnecting() {
    if (_hasAnnouncedConnecting) return;
    _hasAnnouncedConnecting = true;

    const message = 'Menghubungkan ulang ke SmartCane.';
    _showSnackBar(
      message: 'Menghubungkan ulang ke SmartCane...',
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
    const message =
        'Koneksi SmartCane terputus. Ucapkan hubungkan ulang SmartCane untuk mencoba kembali.';
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

  void _queueTts(
    String message, {
    TtsPriority priority = TtsPriority.normal,
    String? replacementKey,
  }) {
    if (priority == TtsPriority.warning || priority == TtsPriority.critical) {
      _announcementGeneration++;
      _announcementQueue = Future<void>.value();
    }

    final generation = _announcementGeneration;
    _announcementQueue = _announcementQueue
        .then((_) {
          if (generation != _announcementGeneration) {
            return Future<void>.value();
          }
          return _ttsService.speak(
            message,
            priority: priority,
            replacementKey: replacementKey,
          );
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
