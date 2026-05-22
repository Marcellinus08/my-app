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

  void startHomeVoiceCommandListener({bool isHomePage = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _homeCommandSttService.startListening((result) {
        if (_isHomeCommandSpeaking || _hasHandledHomeCommand) return;

        final text = result.toLowerCase();
        if (!TunaNetraVoiceCommands.isHomeCommand(text)) return;

        _handleHomeVoiceCommand(isHomePage: isHomePage);
      });
    });
  }

  Future<void> stopHomeVoiceCommandListener() async {
    await _homeCommandSttService.stopListening();
  }

  Future<void> _handleHomeVoiceCommand({required bool isHomePage}) async {
    _hasHandledHomeCommand = true;
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

    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.tunaNetraHome, (route) => false);
  }
}
