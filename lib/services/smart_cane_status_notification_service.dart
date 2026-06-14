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

  static const _hazardRepeatInterval = Duration(seconds: 5);

  Timer? _statusTimer;
  Timer? _startupTimeoutTimer;
  Timer? _waitingSnackBarTimer;
  final List<String> _pendingStartupAnnouncements = [];
  _SmartCaneRuntimeState? _lastState;
  Future<void> _announcementQueue = Future<void>.value();
  int _announcementGeneration = 0;
  bool _isStarted = false;
  bool _isStartupFlowActive = false;
  bool _wentThroughConnecting = false;
  _SmartCaneHazardLevel _lastHazardLevel = _SmartCaneHazardLevel.safe;
  DateTime? _lastHazardAnnouncementAt;
  String? _lastAnnouncedHazardObject;
  String? _lastAnnouncedGuidanceDecision;
  DateTime? _safePathDetectedAt;
  bool _wasNavigationHazardAnnouncementsEnabled = false;
  _SmartCaneBatteryLevel _lastBatteryLevel = _SmartCaneBatteryLevel.normal;
  bool _isPermissionsReady = false;
  bool _batteryCheckPending = false;

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
    _wentThroughConnecting = false;
    _lastState = _currentState;

    if (_lastState == _SmartCaneRuntimeState.ready) {
      _finishStartupFlow();
      _queueStartupTts(
        'SmartCane berhasil terhubung.',
        onBeforeSpeak: () => _showSnackBar(
          message: 'SmartCane berhasil terhubung.',
          color: AppColors.primary,
          icon: Icons.bluetooth_connected_rounded,
          duration: const Duration(seconds: 3),
        ),
      );
      // Tidak perlu "Menunggu sistem siap." karena sudah langsung ready.
      // Baterai diumumkan di _announceReady() setelah "siap digunakan".
      _announceReady();
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

  /// Dipanggil setelah semua permission (mic, GPS, dll.) diberikan oleh pengguna.
  /// Sebelum ini dipanggil, notifikasi baterai (snackbar + TTS) tidak akan muncul
  /// agar tidak mengganggu alur permintaan izin di home screen.
  void markPermissionsReady() {
    _isPermissionsReady = true;
  }

  /// Safety net untuk manual BLE pairing pertama kali. ChangeNotifier listener
  /// di start() sudah menangani transisi state secara reaktif, tapi metode ini
  /// memastikan sequence tetap ter-trigger di edge case.
  ///
  /// Aman dipanggil berulang — jika listener sudah menangkap transisi
  /// (_lastState == _currentState), metode ini langsung return tanpa efek.
  void forceBeginStartupFlowIfNeeded() {
    if (!_isStarted || !_isPermissionsReady) return;
    if (_isStartupFlowActive) return;
    final current = _currentState;
    if (current == _SmartCaneRuntimeState.disconnected) return;
    // Jika _lastState sudah sama dengan _currentState, listener sudah
    // memproses transisi ini — tidak perlu trigger ulang.
    if (_lastState == current) return;
    unawaited(beginStartupFlow());
  }

  void stop() {
    if (!_isStarted) return;
    _isStarted = false;
    _isPermissionsReady = false;
    _statusTimer?.cancel();
    _statusTimer = null;
    _startupTimeoutTimer?.cancel();
    _startupTimeoutTimer = null;
    _waitingSnackBarTimer?.cancel();
    _waitingSnackBarTimer = null;
    _pendingStartupAnnouncements.clear();
    _bleService.removeListener(_evaluateStatus);
    _lastState = null;
    _isStartupFlowActive = false;
    _wentThroughConnecting = false;
    _batteryCheckPending = false;
    _fullResetHazardState();
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

    // Semua announcement (snackbar + TTS) ditahan sampai permission flow selesai.
    // State tetap ditracking di atas agar tidak ada missed transition setelah
    // markPermissionsReady() dipanggil.
    if (!_isPermissionsReady) return;

    if (currentState == _SmartCaneRuntimeState.connecting) {
      // Reconnect setelah disconnect — aktifkan startup flow baru.
      if (!_isStartupFlowActive &&
          previousState == _SmartCaneRuntimeState.disconnected) {
        _activateReconnectFlow();
      }
      if (_isStartupFlowActive) {
        _announceConnecting();
      }
      return;
    }

    if (currentState == _SmartCaneRuntimeState.waiting) {
      // Langsung ke waiting tanpa melalui connecting (atau startup belum aktif).
      if (!_isStartupFlowActive &&
          (previousState == _SmartCaneRuntimeState.disconnected ||
              previousState == _SmartCaneRuntimeState.connecting)) {
        _activateReconnectFlow();
      }
      if (_isStartupFlowActive) {
        _announceConnected();
      }
      return;
    }

    if (currentState == _SmartCaneRuntimeState.ready) {
      // Langsung ready tanpa melalui waiting — announce sequence penuh.
      if (!_isStartupFlowActive &&
          (previousState == _SmartCaneRuntimeState.disconnected ||
              previousState == _SmartCaneRuntimeState.connecting ||
              previousState == _SmartCaneRuntimeState.waiting)) {
        _activateReconnectFlow();
        _finishStartupFlow();
        if (_wentThroughConnecting) {
          _wentThroughConnecting = false;
          final connectingGeneration = _announcementGeneration;
          _announcementQueue = _announcementQueue
              .then((_) async {
                if (connectingGeneration != _announcementGeneration) return;
                if (_currentState == _SmartCaneRuntimeState.ready) return;
                _showSnackBar(
                  message: 'Menghubungkan ulang ke SmartCane...',
                  color: AppColors.primary,
                  icon: Icons.bluetooth_searching_rounded,
                );
                await _ttsService.speak('Menghubungkan ulang ke SmartCane.');
              })
              .catchError((Object error, StackTrace stackTrace) {
                debugPrint('[SMARTCANE-STATUS] TTS connecting gagal: $error');
              });
        }
        _queueStartupTts(
          'SmartCane berhasil terhubung.',
          onBeforeSpeak: () => _showSnackBar(
            message: 'SmartCane berhasil terhubung.',
            color: AppColors.primary,
            icon: Icons.bluetooth_connected_rounded,
            duration: const Duration(seconds: 3),
          ),
        );
        _announceReady();
        return;
      }
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

  void _activateReconnectFlow() {
    _isStartupFlowActive = true;
    _wentThroughConnecting = false;
    _startupTimeoutTimer?.cancel();
    _startupTimeoutTimer = Timer(
      const Duration(seconds: 30),
      _handleStartupTimeout,
    );
  }

  void _evaluateHazardAlert() {
    final announcementsEnabled =
        _bleService.navigationHazardAnnouncementsEnabled;
    if (!announcementsEnabled || !_bleService.isSmartCaneReady) {
      if (_wasNavigationHazardAnnouncementsEnabled) {
        unawaited(_ttsService.cancelByReplacementKey('smart-cane-hazard'));
      }
      _wasNavigationHazardAnnouncementsEnabled = false;
      _fullResetHazardState();
      return;
    }

    _wasNavigationHazardAnnouncementsEnabled = true;
    final sensorData = _bleService.latestSensorData;
    if (!_bleService.isConnected ||
        !_bleService.isSensorRunning ||
        sensorData == null) {
      _resetHazardLevel();
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

    // Eskalasi (warning → danger) selalu diumumkan — prioritas keselamatan.
    final isEscalation = currentLevel.index > _lastHazardLevel.index;
    final objectChanged =
        objectLabel != null && objectLabel != _lastAnnouncedHazardObject;
    final decisionChanged =
        guidanceDecision != null &&
        guidanceDecision != _lastAnnouncedGuidanceDecision;
    final lastAt = _lastHazardAnnouncementAt;
    final cooldownElapsed =
        lastAt == null ||
        now.difference(lastAt) >= _hazardRepeatInterval;

    // Suppres jika bukan eskalasi, tidak ada info baru, dan cooldown belum habis.
    // Ini mencegah spam TTS saat sensor terus mendeteksi bahaya yang sama.
    if (!isEscalation && !objectChanged && !decisionChanged && !cooldownElapsed) {
      _lastHazardLevel = currentLevel;
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

  // Dipanggil dari _announceReady() agar informasi baterai muncul SETELAH
  // "SmartCane berhasil terhubung." dan "SmartCane siap digunakan."
  //
  // Menggunakan chain biasa (tanpa reset queue) sehingga TTS baterai mengantri
  // setelah pesan startup yang sudah ada di queue. Flag _batteryCheckPending
  // menahan _evaluateBatteryAlert() (timer) agar tidak mendahului antrian ini.
  void _checkAndQueueBatteryOnConnect() {
    if (!_isPermissionsReady) return;
    final batteryData = _bleService.latestBatteryData;
    if (batteryData == null) {
      // Data baterai belum diterima — tunggu maks. 3 detik dalam antrian.
      _batteryCheckPending = true;
      final generation = _announcementGeneration;
      _announcementQueue = _announcementQueue
          .then((_) async {
            // Clear flag di awal agar selalu ter-release walau chain dibatalkan.
            _batteryCheckPending = false;
            if (generation != _announcementGeneration) return;
            SmartCaneBatteryData? received;
            try {
              received = await _bleService.batteryDataStream
                  .first
                  .timeout(const Duration(seconds: 3));
            } catch (_) {
              return;
            }
            if (generation != _announcementGeneration) return;

            final pct = received.percentage;
            final level = pct <= 10
                ? _SmartCaneBatteryLevel.critical
                : pct <= 20
                ? _SmartCaneBatteryLevel.low
                : _SmartCaneBatteryLevel.normal;

            if (level == _SmartCaneBatteryLevel.normal) return;
            if (level.index <= _lastBatteryLevel.index) return;

            _lastBatteryLevel = level;

            final isCritical = level == _SmartCaneBatteryLevel.critical;
            final msg = isCritical
                ? 'Baterai SmartCane tersisa $pct persen. Segera lakukan pengisian daya.'
                : 'Baterai SmartCane rendah, tersisa $pct persen. Segera lakukan pengisian daya.';

            _showSnackBar(
              message: msg,
              color: isCritical ? AppColors.error : AppColors.warning,
              icon: isCritical
                  ? Icons.battery_alert_rounded
                  : Icons.battery_2_bar_rounded,
            );
            await _ttsService.speak(
              msg,
              priority: isCritical ? TtsPriority.critical : TtsPriority.warning,
              replacementKey: 'smart-cane-battery',
            );
          })
          .catchError((Object error, StackTrace stackTrace) {
            _batteryCheckPending = false;
            debugPrint(
              '[SMARTCANE-STATUS] Battery wait on connect gagal: $error',
            );
          });
      return;
    }

    final percentage = batteryData.percentage;
    final currentLevel = percentage <= 10
        ? _SmartCaneBatteryLevel.critical
        : percentage <= 20
        ? _SmartCaneBatteryLevel.low
        : _SmartCaneBatteryLevel.normal;

    if (currentLevel == _SmartCaneBatteryLevel.normal) return;
    if (currentLevel.index <= _lastBatteryLevel.index) return;

    // Set level segera agar _evaluateBatteryAlert() tidak fire duplikat
    // seandainya flag di-clear lebih awal karena chain dibatalkan.
    _lastBatteryLevel = currentLevel;
    _batteryCheckPending = true;

    final isCritical = currentLevel == _SmartCaneBatteryLevel.critical;
    final message = isCritical
        ? 'Baterai SmartCane tersisa $percentage persen. Segera lakukan pengisian daya.'
        : 'Baterai SmartCane rendah, tersisa $percentage persen. Segera lakukan pengisian daya.';

    // Chain langsung ke queue tanpa reset — baterai berbunyi setelah "siap digunakan".
    final generation = _announcementGeneration;
    _announcementQueue = _announcementQueue
        .then((_) async {
          // Clear flag di awal agar selalu ter-release walau chain dibatalkan.
          _batteryCheckPending = false;
          if (generation != _announcementGeneration) return;
          _showSnackBar(
            message: message,
            color: isCritical ? AppColors.error : AppColors.warning,
            icon: isCritical
                ? Icons.battery_alert_rounded
                : Icons.battery_2_bar_rounded,
          );
          await _ttsService.speak(
            message,
            priority: isCritical ? TtsPriority.critical : TtsPriority.warning,
            replacementKey: 'smart-cane-battery',
          );
        })
        .catchError((Object error, StackTrace stackTrace) {
          _batteryCheckPending = false;
          debugPrint('[SMARTCANE-STATUS] Battery on-connect TTS gagal: $error');
        });
  }

  void _evaluateBatteryAlert() {
    if (!_isPermissionsReady) return;
    // Tahan selama _checkAndQueueBatteryOnConnect() masih antri di queue agar
    // timer tidak mendahului urutan "siap digunakan" → baterai.
    if (_batteryCheckPending) return;
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

    _queueTts(
      message,
      priority: isCritical ? TtsPriority.critical : TtsPriority.warning,
      replacementKey: 'smart-cane-battery',
      onBeforeSpeak: () => _showSnackBar(
        message: message,
        color: isCritical ? AppColors.error : AppColors.warning,
        icon: isCritical
            ? Icons.battery_alert_rounded
            : Icons.battery_2_bar_rounded,
      ),
    );
    _requeuePendingStartupAnnouncements();
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

    // Jalur benar-benar bersih: reset penuh termasuk cooldown agar peringatan
    // berikutnya (rintangan baru) tetap diumumkan.
    _fullResetHazardState();
    _queueTts(
      'Jalur sudah aman. Silakan lanjutkan perjalanan.',
      priority: TtsPriority.warning,
      replacementKey: 'smart-cane-hazard',
    );
  }

  // Reset level & konteks saja; cooldown (_lastHazardAnnouncementAt) tetap
  // dijaga agar oscillasi safe/warning singkat tidak memicu spam TTS.
  void _resetHazardLevel() {
    _lastHazardLevel = _SmartCaneHazardLevel.safe;
    _lastAnnouncedHazardObject = null;
    _lastAnnouncedGuidanceDecision = null;
    _safePathDetectedAt = null;
  }

  // Reset penuh termasuk cooldown — hanya dipanggil setelah jalur aman
  // dikonfirmasi atau service dihentikan/dinonaktifkan.
  void _fullResetHazardState() {
    _lastHazardLevel = _SmartCaneHazardLevel.safe;
    _lastHazardAnnouncementAt = null;
    _lastAnnouncedHazardObject = null;
    _lastAnnouncedGuidanceDecision = null;
    _safePathDetectedAt = null;
  }

  void _announceNoRememberedCane() {
    const message =
        'SmartCane belum terhubung. Buka menu Koneksi untuk menghubungkan SmartCane.';
    _queueTts(
      message,
      onBeforeSpeak: () => _showSnackBar(
        message: message,
        color: AppColors.warning,
        icon: Icons.bluetooth_disabled_rounded,
      ),
    );
  }

  void _announceConnecting() {
    if (_wentThroughConnecting) return;
    _wentThroughConnecting = true;
    // Koneksi berjalan di background — tidak ada snackbar/TTS saat ini.
    // Pesan "Menghubungkan ulang" akan diputar di _announceConnected()
    // tepat sebelum "SmartCane berhasil terhubung." jika koneksi berhasil.
  }

  void _announceConnected() {
    // Jika sebelumnya melewati state connecting (proses berlangsung di
    // background), munculkan snackbar+TTS "menghubungkan" tepat sebelum
    // "berhasil terhubung" — hanya jika saat giliran queue tiba SmartCane
    // belum ready (kondisi sama seperti "Menunggu sistem siap.").
    if (_wentThroughConnecting) {
      _wentThroughConnecting = false;
      final connectingGeneration = _announcementGeneration;
      _announcementQueue = _announcementQueue
          .then((_) async {
            if (connectingGeneration != _announcementGeneration) return;
            if (_currentState == _SmartCaneRuntimeState.ready) return;
            _showSnackBar(
              message: 'Menghubungkan ulang ke SmartCane...',
              color: AppColors.primary,
              icon: Icons.bluetooth_searching_rounded,
            );
            await _ttsService.speak('Menghubungkan ulang ke SmartCane.');
          })
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint('[SMARTCANE-STATUS] TTS connecting gagal: $error');
          });
    }

    _queueStartupTts(
      'SmartCane berhasil terhubung.',
      onBeforeSpeak: () => _showSnackBar(
        message: 'SmartCane berhasil terhubung.',
        color: AppColors.primary,
        icon: Icons.bluetooth_connected_rounded,
        duration: const Duration(seconds: 3),
      ),
    );

    _waitingSnackBarTimer?.cancel();
    _waitingSnackBarTimer = Timer(const Duration(seconds: 3), () {
      _waitingSnackBarTimer = null;
      if (_isStarted && _currentState == _SmartCaneRuntimeState.waiting) {
        _showSnackBar(
          message: 'Menunggu sistem siap.',
          color: AppColors.primary,
          icon: Icons.hourglass_empty_rounded,
        );
      }
    });
    // Hanya ucapkan "Menunggu sistem siap." jika saat giliran TTS tiba
    // sistem belum ready — jika sudah ready, _announceReady() akan langsung
    // diucapkan sesudah "berhasil terhubung." tanpa pesan tunggu ini.
    _queueStartupTtsIf(
      'Menunggu sistem siap.',
      condition: () => _currentState == _SmartCaneRuntimeState.waiting,
    );
  }

  void _announceReady() {
    const message = 'SmartCane siap digunakan.';
    _queueStartupTts(
      message,
      onBeforeSpeak: () => _showSnackBar(
        message: message,
        color: AppColors.success,
        icon: Icons.check_circle_rounded,
      ),
    );
    // Informasi baterai diumumkan setelah "siap digunakan" agar urutan jelas.
    _checkAndQueueBatteryOnConnect();
  }

  void _announceDisconnected() {
    const message = 'Koneksi SmartCane terputus.';
    _queueTts(
      message,
      onBeforeSpeak: () => _showSnackBar(
        message: message,
        color: AppColors.error,
        icon: Icons.bluetooth_disabled_rounded,
      ),
    );
  }

  void _handleStartupTimeout() {
    if (!_isStarted ||
        !_isStartupFlowActive ||
        _currentState == _SmartCaneRuntimeState.ready) {
      return;
    }

    _pendingStartupAnnouncements.clear();
    _finishStartupFlow();

    final isConnected = _bleService.isConnected;
    final message = isConnected
        ? 'SmartCane belum siap. Pastikan sensor dan model berjalan.'
        : 'SmartCane belum terhubung. Pastikan tongkat aktif dan berada di dekat Anda.';

    _queueTts(
      message,
      onBeforeSpeak: () => _showSnackBar(
        message: message,
        color: AppColors.warning,
        icon: Icons.warning_amber_rounded,
      ),
    );
  }

  void _finishStartupFlow() {
    _isStartupFlowActive = false;
    _startupTimeoutTimer?.cancel();
    _startupTimeoutTimer = null;
    _waitingSnackBarTimer?.cancel();
    _waitingSnackBarTimer = null;
  }

  // Antrian TTS khusus startup: melacak pesan yang belum diucapkan agar bisa
  // di-replay jika diinterupsi oleh TTS prioritas tinggi (mis. baterai rendah).
  //
  // Pesan baru dihapus dari pending SETELAH speak selesai dan hanya jika
  // generation masih sama — sehingga pesan yang sedang diucapkan saat diinterupsi
  // tetap tersimpan di pending dan ikut di-replay oleh
  // _requeuePendingStartupAnnouncements().
  //
  // onBeforeSpeak dipanggil tepat sebelum speak — dipakai untuk menampilkan
  // snackbar agar sinkron dengan TTS, bukan lebih awal.
  void _queueStartupTts(String message, {VoidCallback? onBeforeSpeak}) {
    _pendingStartupAnnouncements.add(message);
    final generation = _announcementGeneration;
    _announcementQueue = _announcementQueue
        .then((_) async {
          if (generation != _announcementGeneration) {
            // Diinterupsi sebelum mulai — tetap di pending.
            return;
          }
          onBeforeSpeak?.call();
          await _ttsService.speak(message);
          // Hanya hapus dari pending jika tidak diinterupsi selama speak.
          if (generation == _announcementGeneration) {
            _pendingStartupAnnouncements.remove(message);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[SMARTCANE-STATUS] TTS startup gagal: $error');
        });
  }

  // Varian _queueStartupTts dengan kondisi: pesan hanya diucapkan jika
  // condition() == true saat giliran TTS tiba. Tidak ditambahkan ke pending
  // karena bersifat opsional (tidak perlu di-replay).
  void _queueStartupTtsIf(String message, {required bool Function() condition}) {
    final generation = _announcementGeneration;
    _announcementQueue = _announcementQueue
        .then((_) async {
          if (generation != _announcementGeneration) return;
          if (!condition()) return;
          await _ttsService.speak(message);
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[SMARTCANE-STATUS] TTS startup kondisional gagal: $error');
        });
  }

  // Dipanggil setelah TTS prioritas tinggi di-queue (mis. baterai) agar
  // pesan startup yang terdrop tetap terucap sesudahnya.
  void _requeuePendingStartupAnnouncements() {
    if (_pendingStartupAnnouncements.isEmpty) return;
    final pending = List<String>.from(_pendingStartupAnnouncements);
    for (final msg in pending) {
      final generation = _announcementGeneration;
      _announcementQueue = _announcementQueue
          .then((_) async {
            if (generation != _announcementGeneration) {
              return;
            }
            await _ttsService.speak(msg);
            if (generation == _announcementGeneration) {
              _pendingStartupAnnouncements.remove(msg);
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint('[SMARTCANE-STATUS] TTS startup replay gagal: $error');
          });
    }
  }

  // onBeforeSpeak dipanggil tepat sebelum speak — dipakai untuk menampilkan
  // snackbar agar sinkron dengan TTS, bukan lebih awal.
  void _queueTts(
    String message, {
    TtsPriority priority = TtsPriority.normal,
    String? replacementKey,
    VoidCallback? onBeforeSpeak,
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
          onBeforeSpeak?.call();
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
    Duration duration = const Duration(seconds: 4),
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
          duration: duration,
        ),
      );
  }
}
