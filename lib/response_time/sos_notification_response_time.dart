// Response time measurement: SOS triple press -> FCM dispatched (notifikasi keluarga)
//
// Mengukur 5 segmen end-to-end:
//   Trigger->Send   : triple press confirmed -> sendSosAlert() dipanggil
//                     (termasuk await speakSafe "Mengirim SOS darurat")
//   Auth            : Firebase getIdToken()
//   Firestore       : getTunaNetraProfile + getLiveTracking + getConnectedFamilyUids
//                     + saveSosAlert (semua operasi Firestore sebelum kirim Worker)
//   Worker HTTP     : POST ke Cloudflare Worker -> FCM dispatched (round trip)
//   Total           : triple press confirmed -> FCM dispatched
//
// CATATAN: Waktu pengiriman FCM dari Google server ke device keluarga TIDAK terukur
//          dari sisi ini (~500–2000ms tambahan di luar kontrol app).
//
// HOW TO USE di navigation_screen.dart & tunanetra_home_screen.dart:
//   initState:
//     SosService.onAuthDone      = SosRtTimer.onAuthDone;
//     SosService.onFirestoreDone = SosRtTimer.onFirestoreDone;
//     SosService.onWorkerDone    = SosRtTimer.onWorkerDone;
//   dispose:
//     SosService.onAuthDone      = null;
//     SosService.onFirestoreDone = null;
//     SosService.onWorkerDone    = null;
//   _triggerNavigationSos / _triggerEmergency, setelah claimSosTrigger() return true:
//     SosRtTimer.onTrigger();
//   tepat sebelum _sosService.sendSosAlert():
//     SosRtTimer.onSendStart();
//   setelah sendSosAlert() selesai (di blok try, sebelum baca result):
//     SosRtTimer.onSendComplete(result.deliveredToAnyFamily);
//
// HOW TO USE di sos_service.dart (lihat sos_service.dart untuk hook yang sudah ditambah):
//   Tambahkan static hooks & panggil di dalam sendSosAlert().
//
// MELIHAT HASIL (terminal kedua saat app berjalan):
//   & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat -c ; & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat flutter:V *:S | Select-String "RT_SOS"

import 'package:flutter/foundation.dart';

class SosRtTimer {
  SosRtTimer._();

  static DateTime? _t0Trigger;
  static DateTime? _t1SendStart;
  static DateTime? _t2AuthDone;
  static DateTime? _t3FirestoreDone;

  static int _sampleCount = 0;
  static int _totalTriggerToSendMs = 0;
  static int _totalAuthMs = 0;
  static int _totalFirestoreMs = 0;
  static int _totalWorkerMs = 0;
  static int _totalEndToEndMs = 0;
  static int _minEndToEndMs = 999999;
  static int _maxEndToEndMs = 0;

  // Stage 1: triple press confirmed, tepat setelah claimSosTrigger() return true
  static void onTrigger() {
    if (!kDebugMode) return;
    _t0Trigger = DateTime.now();
    _t1SendStart = null;
    _t2AuthDone = null;
    _t3FirestoreDone = null;
  }

  // Stage 2: sendSosAlert() akan dipanggil (setelah speakSafe "Mengirim SOS darurat")
  static void onSendStart() {
    if (!kDebugMode) return;
    if (_t0Trigger == null) return;
    _t1SendStart = DateTime.now();
  }

  // Stage 3: getIdToken() selesai — dipanggil via SosService.onAuthDone hook
  static void onAuthDone() {
    if (!kDebugMode) return;
    if (_t1SendStart == null) return;
    _t2AuthDone = DateTime.now();
  }

  // Stage 4: semua Firestore selesai (profile + familyUIDs + saveAlert)
  //          dipanggil via SosService.onFirestoreDone hook
  static void onFirestoreDone() {
    if (!kDebugMode) return;
    if (_t2AuthDone == null) return;
    _t3FirestoreDone = DateTime.now();
  }

  // Stage 5: Future.wait worker selesai (FCM dispatched)
  //          dipanggil via SosService.onWorkerDone hook
  static void onWorkerDone(int successCount, int failedCount) {
    if (!kDebugMode) return;
    final t0 = _t0Trigger;
    final t1 = _t1SendStart;
    final t2 = _t2AuthDone;
    final t3 = _t3FirestoreDone;
    if (t0 == null || t1 == null || t2 == null || t3 == null) return;

    final now = DateTime.now();
    final triggerToSendMs = t1.difference(t0).inMilliseconds;
    final authMs = t2.difference(t1).inMilliseconds;
    final firestoreMs = t3.difference(t2).inMilliseconds;
    final workerMs = now.difference(t3).inMilliseconds;
    final totalMs = now.difference(t0).inMilliseconds;

    _t0Trigger = null;
    _t1SendStart = null;
    _t2AuthDone = null;
    _t3FirestoreDone = null;

    _sampleCount++;
    _totalTriggerToSendMs += triggerToSendMs;
    _totalAuthMs += authMs;
    _totalFirestoreMs += firestoreMs;
    _totalWorkerMs += workerMs;
    _totalEndToEndMs += totalMs;
    if (totalMs < _minEndToEndMs) _minEndToEndMs = totalMs;
    if (totalMs > _maxEndToEndMs) _maxEndToEndMs = totalMs;

    final status =
        successCount > 0 ? 'OK($successCount sukses)' : 'GAGAL($failedCount)';

    debugPrint(
      '[RT_SOS] #$_sampleCount | '
      'Trigger->Send: ${triggerToSendMs}ms | '
      'Auth: ${authMs}ms | '
      'Firestore: ${firestoreMs}ms | '
      'Worker HTTP: ${workerMs}ms | '
      'Total: ${totalMs}ms | '
      'FCM: $status',
    );

    if (_sampleCount % 5 == 0) _printSummary();
  }

  // Dipanggil dari call site setelah sendSosAlert() selesai
  // (opsional — hanya untuk log apakah pengiriman berhasil tanpa masalah hook)
  static void onSendComplete(bool deliveredToAnyFamily) {
    if (!kDebugMode) return;
    if (_t0Trigger == null && _sampleCount == 0) return;
    // onWorkerDone sudah menghitung; ini hanya fallback log jika hook tidak terpasang
    if (_t3FirestoreDone != null) {
      debugPrint(
        '[RT_SOS] onSendComplete dipanggil tapi onWorkerDone hook belum jalan — '
        'pastikan SosService hooks terpasang.',
      );
    }
  }

  static void printSummary() => _printSummary();

  static void _printSummary() {
    if (_sampleCount == 0) {
      debugPrint('[RT_SOS] Belum ada data.');
      return;
    }
    final avgTriggerToSend =
        (_totalTriggerToSendMs / _sampleCount).round();
    final avgAuth = (_totalAuthMs / _sampleCount).round();
    final avgFirestore = (_totalFirestoreMs / _sampleCount).round();
    final avgWorker = (_totalWorkerMs / _sampleCount).round();
    final avgTotal = (_totalEndToEndMs / _sampleCount).round();
    debugPrint('[RT_SOS] -- SUMMARY ($_sampleCount samples) --');
    debugPrint('[RT_SOS]   Trigger->Send  : avg ${avgTriggerToSend}ms  (TTS "Mengirim SOS darurat")');
    debugPrint('[RT_SOS]   Auth           : avg ${avgAuth}ms  (Firebase getIdToken)');
    debugPrint('[RT_SOS]   Firestore      : avg ${avgFirestore}ms  (profile + familyUIDs + saveAlert)');
    debugPrint('[RT_SOS]   Worker HTTP    : avg ${avgWorker}ms  (CF Worker -> FCM dispatched)');
    debugPrint('[RT_SOS]   Total          : avg ${avgTotal}ms  (min: ${_minEndToEndMs}ms, max: ${_maxEndToEndMs}ms)');
    debugPrint('[RT_SOS]   NFR-07 target  : <= 5000ms  (+ FCM transit ~500–2000ms tidak terukur)');
  }

  static void reset() {
    _t0Trigger = null;
    _t1SendStart = null;
    _t2AuthDone = null;
    _t3FirestoreDone = null;
    _sampleCount = 0;
    _totalTriggerToSendMs = 0;
    _totalAuthMs = 0;
    _totalFirestoreMs = 0;
    _totalWorkerMs = 0;
    _totalEndToEndMs = 0;
    _minEndToEndMs = 999999;
    _maxEndToEndMs = 0;
    debugPrint('[RT_SOS] Timer direset.');
  }
}
