import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Konstanta (harus sama dengan fall_worker.py)
// ─────────────────────────────────────────────────────────────────────────────

const int _kPhoneBufferSize = 300;
const int _kFusionHalfWin = 100; // window = 200 timestep
const double _kPeltPenalty = 10.0;
const double _kMinCpDelta = 1.0; // m/s²
const Duration _kSendCooldown = Duration(seconds: 8);

// ─────────────────────────────────────────────────────────────────────────────
// Event output
// ─────────────────────────────────────────────────────────────────────────────

class FallDetectedEvent {
  const FallDetectedEvent({required this.probability, required this.timestamp});
  final double probability;
  final DateTime timestamp;
}

// ─────────────────────────────────────────────────────────────────────────────
// FallDetectionService
// ─────────────────────────────────────────────────────────────────────────────

class FallDetectionService extends ChangeNotifier {
  FallDetectionService._();
  static final FallDetectionService instance = FallDetectionService._();

  // ── Stream output ──────────────────────────────────────────────────────────
  final StreamController<FallDetectedEvent> _fallController =
      StreamController<FallDetectedEvent>.broadcast();
  Stream<FallDetectedEvent> get fallStream => _fallController.stream;

  // ── Callback untuk kirim phone IMU ke RPi via BLE ─────────────────────────
  /// Dipasang oleh SmartCaneBleService setelah koneksi BLE berhasil.
  /// Menerima JSON string phone IMU dan menulisnya ke characteristic a004.
  void Function(String jsonPayload)? onSendPhoneImu;

  // ── State ──────────────────────────────────────────────────────────────────
  bool _running = false;
  bool get isRunning => _running;

  // Phone IMU ring buffer  — List<List<double>> panjang maks _kPhoneBufferSize
  final _phoneBuffer = <List<double>>[];
  final _phoneTimestamps = <double>[]; // Unix epoch detik

  DateTime? _lastSendTime;

  // Subscription sensor
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // Sample IMU sementara (accel + gyro disatukan per frame)
  List<double>? _latestAccel;
  List<double>? _latestGyro;

  // ── Init & dispose ─────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_running) return;
    _running = true;

    _startSensorListeners();
    notifyListeners();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;

    _phoneBuffer.clear();
    _phoneTimestamps.clear();

    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _fallController.close();
    super.dispose();
  }

  // ── Sensor listeners ───────────────────────────────────────────────────────

  void _startSensorListeners() {
    _accelSub =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 10), // ~100 Hz
        ).listen((event) {
          _latestAccel = [event.x, event.y, event.z];
          _tryMergeSample();
        });

    _gyroSub =
        gyroscopeEventStream(
          samplingPeriod: const Duration(milliseconds: 10),
        ).listen((event) {
          _latestGyro = [event.x, event.y, event.z];
          _tryMergeSample();
        });
  }

  void _tryMergeSample() {
    final accel = _latestAccel;
    final gyro = _latestGyro;
    if (accel == null || gyro == null) return;

    final sample = [...accel, ...gyro]; // [ax, ay, az, gx, gy, gz]
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    _latestAccel = null;
    _latestGyro = null;

    // Tambah ke buffer
    _phoneBuffer.add(sample);
    _phoneTimestamps.add(now);
    if (_phoneBuffer.length > _kPhoneBufferSize) {
      _phoneBuffer.removeAt(0);
      _phoneTimestamps.removeAt(0);
    }

    // Kirim raw sample ke RPi untuk dimasukkan ke CPD tongkat
    _sendPhoneImuToRpi(sample, now);

    // Jalankan CPD lokal setiap kali buffer penuh
    if (_phoneBuffer.length >= _kPhoneBufferSize) {
      _runLocalCpd();
    }
  }

  // ── Kirim phone IMU ke RPi ─────────────────────────────────────────────────

  DateTime? _lastImuSendTime;

  void _sendPhoneImuToRpi(List<double> sample, double nowSec) {
    final cb = onSendPhoneImu;
    if (cb == null) return;

    // Throttle: kirim max 10Hz (setiap 100ms)
    final now = DateTime.now();
    if (_lastImuSendTime != null &&
        now.difference(_lastImuSendTime!) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastImuSendTime = now;

    final payload = jsonEncode({
      'e': 'phone_imu',
      'imu': sample,
      't': (nowSec * 1000).round(),
    });
    Future.microtask(() => cb(payload));
  }

  // ── PELT CPD lokal (Dart) ──────────────────────────────────────────────────
  //
  // Implementasi PELT RBF sederhana:
  // Cost RBF = -n * log(sigma²) di mana sigma² = var(segment).
  // Ini ekuivalen dengan ruptures PELT(model="rbf") untuk sinyal 1D.

  bool _localCpdVerified = false;
  DateTime? _localCpdVerifiedAt;

  void _runLocalCpd() {
    // Hanya jalankan kalau cooldown sudah lewat
    final last = _lastSendTime;
    if (last != null && DateTime.now().difference(last) < _kSendCooldown) {
      return;
    }

    final arr = List<List<double>>.from(_phoneBuffer);
    final mag = _computeMagnitude(arr);

    final result = _pelt1D(mag, penalty: _kPeltPenalty, minDelta: _kMinCpDelta);
    if (result == null) {
      _localCpdVerified = false;
      return;
    }

    _localCpdVerified = true;
    _localCpdVerifiedAt = DateTime.now();
    debugPrint(
      '[FALL] Phone CPD verified: cp=${result.$1}, delta=${result.$2.toStringAsFixed(2)}',
    );
  }

  // ── Terima fusion window dari RPi ─────────────────────────────────────────

  /// Dipanggil oleh SmartCaneBleService saat menerima {"e":"fusion_window",...} dari RPi.
  void onFusionWindowReceived(Map<String, dynamic> data) {
    final verifiedAt = _localCpdVerifiedAt;
    if (!_localCpdVerified || verifiedAt == null) {
      debugPrint(
        '[FALL] Fusion window diterima tapi phone CPD belum verified → diabaikan',
      );
      return;
    }

    if (DateTime.now().difference(verifiedAt).inSeconds > 2) {
      debugPrint('[FALL] Phone CPD terlalu lama → reset, fusion diabaikan');
      _localCpdVerified = false;
      return;
    }

    _localCpdVerified = false;
    _localCpdVerifiedAt = null;
    _lastSendTime = DateTime.now();

    final event = FallDetectedEvent(
      probability: 1.0,
      timestamp: DateTime.now(),
    );
    _fallController.add(event);
    debugPrint('[FALL] JATUH TERDETEKSI via CPD fusion');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<double> _computeMagnitude(List<List<double>> arr) {
    return arr.map((row) {
      final ax = row[0], ay = row[1], az = row[2];
      return math.sqrt(ax * ax + ay * ay + az * az);
    }).toList();
  }

  /// PELT 1D sederhana. Return (best_cp_index, delta) atau null.
  (int, double)? _pelt1D(
    List<double> signal, {
    required double penalty,
    required double minDelta,
  }) {
    final n = signal.length;
    if (n < 30) return null;

    // Cost per segmen: sum of squared deviations dari mean
    double _segCost(int s, int e) {
      if (e <= s) return 0.0;
      double sum = 0, sumSq = 0;
      for (var i = s; i < e; i++) {
        sum += signal[i];
        sumSq += signal[i] * signal[i];
      }
      final len = (e - s).toDouble();
      final mean = sum / len;
      return sumSq - len * mean * mean;
    }

    // PELT: dynamic programming
    final F = List<double>.filled(n + 1, double.infinity);
    final cps = List<int>.filled(n + 1, 0);
    F[0] = -penalty;

    for (var t = 1; t <= n; t++) {
      for (var s = 0; s < t; s++) {
        final cost = F[s] + _segCost(s, t) + penalty;
        if (cost < F[t]) {
          F[t] = cost;
          cps[t] = s;
        }
      }
    }

    // Rekonstruksi change points
    final breakpoints = <int>[];
    var t = n;
    while (t > 0) {
      final s = cps[t];
      if (s > 0) breakpoints.add(s);
      t = s;
    }
    breakpoints.sort();

    if (breakpoints.isEmpty) return null;

    // Pilih CP dengan delta terbesar
    int bestCp = -1;
    double bestDelta = 0;

    for (final cp in breakpoints) {
      final before = signal.sublist(math.max(0, cp - 10), cp);
      final after = signal.sublist(cp, math.min(n, cp + 10));
      if (before.isEmpty || after.isEmpty) continue;

      final meanBefore = before.reduce((a, b) => a + b) / before.length;
      final meanAfter = after.reduce((a, b) => a + b) / after.length;
      final delta = (meanAfter - meanBefore).abs();

      if (delta > bestDelta) {
        bestDelta = delta;
        bestCp = cp;
      }
    }

    if (bestCp < 0 || bestDelta < minDelta) return null;
    return (bestCp, bestDelta);
  }

}
