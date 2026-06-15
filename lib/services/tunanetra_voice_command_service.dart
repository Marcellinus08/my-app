import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/constants.dart';
import 'smart_cane_ble_service.dart';
import 'sos_service.dart';
import 'stt_service.dart';
import 'tts_service.dart';

class TunaNetraVoiceCommands {
  static DateTime? _lastSosTriggerAt;

  static bool isHomeCommand(String command) {
    final text = command.toLowerCase();
    return text.contains('halaman utama') ||
        text.contains('beranda') ||
        text.contains('home');
  }

  static bool isSettingsCommand(String command) {
    return command.toLowerCase().contains('pengaturan');
  }

  static bool isSosCommand(String command) {
    final text = command
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    const exactCommands = {
      'sos',
      'kirim sos',
      'aktifkan sos',
      'sos darurat',
      'kirim sos darurat',
      'saya darurat',
      'saya butuh bantuan darurat',
      'tolong kirim sos',
    };

    return exactCommands.contains(text) ||
        text.startsWith('kirim sos ') ||
        text.startsWith('aktifkan sos ');
  }

  static bool isReconnectSmartCaneCommand(String command) {
    final text = command.toLowerCase();
    final asksToReconnect =
        text.contains('hubungkan ulang') ||
        text.contains('sambungkan ulang') ||
        text.contains('koneksikan ulang');
    final mentionsCane =
        text.contains('smartcane') ||
        text.contains('smarthcane') ||
        text.contains('tongkat');
    return asksToReconnect && mentionsCane;
  }

  static bool isBackCommand(String command) {
    return command.toLowerCase().contains('kembali');
  }

  static bool isPageStatusCommand(String command) {
    final text = command.toLowerCase();
    return text.contains('status halaman') || text.contains('halaman apa');
  }

  static bool claimSosTrigger({
    Duration cooldown = const Duration(seconds: 5),
  }) {
    final now = DateTime.now();
    final lastTriggerAt = _lastSosTriggerAt;
    if (lastTriggerAt != null && now.difference(lastTriggerAt) < cooldown) {
      return false;
    }

    _lastSosTriggerAt = now;
    return true;
  }
}

mixin TunaNetraHomeVoiceCommandMixin<T extends StatefulWidget> on State<T> {
  final STTService _homeCommandSttService = STTService();
  final TTSService _homeCommandTtsService = TTSService();
  late final String _screenTtsKey = 'screen-tts-${identityHashCode(this)}';
  String? _pageName;
  bool _isHomeCommandSpeaking = false;
  bool _hasHandledHomeCommand = false;
  bool _homeCommandListenerActive = false;
  bool _isStartingHomeCommandListener = false;
  bool _homeCommandListenerEnabled = false;
  bool _isSendingHardwareSos = false;
  StreamSubscription<SmartCaneButtonEvent>? _homeCommandButtonSubscription;

  void startHomeVoiceCommandListener({
    bool isHomePage = false,
    String? openingAnnouncement,
    String? pageName,
    Future<bool> Function(String command)? onCommand,
  }) {
    _pageName = pageName;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _homeCommandListenerEnabled = true;
      _homeCommandButtonSubscription?.cancel();
      _homeCommandButtonSubscription = SmartCaneBleService
          .instance
          .buttonEventStream
          .listen(
            (event) => _handleHomeCommandButtonEvent(
              event,
              isHomePage: isHomePage,
              onCommand: onCommand,
            ),
          );
      _speakOpeningAnnouncement(openingAnnouncement: openingAnnouncement);
    });
  }

  Future<void> _speakOpeningAnnouncement({String? openingAnnouncement}) async {
    if (openingAnnouncement != null && openingAnnouncement.isNotEmpty) {
      _isHomeCommandSpeaking = true;
      await _homeCommandTtsService.speak(
        openingAnnouncement,
        replacementKey: _screenTtsKey,
      );
      _isHomeCommandSpeaking = false;

      if (!mounted) return;
    }
  }

  Future<void> _handleHomeCommandButtonEvent(
    SmartCaneButtonEvent event, {
    required bool isHomePage,
    Future<bool> Function(String command)? onCommand,
  }) async {
    if (!mounted || !_homeCommandListenerEnabled) {
      return;
    }

    if (event.isVoiceAssistantStop) {
      _homeCommandListenerActive = false;
      await _homeCommandSttService.finishListening();
      return;
    }

    if (event.isSos) {
      await _handleSosCommand();
      return;
    }

    if (!event.isVoiceAssistantStart || _isHomeCommandSpeaking) return;

    if (!mounted || !_homeCommandListenerEnabled) return;
    await _homeCommandSttService.stopListening();
    _homeCommandListenerActive = false;
    _hasHandledHomeCommand = false;
    await _startHomeCommandStt(isHomePage: isHomePage, onCommand: onCommand);
  }

  Future<void> _startHomeCommandStt({
    required bool isHomePage,
    Future<bool> Function(String command)? onCommand,
  }) async {
    if (_isStartingHomeCommandListener ||
        _homeCommandListenerActive ||
        _hasHandledHomeCommand ||
        !_homeCommandListenerEnabled ||
        !mounted) {
      return;
    }

    _isStartingHomeCommandListener = true;
    await _homeCommandSttService.startListening(
      (result) {
        if (_isHomeCommandSpeaking || _hasHandledHomeCommand) return;

        final text = result.toLowerCase();
        if (onCommand != null) {
          onCommand(text).then((handled) {
            if (handled) return;
            if (TunaNetraVoiceCommands.isReconnectSmartCaneCommand(text)) {
              _handleReconnectSmartCaneCommand();
              return;
            }
            if (TunaNetraVoiceCommands.isSosCommand(text)) {
              _handleSosCommand();
              return;
            }
            if (TunaNetraVoiceCommands.isBackCommand(text) && !isHomePage) {
              _handleBackVoiceCommand();
              return;
            }
            if (TunaNetraVoiceCommands.isPageStatusCommand(text)) {
              _handlePageStatusVoiceCommand();
              return;
            }
            if (TunaNetraVoiceCommands.isHomeCommand(text)) {
              _handleHomeVoiceCommand(isHomePage: isHomePage);
            }
          });
          return;
        }

        if (TunaNetraVoiceCommands.isReconnectSmartCaneCommand(text)) {
          _handleReconnectSmartCaneCommand();
          return;
        }

        if (TunaNetraVoiceCommands.isSosCommand(text)) {
          _handleSosCommand();
          return;
        }

        if (TunaNetraVoiceCommands.isBackCommand(text) && !isHomePage) {
          _handleBackVoiceCommand();
          return;
        }

        if (TunaNetraVoiceCommands.isPageStatusCommand(text)) {
          _handlePageStatusVoiceCommand();
          return;
        }

        if (!TunaNetraVoiceCommands.isHomeCommand(text)) return;

        _handleHomeVoiceCommand(isHomePage: isHomePage);
      },
      onNoSpeechDetected: () {
        if (!mounted || _isHomeCommandSpeaking) return;
        _isHomeCommandSpeaking = true;
        _homeCommandTtsService
            .speak(
              'Tidak ada suara terdeteksi. Tekan tombol dan coba lagi.',
              replacementKey: _screenTtsKey,
            )
            .whenComplete(() => _isHomeCommandSpeaking = false);
      },
      onStatus: (status) {
        _homeCommandListenerActive = status == 'listening';
      },
      onError: (_) {
        _homeCommandListenerActive = false;
      },
      pauseFor: const Duration(seconds: 5),
      finalResultsOnly: true,
    );
    _isStartingHomeCommandListener = false;
  }

  Future<void> stopHomeVoiceCommandListener() async {
    _hasHandledHomeCommand = true;
    _homeCommandListenerEnabled = false;
    _homeCommandListenerActive = false;
    await _homeCommandButtonSubscription?.cancel();
    _homeCommandButtonSubscription = null;
    await _homeCommandSttService.stopListening();
    unawaited(_homeCommandTtsService.cancelByReplacementKey(_screenTtsKey));
    _hasHandledHomeCommand = false;
  }

  Future<void> _handleSosCommand() async {
    if (_isSendingHardwareSos) return;
    if (!TunaNetraVoiceCommands.claimSosTrigger()) return;

    _isSendingHardwareSos = true;
    _hasHandledHomeCommand = true;
    _homeCommandListenerActive = false;
    await _homeCommandSttService.stopListening();

    try {
      _isHomeCommandSpeaking = true;
      await _homeCommandTtsService.speak(
        'Mengirim SOS darurat',
        replacementKey: _screenTtsKey,
      );
      final result = await SosService().sendSosAlert();
      await Future.delayed(const Duration(milliseconds: 600));
      await _homeCommandTtsService.speak(
        result.spokenMessage,
        replacementKey: _screenTtsKey,
      );
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 600));
      await _homeCommandTtsService.speak(
        'Status SOS, gagal dikirim',
        replacementKey: _screenTtsKey,
      );
    } finally {
      _isHomeCommandSpeaking = false;
      _isSendingHardwareSos = false;
      _hasHandledHomeCommand = false;
    }
  }

  Future<void> _handleReconnectSmartCaneCommand() async {
    if (_hasHandledHomeCommand) return;
    _hasHandledHomeCommand = true;
    _homeCommandListenerActive = false;
    await _homeCommandSttService.stopListening();

    final bleService = SmartCaneBleService.instance;
    _isHomeCommandSpeaking = true;
    try {
      if (bleService.isConnected) {
        await _homeCommandTtsService.speak(
          'SmartCane sudah terhubung.',
          replacementKey: _screenTtsKey,
        );
        return;
      }

      if (bleService.isConnecting || bleService.isAutoConnecting) {
        await _homeCommandTtsService.speak(
          'SmartCane sedang dihubungkan. Mohon tunggu.',
          replacementKey: _screenTtsKey,
        );
        return;
      }

      final rememberedCaneId = await bleService.getRememberedCaneRemoteId();
      if (rememberedCaneId == null) {
        await _homeCommandTtsService.speak(
          'Belum ada SmartCane tersimpan. Buka menu koneksi untuk menghubungkan SmartCane.',
          replacementKey: _screenTtsKey,
        );
        return;
      }

      await _homeCommandTtsService.speak(
        'Mencoba menghubungkan ulang SmartCane.',
        replacementKey: _screenTtsKey,
      );
      await bleService.initializeAutoReconnect(force: true, maxAttempts: 5);

      await _homeCommandTtsService.speak(
        bleService.isConnected
            ? 'SmartCane berhasil terhubung kembali.'
            : 'SmartCane belum dapat terhubung. Pastikan SmartCane menyala dan berada di dekat Anda.',
        replacementKey: _screenTtsKey,
      );
    } finally {
      _isHomeCommandSpeaking = false;
      _hasHandledHomeCommand = false;
    }
  }

  Future<void> _handleBackVoiceCommand() async {
    _hasHandledHomeCommand = true;
    _homeCommandListenerActive = false;
    await _homeCommandSttService.stopListening();

    _isHomeCommandSpeaking = true;
    await _homeCommandTtsService.speak(
      'Kembali',
      replacementKey: _screenTtsKey,
    );
    _isHomeCommandSpeaking = false;

    _homeCommandListenerEnabled = false;
    await _homeCommandButtonSubscription?.cancel();
    _homeCommandButtonSubscription = null;

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _handlePageStatusVoiceCommand() async {
    _hasHandledHomeCommand = true;
    _homeCommandListenerActive = false;
    await _homeCommandSttService.stopListening();

    final name = _pageName ?? 'ini';
    _isHomeCommandSpeaking = true;
    await _homeCommandTtsService.speak(
      'Anda sedang berada di halaman $name',
      replacementKey: _screenTtsKey,
    );
    _isHomeCommandSpeaking = false;
    _hasHandledHomeCommand = false;
  }

  Future<void> _handleHomeVoiceCommand({required bool isHomePage}) async {
    _hasHandledHomeCommand = true;
    _homeCommandListenerActive = false;
    await _homeCommandSttService.stopListening();

    _isHomeCommandSpeaking = true;
    await _homeCommandTtsService.speak(
      isHomePage
          ? 'Kamu sudah berada di halaman utama'
          : 'Membuka halaman utama',
      replacementKey: _screenTtsKey,
    );
    _isHomeCommandSpeaking = false;

    if (!mounted) return;

    if (isHomePage) {
      _hasHandledHomeCommand = false;
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.tunaNetraHome,
      (route) => false,
      arguments: {'announceHomeOpened': true},
    );
  }
}
