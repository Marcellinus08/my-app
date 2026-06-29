// Response time measurement: Perubahan posisi GPS -> pembaruan di aplikasi pengawas
//
// Mengukur segmen end-to-end dari device tunanetra ke device keluarga:
//   Battery        : LiveTrackingService mulai tulis -> battery.batteryLevel selesai
//   RTDB+Propagasi : ref.update() dipanggil -> data tiba di client keluarga
//                    (termasuk Firebase RTDB write + push propagation antar device)
//   Total          : WriteStart -> data tiba di client keluarga
//
// Tambahan log dari device tunanetra (segmen lokal, single-device):
//   RTDB write     : battery done -> ref.update() selesai (server ack)
//
// CATATAN:
//   - "Total" TIDAK termasuk GPS event -> WriteStart (throttle 2 detik, dll).
//   - RTDB+Propagasi diukur cross-device — akurasi bergantung sinkronisasi clock HP.
//   - Segmen "Battery" di log keluarga dihitung dari clock device tunanetra (embedded di RTDB).
//   - Nomor #N di kedua sisi menggunakan sampleNum yang sama (embedded di RTDB) sehingga
//     baris tunanetra dan family dengan #N yang sama merujuk pada GPS update yang sama.
//
// HOW TO USE di tunanetra_home_screen.dart & navigation_screen.dart (sudah terpasang):
//   initState:
//     GpsRtTimer.reset();
//     LiveTrackingService.onWriteStart           = GpsRtTimer.onWriteStart;
//     LiveTrackingService.onBatteryDone          = GpsRtTimer.onBatteryDone;
//     LiveTrackingService.onGetWriteStartMs      = GpsRtTimer.getWriteStartMs;
//     LiveTrackingService.onGetSampleNum         = GpsRtTimer.getSampleNum;
//     RealtimeLiveTrackingService.onRtdbWriteDone = GpsRtTimer.onRtdbWriteDone;
//   dispose:
//     LiveTrackingService.onWriteStart           = null;
//     LiveTrackingService.onBatteryDone          = null;
//     LiveTrackingService.onGetWriteStartMs      = null;
//     LiveTrackingService.onGetSampleNum         = null;
//     RealtimeLiveTrackingService.onRtdbWriteDone = null;
//
// HOW TO USE di family_home_screen.dart (sudah terpasang):
//   initState:
//     GpsRtTimer.reset();
//     FamilyLocationService.onFamilyReceived = GpsRtTimer.onFamilyReceived;
//   dispose:
//     FamilyLocationService.onFamilyReceived = null;
//
// MELIHAT HASIL (butuh 2 terminal terpisah, app harus debug mode):
//
//   Cek device ID dulu:
//     & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
//
//   Terminal 1 — device tunanetra (ganti <ID_TUNANETRA> dengan ID dari perintah di atas):
//     & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s <ID_TUNANETRA> logcat -c ; & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s <ID_TUNANETRA> logcat flutter:V *:S | Select-String "RT_GPS"
//
//   Terminal 2 — device keluarga (ganti <ID_KELUARGA> dengan ID dari perintah di atas):
//     & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s <ID_KELUARGA> logcat -c ; & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s <ID_KELUARGA> logcat flutter:V *:S | Select-String "RT_GPS"
//
//   Pastikan app di-hot restart (tekan R di terminal flutter) setelah menghubungkan device.

import 'package:flutter/foundation.dart';

class GpsRtTimer {
  GpsRtTimer._();

  // --- State sisi tunanetra ---
  // _writeInProgress mencegah multiple concurrent writes di startup
  // men-overwrite _sampleCounter sehingga nomor mulai dari #1.
  static bool _writeInProgress = false;
  static int _sampleCounter = 0;
  static int? _currentSampleNum;
  static DateTime? _tWriteStart;
  static DateTime? _tBatteryDone;

  // Stage 1: LiveTrackingService mulai proses update
  // Dipanggil via LiveTrackingService.onWriteStart
  static void onWriteStart() {
    if (!kDebugMode) return;
    if (_writeInProgress) return; // write sebelumnya belum selesai, skip
    _writeInProgress = true;
    _sampleCounter++;
    _currentSampleNum = _sampleCounter;
    _tWriteStart = DateTime.now();
    _tBatteryDone = null;
  }

  // Stage 2: battery.batteryLevel selesai
  // Dipanggil via LiveTrackingService.onBatteryDone
  static void onBatteryDone() {
    if (!kDebugMode) return;
    if (!_writeInProgress) return;
    _tBatteryDone = DateTime.now();
  }

  // Getter: epoch ms saat WriteStart — di-embed ke RTDB sebagai _rt_start_ms
  // Dipanggil via LiveTrackingService.onGetWriteStartMs
  static int? getWriteStartMs() {
    if (!kDebugMode) return null;
    return _tWriteStart?.millisecondsSinceEpoch;
  }

  // Getter: nomor sampel — di-embed ke RTDB sebagai _rt_sample_num
  // Dipanggil via LiveTrackingService.onGetSampleNum
  static int? getSampleNum() {
    if (!kDebugMode) return null;
    return _currentSampleNum;
  }

  // Stage 3: RTDB ref.update() selesai (server ack)
  // Dipanggil via RealtimeLiveTrackingService.onRtdbWriteDone
  static void onRtdbWriteDone() {
    if (!kDebugMode) return;
    if (!_writeInProgress) return;

    final tWrite = _tWriteStart;
    final tBattery = _tBatteryDone;
    final sampleNum = _currentSampleNum;

    // Buka slot untuk write berikutnya sebelum return
    _writeInProgress = false;
    _tWriteStart = null;
    _tBatteryDone = null;
    _currentSampleNum = null;

    if (tWrite == null || tBattery == null || sampleNum == null) return;

    final now = DateTime.now();
    final batteryMs = tBattery.difference(tWrite).inMilliseconds;
    final rtdbMs = now.difference(tBattery).inMilliseconds;

    debugPrint(
      '[RT_GPS] #$sampleNum (tunanetra) | '
      'Battery: ${batteryMs}ms | '
      'RTDB write: ${rtdbMs}ms',
    );
  }

  // Stage 4: data tiba di client keluarga
  // Dipanggil via FamilyLocationService.onFamilyReceived
  // batteryMs, rtdbAndPropMs, totalMs dihitung dari data yang di-embed di RTDB
  static void onFamilyReceived(
    int sampleNum,
    int batteryMs,
    int rtdbAndPropMs,
    int totalMs,
  ) {
    if (!kDebugMode) return;

    debugPrint(
      '[RT_GPS] #$sampleNum (family) | '
      'Battery: ${batteryMs}ms | '
      'RTDB+Propagasi: ${rtdbAndPropMs}ms | '
      'Total: ${totalMs}ms',
    );
  }

  static void reset() {
    _writeInProgress = false;
    _sampleCounter = 0;
    _currentSampleNum = null;
    _tWriteStart = null;
    _tBatteryDone = null;
    debugPrint('[RT_GPS] Timer direset.');
  }
}
