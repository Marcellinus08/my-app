import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'tts_service.dart';

class CorePermissionStatus {
  final bool locationServiceEnabled;
  final bool locationGranted;
  final bool microphoneGranted;

  const CorePermissionStatus({
    required this.locationServiceEnabled,
    required this.locationGranted,
    required this.microphoneGranted,
  });

  bool get allGranted =>
      locationServiceEnabled && locationGranted && microphoneGranted;
}

class CorePermissionService {
  Future<CorePermissionStatus> ensureTunaNetraCorePermissions({
    Future<void> Function(bool locationGranted)? onLocationPermissionHandled,
  }) async {
    final ttsService = TTSService();

    final locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!locationServiceEnabled) {
      await ttsService.speak(
        'Layanan GPS belum aktif. Silakan aktifkan lokasi di pengaturan HP.',
      );
    }

    var locationPermission = await Geolocator.checkPermission();

    if (locationPermission == LocationPermission.denied) {
      await ttsService.speak(
        'Aplikasi membutuhkan akses lokasi untuk navigasi. Silakan pilih Izinkan pada dialog berikutnya.',
      );
      locationPermission = await Geolocator.requestPermission();
    }

    final locationGranted =
        locationPermission == LocationPermission.always ||
        locationPermission == LocationPermission.whileInUse;
    if (locationPermission == LocationPermission.deniedForever) {
      await ttsService.speak(
        'Izin lokasi dinonaktifkan permanen. Buka pengaturan aplikasi, lalu izinkan akses lokasi.',
      );
    }
    await onLocationPermissionHandled?.call(locationGranted);

    var microphonePermission = await Permission.microphone.status;
    if (!microphonePermission.isGranted) {
      await ttsService.speak(
        'Aplikasi membutuhkan akses mikrofon agar perintah suara dapat digunakan. Silakan pilih Izinkan pada dialog berikutnya.',
      );
      microphonePermission = await Permission.microphone.request();
    }

    final microphoneGranted = microphonePermission.isGranted;
    if (microphonePermission.isPermanentlyDenied) {
      await ttsService.speak(
        'Izin mikrofon dinonaktifkan permanen. Buka pengaturan aplikasi, lalu izinkan mikrofon untuk memakai perintah suara.',
      );
    }
    if (microphoneGranted) {
      final stt = SpeechToText();
      await stt.initialize();
      await stt.stop();
    }

    return CorePermissionStatus(
      locationServiceEnabled: locationServiceEnabled,
      locationGranted: locationGranted,
      microphoneGranted: microphoneGranted,
    );
  }
}
