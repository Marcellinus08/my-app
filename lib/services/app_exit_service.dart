import 'package:flutter/services.dart';

import 'live_tracking_service.dart';
import 'smart_cane_ble_service.dart';
import 'stt_service.dart';
import 'tts_service.dart';

class AppExitService {
  AppExitService._();

  static Future<void> stopBackgroundServices() async {
    final liveTrackingService = LiveTrackingService();

    await STTService().stopListening();
    await liveTrackingService.stopNavigationTracking(resumeHomeTracking: false);
    await liveTrackingService.stopHomeLocationTracking();
    await liveTrackingService.updateInactiveTracking();

    final bleService = SmartCaneBleService.instance;
    bleService.setNavigationHazardAnnouncementsEnabled(false);
    await bleService.disconnect(log: (_) {}, updateStatus: (_) {});
  }

  static Future<void> closeApp() async {
    await stopBackgroundServices();
    await TTSService().stop();
    await SystemNavigator.pop();
  }
}
