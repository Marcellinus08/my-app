import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../utils/constants.dart';
import '../widgets/app_dialog.dart';
import 'smart_cane_ble_service.dart';

/// Threshold untuk HP yang dipegang di tangan.
const double _freeFallThreshold = 3.5;
const double _impactThreshold = 28.0;
const Duration _detectionWindow = Duration(milliseconds: 600);
const Duration _cooldown = Duration(seconds: 5);

enum FallSource { device, smartCane }

class FallDetectionService {
  FallDetectionService._();
  static final FallDetectionService instance = FallDetectionService._();

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<SmartCaneFallEvent>? _smartCaneSubscription;
  DateTime? _freeFallDetectedAt;
  DateTime? _lastFallAt;
  bool _isRunning = false;
  bool _isDialogShowing = false;

  GlobalKey<NavigatorState>? _navigatorKey;

  bool get isRunning => _isRunning;

  void start({required GlobalKey<NavigatorState> navigatorKey}) {
    if (_isRunning) return;
    _navigatorKey = navigatorKey;
    _isRunning = true;

    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(_onAccelerometerEvent, onError: (e) {
      debugPrint('[FallDetection] Accelerometer error: $e');
    });

    _smartCaneSubscription = SmartCaneBleService.instance.fallEventStream
        .listen(_onSmartCaneFallEvent);

    debugPrint('[FallDetection] Service started');
  }

  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _smartCaneSubscription?.cancel();
    _smartCaneSubscription = null;
    _freeFallDetectedAt = null;
    _isDialogShowing = false;
    _navigatorKey = null;
    debugPrint('[FallDetection] Service stopped');
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    final magnitude = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );

    final now = DateTime.now();

    if (_lastFallAt != null && now.difference(_lastFallAt!) < _cooldown) {
      return;
    }

    if (magnitude < _freeFallThreshold) {
      _freeFallDetectedAt ??= now;
      return;
    }

    if (_freeFallDetectedAt != null) {
      final elapsed = now.difference(_freeFallDetectedAt!);
      if (elapsed <= _detectionWindow && magnitude > _impactThreshold) {
        _lastFallAt = now;
        _freeFallDetectedAt = null;
        _showFallPopup(
          source: FallSource.device,
          impactMagnitude: magnitude,
        );
        return;
      }

      if (elapsed > _detectionWindow) {
        _freeFallDetectedAt = null;
      }
    }
  }

  // Hanya proses fall event SmartCane dengan probabilitas tinggi
  // untuk menghindari false positive saat SmartCane hanya dipegang/digerakkan biasa.
  static const double _smartCaneMinProbability = 0.90;

  void _onSmartCaneFallEvent(SmartCaneFallEvent event) {
    if (event.probability < _smartCaneMinProbability) {
      debugPrint(
        '[FallDetection] SmartCane fall event diabaikan (prob terlalu rendah: ${event.probability.toStringAsFixed(2)} < $_smartCaneMinProbability)',
      );
      return;
    }

    final now = DateTime.now();
    if (_lastFallAt != null && now.difference(_lastFallAt!) < _cooldown) {
      debugPrint(
        '[FallDetection] SmartCane fall event diabaikan (cooldown aktif)',
      );
      return;
    }

    debugPrint(
      '[FallDetection] JATUH TERDETEKSI (SmartCane) — prob: ${event.probability.toStringAsFixed(2)}',
    );
    _lastFallAt = now;
    _freeFallDetectedAt = null;
    _showFallPopup(
      source: FallSource.smartCane,
      smartCaneProbability: event.probability,
    );
  }

  void _showFallPopup({
    required FallSource source,
    double? impactMagnitude,
    double? smartCaneProbability,
  }) {
    if (source == FallSource.device) {
      debugPrint(
        '[FallDetection] JATUH TERDETEKSI (Device) — impact: ${impactMagnitude?.toStringAsFixed(1)} m/s²',
      );
    }

    if (_isDialogShowing) {
      debugPrint('[FallDetection] Dialog sudah tampil, popup dilewati');
      return;
    }

    // Defer ke frame berikutnya agar tidak bentrok dengan perubahan UI
    // yang sedang terjadi (misal: BLE reconnect memicu setState)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKey?.currentState;
      final overlayContext = navigator?.overlay?.context;
      if (overlayContext == null) {
        debugPrint('[FallDetection] Overlay context null, popup dilewati');
        return;
      }

      _isDialogShowing = true;
      try {
        showDialog<void>(
          context: overlayContext,
          barrierColor: AppDialogStyle.barrierColor,
          barrierDismissible: true,
          builder: (_) => _FallDetectedDebugDialog(
            source: source,
            impactMagnitude: impactMagnitude,
            smartCaneProbability: smartCaneProbability,
          ),
        ).whenComplete(() {
          _isDialogShowing = false;
        });
      } catch (e) {
        _isDialogShowing = false;
        debugPrint('[FallDetection] showDialog gagal: $e');
      }
    });
  }
}

class _FallDetectedDebugDialog extends StatelessWidget {
  const _FallDetectedDebugDialog({
    required this.source,
    this.impactMagnitude,
    this.smartCaneProbability,
  });

  final FallSource source;
  final double? impactMagnitude;
  final double? smartCaneProbability;

  @override
  Widget build(BuildContext context) {
    final isDevice = source == FallSource.device;
    final sourceLabel = isDevice ? 'HP Pengguna' : 'SmartCane (BLE)';
    final sourceIcon = isDevice ? Icons.smartphone : Icons.settings_remote;
    final sourceColor = isDevice ? Colors.orange : Colors.blue;

    final debugLines = isDevice
        ? 'Sumber       : $sourceLabel\n'
            'Impact       : ${impactMagnitude?.toStringAsFixed(1) ?? '-'} m/s²\n'
            'FF threshold : < ${_freeFallThreshold.toStringAsFixed(1)} m/s²\n'
            'Impact thr.  : > ${_impactThreshold.toStringAsFixed(1)} m/s²'
        : 'Sumber       : $sourceLabel\n'
            'Probabilitas : ${((smartCaneProbability ?? 0) * 100).toStringAsFixed(1)}%';

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: AppDialogStyle.insetPadding,
      titlePadding: AppDialogStyle.titlePadding,
      contentPadding: AppDialogStyle.contentPadding,
      actionsPadding: AppDialogStyle.actionPadding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDialogStyle.borderRadius),
        side: const BorderSide(color: AppDialogStyle.borderColor, width: 1),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: sourceColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.warning_amber_rounded, color: sourceColor, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '[DEBUG] Jatuh Terdeteksi',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(sourceIcon, size: 14, color: sourceColor),
              const SizedBox(width: 6),
              Text(
                'Terdeteksi dari $sourceLabel',
                style: TextStyle(
                  color: sourceColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Fitur deteksi jatuh AKTIF dan berhasil mendeteksi kejadian.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.4,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              debugLines,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF475569),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ),
      ],
    );
  }
}
