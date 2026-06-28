import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

// Threshold
const double _kFreefallThreshold = 5.0;  // m/s² — di bawah ini = free-fall
const double _kImpactThreshold = 20.0;   // m/s² — di atas ini = impact
const int _kFreefallMinSamples = 3;      // minimal sample free-fall berturut
const Duration _kImpactWindow = Duration(milliseconds: 500); // max jeda setelah free-fall
const Duration _kCooldown = Duration(seconds: 8);

class FallDetectedEvent {
  const FallDetectedEvent({required this.timestamp});
  final DateTime timestamp;
}

class FallDetectionService extends ChangeNotifier {
  FallDetectionService._();
  static final FallDetectionService instance = FallDetectionService._();

  final StreamController<FallDetectedEvent> _fallController =
      StreamController<FallDetectedEvent>.broadcast();
  Stream<FallDetectedEvent> get fallStream => _fallController.stream;

  bool _running = false;
  bool get isRunning => _running;

  StreamSubscription<AccelerometerEvent>? _accelSub;

  // State mesin deteksi
  int _freefallCount = 0;
  DateTime? _freefallEndTime;
  DateTime? _lastFallTime;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20), // 50 Hz cukup
    ).listen(_onAccel);
    notifyListeners();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _accelSub?.cancel();
    _accelSub = null;
    _freefallCount = 0;
    _freefallEndTime = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _fallController.close();
    super.dispose();
  }

  void _onAccel(AccelerometerEvent e) {
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    final now = DateTime.now();

    // Cooldown global
    if (_lastFallTime != null && now.difference(_lastFallTime!) < _kCooldown) {
      return;
    }

    if (mag < _kFreefallThreshold) {
      _freefallCount++;
      if (_freefallCount >= _kFreefallMinSamples) {
        _freefallEndTime = now;
      }
    } else {
      if (_freefallCount > 0) _freefallCount = 0;

      // Cek impact setelah free-fall
      final freefallAt = _freefallEndTime;
      if (freefallAt != null &&
          now.difference(freefallAt) <= _kImpactWindow &&
          mag >= _kImpactThreshold) {
        _freefallEndTime = null;
        _lastFallTime = now;
        debugPrint('[FALL] Jatuh terdeteksi: mag=${mag.toStringAsFixed(1)}');
        _fallController.add(FallDetectedEvent(timestamp: now));
      }
    }

    // Reset free-fall state kalau terlalu lama tidak ada impact
    if (_freefallEndTime != null &&
        now.difference(_freefallEndTime!) > _kImpactWindow) {
      _freefallEndTime = null;
    }
  }
}
