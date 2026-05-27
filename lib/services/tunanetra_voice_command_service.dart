import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/constants.dart';
import 'stt_service.dart';
import 'tts_service.dart';

class TunaNetraVoiceCommands {
  static bool isHomeCommand(String command) {
    final text = command.toLowerCase();
    return text.contains('halaman utama') ||
        text.contains('beranda') ||
        text.contains('home');
  }
}

mixin TunaNetraHomeVoiceCommandMixin<T extends StatefulWidget> on State<T> {
  final STTService _homeCommandSttService = STTService();
  final TTSService _homeCommandTtsService = TTSService();
  bool _isHomeCommandSpeaking = false;
  bool _hasHandledHomeCommand = false;
  bool _homeCommandListenerActive = false;
  bool _isStartingHomeCommandListener = false;
  bool _homeCommandListenerEnabled = false;
  Timer? _homeCommandSttWatchdog;

  void startHomeVoiceCommandListener({
    bool isHomePage = false,
    String? openingAnnouncement,
    Future<bool> Function(String command)? onCommand,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _homeCommandListenerEnabled = true;
      _startHomeCommandSttWatchdog(
        isHomePage: isHomePage,
        onCommand: onCommand,
      );
      _startHomeVoiceCommandListenerAfterAnnouncement(
        isHomePage: isHomePage,
        openingAnnouncement: openingAnnouncement,
        onCommand: onCommand,
      );
    });
  }

  Future<void> _startHomeVoiceCommandListenerAfterAnnouncement({
    required bool isHomePage,
    String? openingAnnouncement,
    Future<bool> Function(String command)? onCommand,
  }) async {
    if (openingAnnouncement != null && openingAnnouncement.isNotEmpty) {
      _isHomeCommandSpeaking = true;
      await _homeCommandTtsService.speak(openingAnnouncement);
      _isHomeCommandSpeaking = false;

      if (!mounted) return;
    }

    _startHomeCommandStt(isHomePage: isHomePage, onCommand: onCommand);
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
            if (TunaNetraVoiceCommands.isHomeCommand(text)) {
              _handleHomeVoiceCommand(isHomePage: isHomePage);
            }
          });
          return;
        }

        if (!TunaNetraVoiceCommands.isHomeCommand(text)) return;

        _handleHomeVoiceCommand(isHomePage: isHomePage);
      },
      onStatus: (status) {
        _homeCommandListenerActive = status == 'listening';

        if ((status == 'notListening' || status == 'done') &&
            mounted &&
            _homeCommandListenerEnabled &&
            !_isHomeCommandSpeaking &&
            !_hasHandledHomeCommand) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            _startHomeCommandStt(isHomePage: isHomePage, onCommand: onCommand);
          });
        }
      },
      onError: (_) {
        _homeCommandListenerActive = false;
        if (mounted &&
            _homeCommandListenerEnabled &&
            !_isHomeCommandSpeaking &&
            !_hasHandledHomeCommand) {
          Future.delayed(const Duration(seconds: 2), () {
            _startHomeCommandStt(isHomePage: isHomePage, onCommand: onCommand);
          });
        }
      },
    );
    _isStartingHomeCommandListener = false;
  }

  void _startHomeCommandSttWatchdog({
    required bool isHomePage,
    Future<bool> Function(String command)? onCommand,
  }) {
    _homeCommandSttWatchdog?.cancel();
    _homeCommandSttWatchdog = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted ||
          !_homeCommandListenerEnabled ||
          _isHomeCommandSpeaking ||
          _hasHandledHomeCommand) {
        return;
      }

      if (!_homeCommandSttService.isActuallyListening &&
          !_isStartingHomeCommandListener) {
        _homeCommandListenerActive = false;
        _startHomeCommandStt(isHomePage: isHomePage, onCommand: onCommand);
      }
    });
  }

  Future<void> stopHomeVoiceCommandListener() async {
    _hasHandledHomeCommand = true;
    _homeCommandListenerEnabled = false;
    _homeCommandListenerActive = false;
    _homeCommandSttWatchdog?.cancel();
    _homeCommandSttWatchdog = null;
    await _homeCommandSttService.stopListening();
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
    );
    _isHomeCommandSpeaking = false;

    if (!mounted) return;

    if (isHomePage) {
      _hasHandledHomeCommand = false;
      startHomeVoiceCommandListener(isHomePage: true);
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.tunaNetraHome,
      (route) => false,
      arguments: {'announceHomeOpened': true},
    );
  }
}
