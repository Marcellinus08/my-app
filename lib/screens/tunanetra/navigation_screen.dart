import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import '../../utils/constants.dart';
import '../../utils/app_feedback.dart';
import '../../models/place_model.dart';
import '../../models/navigation_instruction_model.dart';
import '../../services/places_service.dart';
import '../../services/routing_service.dart';
import '../../services/analytics_service.dart';
import '../../services/app_exit_service.dart';
import '../../services/live_tracking_service.dart';
import '../../services/realtime_live_tracking_service.dart';
import '../../services/navigation_history_service.dart';
import '../../services/smart_cane_ble_service.dart';
import '../../services/sos_service.dart';
import '../../services/stt_service.dart';
import '../../services/tts_service.dart';
import '../../services/tunanetra_voice_command_service.dart';
import '../../widgets/app_dialog.dart';
import 'package:teman_arah/response_time/obstacle_tts_response_time.dart';
import 'package:teman_arah/response_time/sos_notification_response_time.dart';
import 'package:teman_arah/response_time/gps_tracking_response_time.dart';

enum _GpsAccuracyStatus { good, fair, weak }

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late MapController _mapController;
  bool _isMapReady = false;
  LatLng? _pendingMapCenter;
  double? _pendingMapZoom;
  final PlacesService _placesService = PlacesService();
  final RoutingService _routingService = RoutingService();
  final AnalyticsService _analyticsService = AnalyticsService();
  final LiveTrackingService _liveTrackingService = LiveTrackingService();
  final NavigationHistoryService _navigationHistoryService =
      NavigationHistoryService();
  final SmartCaneBleService _smartCaneBleService = SmartCaneBleService.instance;
  final SosService _sosService = SosService();
  final TTSService _ttsService = TTSService();
  final STTService _sttService = STTService();
  bool _isSpeaking = false;
  bool _suppressTtsStopOnDispose = false;
  int _localSpeechGeneration = 0;
  bool _navigationSttActive = false;
  bool _navigationSttStarting = false;
  bool _isSendingSos = false;
  bool _isFreeMode = false;
  static const double _pedestrianSpeedMs = 1.4;
  static const double _arrivalThresholdMeters = 10.0;
  static const double _routeEndArrivalThresholdMeters = 5.0;
  static const double _routeEndDestinationToleranceMeters = 20.0;
  static const double _goodGpsAccuracyMeters = 10.0;
  static const double _fairGpsAccuracyMeters = 20.0;
  static const double _turnCompletionHeadingToleranceDegrees = 45.0;
  static const double _turnAreaDistanceMeters = 10.0;
  static const double _instructionLookAheadMeters = 15.0;
  static const double _turnCompletionMinimumDistanceMeters = 7.0;
  static const double _turnCompletionRouteToleranceMeters = 8.0;
  static const double _minimumWalkingSpeedMs = 0.2;
  static const double _maximumWalkingCueSpeedMs = 3.0;
  static const double _turnAnchorSearchRadiusMeters = 35.0;
  static const double _turnAnchorMinimumAngleDegrees = 20.0;
  static const int _requiredArrivalConfirmations = 3;
  static const int _requiredManeuverConfirmations = 2;
  static const int _requiredFairAccuracyManeuverConfirmations = 3;
  static const int _requiredTurnCompletionConfirmations = 2;
  static const int _requiredGpsStatusChangeSamples = 3;
  static const int _gpsCueWindowSize = 5;
  static const Duration _gpsWeakAnnouncementInterval = Duration(seconds: 5);
  static const Duration _maneuverConfirmationInterval = Duration(
    milliseconds: 500,
  );

  // Default location: Bandung, Indonesia
  final LatLng defaultLocation = const LatLng(-6.9147, 107.6098);
  late LatLng _userLocation;
  late LatLng _animatedUserLocation;
  late final AnimationController _locationAnimationController;
  Animation<double>? _latAnimation;
  Animation<double>? _lngAnimation;
  double _markerHeading = 0.0;
  StreamSubscription<UserAccelerometerEvent>? _userAccelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<SmartCaneSensorData>? _smartCaneSensorSubscription;
  StreamSubscription<SmartCaneButtonEvent>? _smartCaneButtonSubscription;
  // StreamSubscription<SmartCaneFallEvent>? _fallEventSubscription;
  Timer? _predictionTimer;
  DateTime? _lastGpsUpdateAt;
  DateTime? _lastGyroEventAt;
  DateTime? _lastPredictionTickAt;
  LatLng? _lastGpsLocation;
  double _estimatedSpeedMs = 0.0;
  double _smoothedAccelMagnitude = 0.0;
  double _predictedDistanceSinceLastGps = 0.0;
  bool _isUsingPredictedPosition = false;
  static const Duration _gpsStaleThreshold = Duration(milliseconds: 1200);
  static const Duration _predictionTickInterval = Duration(milliseconds: 250);
  static const double _maxPredictionDistanceMeters = 15.0;
  static const double _maxWalkingSpeedMs = 2.4;
  static const double _routeTrimThresholdMeters = 12.0;
  static const double _routeSnapThresholdMeters = 10.0;
  static const double _offRouteThresholdMeters = 15.0;
  static const Duration _offRouteConfirmDuration = Duration(seconds: 1);
  static const Duration _rerouteCooldown = Duration(seconds: 10);
  bool _isLocationReady =
      false; // Track if real user location has been obtained

  // Places from Firestore
  List<PlaceModel> _places = [];
  bool _isLoadingPlaces = true;

  // Track if user selected a place (untuk show map atau list)
  PlaceModel? _selectedPlace;

  // Route polyline points
  List<LatLng> _routePoints = [];
  int _lastPassedRouteIndex = 0;
  LatLng? _currentSnappedRoutePoint;
  bool _isLoadingRoute = false;
  String _routeLoadError = ''; // Error message for route
  DateTime? _offRouteSince;
  DateTime? _lastRerouteAt;
  bool _isOffRouteWarningVisible = false;
  DateTime? _lastGpsWeakAnnouncementAt;
  bool _wasGpsWeak = false;
  _GpsAccuracyStatus? _stableGpsAccuracyStatus;
  _GpsAccuracyStatus? _pendingGpsAccuracyStatus;
  int _pendingGpsAccuracyStatusCount = 0;

  // Route info (distance, duration) - Walking mode
  double _routeDistanceKm = 0.0;
  double _routeDurationMinutes = 0.0;
  double _routeDistanceMeters = 0.0;
  double _routeDurationSeconds = 0.0;

  // Time calculation variables
  bool _isNavigating = false; // Track if user is navigating
  DateTime? _navigationStartTime; // Time when navigation started
  String? _currentTripId;
  DateTime? _tripStartedAt;
  bool _isStartingTripHistory = false;
  LatLng? _lastRoutePointLocation;
  DateTime? _lastRoutePointSavedAt;
  Position? _lastKnownGpsPosition;
  bool _wasOffRoute = false;
  double _initialDurationSeconds = 0.0; // Initial duration from OSRM
  DateTime? _lastDurationUpdateTime; // Last time duration was updated
  Timer? _durationUpdateTimer; // Timer for periodic duration updates
  SmartCaneSensorData? _latestSmartCaneSensorData;
  String _lastSpokenSensorMessage = '';
  DateTime? _lastSensorTtsAt;

  // Navigation instructions (Turn-by-turn guidance)
  List<NavigationInstruction> _navigationInstructions = [];
  int _currentInstructionIndex = 0; // Index of current/next instruction
  double? _currentInstructionRemainingMeters;
  final Map<int, Set<int>> _announcedInstructionCueMeters = {};
  final Set<int> _announcedNowInstructionIndexes = {};
  final Map<int, int> _maneuverConfirmationCounts = {};
  final Map<int, int> _turnCompletionConfirmationCounts = {};
  final Map<int, DateTime> _lastManeuverConfirmationAt = {};
  final Map<int, double> _lastDistanceToManeuver = {};
  final List<LatLng> _gpsCueWindow = [];
  int? _pendingTurnSourceInstructionIndex;
  int? _pendingTurnNextInstructionIndex;
  double? _pendingTurnExpectedHeading;
  LatLng? _pendingTurnStartLocation;
  bool _isLoadingInstructions = false;
  String _instructionLoadError = '';
  bool _hasArrivedAtDestination = false;
  int _arrivalConfirmationCount = 0;
  String _destinationName = '';

  // Level terakhir yang diumumkan (0=none, 1=safe/ml, 2=warning, 3=danger)
  int _lastSensorLevel = 0;
  DateTime? _safePathDetectedAt;

  // Terjemahan label ML ke Bahasa Indonesia (termasuk label yang tidak ada
  // di SmartCaneSensorData._translateObjectLabel seperti pothole/stair/road).
  String _labelId(String label) => switch (label.toLowerCase()) {
    'pothole' => 'lubang',
    'obstacle' => 'hambatan',
    'stair' || 'stairs' => 'tangga',
    'road' => 'jalur kendaraan',
    'puddle' => 'genangan',
    'zebra_cross' || 'zebracross' || 'zebra cross' => 'zebra cross',
    'person' => 'orang',
    'bicycle' => 'sepeda',
    'car' => 'mobil',
    'motorcycle' || 'motorbike' => 'motor',
    'bus' => 'bus',
    'truck' => 'truk',
    'traffic light' => 'lampu lalu lintas',
    _ => label,
  };

  // Suffix posisi — hanya untuk non-tengah.
  String _posSuffix(String pos) => switch (pos.toLowerCase()) {
    'kiri' || 'left' => ' kiri',
    'kanan' || 'right' => ' kanan',
    _ => '',
  };

  /// Membangun pesan TTS singkat (≤5 kata) untuk mode jelajah.
  /// Satu pesan = satu informasi paling kritis, hierarki ketat:
  ///   1. Sensor danger (ultrasonik)
  ///   2. Road / pothole (label bahaya fisik)
  ///   3. Obstacle / stair / kendaraan (waspada)
  ///   4. Info lingkungan (zebra cross, genangan)
  ///   5. Arah dari decision RPi
  String _buildSimpleObstacleMessage(SmartCaneSensorData data) {
    final decisionRaw = data.decision?.trim().toLowerCase() ?? '';
    final direction = switch (decisionRaw) {
      'kiri' ||
      'belok kiri' ||
      'left' ||
      'pindah kiri' ||
      'pindah ke kiri' ||
      'geser kiri' ||
      'geser ke kiri' => 'kiri',
      'kanan' ||
      'belok kanan' ||
      'right' ||
      'pindah kanan' ||
      'pindah ke kanan' ||
      'geser kanan' ||
      'geser ke kanan' => 'kanan',
      _ => '',
    };
    final isStop =
        decisionRaw == 'stop' ||
        decisionRaw == 'berhenti' ||
        decisionRaw == 'berhenti sementara';

    // Level 1 — sensor ultrasonik danger
    if (data.isDanger) {
      if (direction.isNotEmpty) return 'Bahaya! Pindah $direction.';
      if (isStop) return 'Bahaya! Berhenti.';
      // belum ada label → cek deteksi dulu, fallback di bawah
    }

    final dets = data.detections;

    // Level 2 — road / pothole (bahaya fisik langsung)
    for (final d in dets) {
      switch (d.label.toLowerCase()) {
        case 'road':
          final pos = _posSuffix(d.position);
          return pos.isEmpty
              ? 'Jalur kendaraan! Mundur.'
              : 'Jalur kendaraan$pos!';
        case 'pothole':
          final pos = _posSuffix(d.position);
          return pos.isEmpty ? 'Lubang di depan.' : 'Lubang$pos.';
      }
    }

    // Sensor danger tanpa label spesifik
    if (data.isDanger) return 'Bahaya! Berhenti.';

    // Level 3 — obstacle / stair / kendaraan
    const alertSet = {
      'obstacle',
      'stair',
      'stairs',
      'person',
      'bicycle',
      'car',
      'motorcycle',
      'motorbike',
      'bus',
      'truck',
    };
    final alertDets = dets
        .where((d) => alertSet.contains(d.label.toLowerCase()))
        .toList();
    if (alertDets.isNotEmpty) {
      if (alertDets.length >= 2) {
        final l1 = _labelId(alertDets[0].label);
        final l2 = _labelId(alertDets[1].label);
        return 'Waspada, $l1 dan $l2.';
      }
      final d = alertDets.first;
      final labelText = _labelId(d.label);
      final pos = _posSuffix(d.position);
      if (direction.isNotEmpty) return '$labelText$pos. Pindah $direction.';
      return 'Waspada, $labelText$pos.';
    }

    // Warning + arah (tanpa label bahaya)
    if (data.isWarning) {
      if (direction.isNotEmpty) return 'Hambatan, pindah $direction.';
      if (isStop) return 'Hambatan, berhenti.';
      return 'Hati-hati! Hambatan.';
    }

    // Level 4 — info lingkungan
    for (final d in dets) {
      final label = d.label.toLowerCase();
      if (label.contains('zebra')) return 'Waspada, zebra cross.';
      if (label == 'puddle') {
        final pos = _posSuffix(d.position);
        return 'Waspada, genangan$pos.';
      }
      if (label != 'walkable' && label != 'road') {
        final pos = _posSuffix(d.position);
        return 'Waspada, ${_labelId(d.label)}$pos.';
      }
    }

    // Level 5 — hanya arah dari decision
    if (direction.isNotEmpty) return 'Pindah $direction.';

    // Fallback berbasis status — raw message RPi tidak pernah dipakai
    if (data.isDanger || data.hasDangerDetection) return 'Bahaya! Berhenti.';
    if (data.isWarning) return 'Hati-hati! Hambatan.';
    return '';
  }

  void _handleSensorTts(SmartCaneSensorData data) {
    if (!_smartCaneBleService.navigationHazardAnnouncementsEnabled) return;
    if (!_isNavigating && !_isFreeMode) return;

    final isDanger = data.isDanger || data.hasDangerDetection;
    final isWarning = data.isWarning;
    final isNavigationSpeaking =
        _ttsService.currentPriority == TtsPriority.navigation;

    // Tentukan level saat ini (3=danger, 2=warning, 1=safe/ml, 0=tidak ada)
    final int currentLevel;
    if (isDanger) {
      currentLevel = 3;
    } else if (isWarning) {
      currentLevel = 2;
    } else {
      final hasUsefulMl = data.detections.any(
        (d) => !const {'road', 'walkable'}.contains(d.label),
      );
      currentLevel = hasUsefulMl ? 1 : 0;
    }

    // Tidak ada bahaya/warning
    if (currentLevel < 2) {
      // Transisi dari bahaya/warning ke aman — tunggu 1.5s stabil lalu ucapkan
      if (_lastSensorLevel >= 2) {
        final now = DateTime.now();
        _safePathDetectedAt ??= now;
        if (now.difference(_safePathDetectedAt!) >=
            const Duration(milliseconds: 1000)) {
          _safePathDetectedAt = null;
          _lastSensorLevel = 0;
          unawaited(
            speakSafe(
              'Jalur aman.',
              priority: TtsPriority.warning,
              replacementKey: 'sensor-hazard',
              maxAge: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      if (currentLevel == 0) return;
      // level 1 (ML info) lanjut ke bawah
    } else {
      // Ada bahaya/warning — reset timer safe path
      _safePathDetectedAt = null;
    }

    final message = _buildSimpleObstacleMessage(data);
    if (message.isEmpty) return;

    // Suppress warning/info saat navigasi sedang bicara — danger tetap lanjut
    if (currentLevel < 3 && isNavigationSpeaking) return;

    final now = DateTime.now();

    final TtsPriority priority;
    final String replacementKey;
    final Duration maxAge;

    if (isDanger) {
      priority = TtsPriority.warning;
      replacementKey = 'sensor-hazard';
      maxAge = const Duration(seconds: 4);
    } else if (isWarning) {
      // Hambatan fisik harus bisa interrupt ML speech (low) — pakai warning priority
      priority = TtsPriority.warning;
      replacementKey = 'sensor-hazard';
      maxAge = const Duration(seconds: 3);
    } else {
      priority = TtsPriority.low;
      replacementKey = 'sensor-info';
      maxAge = const Duration(seconds: 2);
    }

    _lastSpokenSensorMessage = message;
    _lastSensorTtsAt = now;
    _lastSensorLevel = currentLevel;

    ObstacleTtsTimer.onTtsCall(message);

    unawaited(
      speakSafe(
        message,
        priority: priority,
        deduplicationKey: 'sensor-$message',
        replacementKey: replacementKey,
        maxAge: maxAge,
      ),
    );
  }

  Future<void> speakSafe(
    String text, {
    TtsPriority priority = TtsPriority.normal,
    String? deduplicationKey,
    String? replacementKey,
    Duration? maxAge,
  }) async {
    final localGeneration = _localSpeechGeneration;
    if (localGeneration != _localSpeechGeneration) return;

    _isSpeaking = true;
    try {
      await _ttsService.speak(
        text,
        priority: priority,
        deduplicationKey: deduplicationKey,
        replacementKey: replacementKey,
        maxAge: maxAge,
      );
    } finally {
      _isSpeaking = false;
    }
  }

  @override
  void initState() {
    super.initState();
    TTSService.onSpeechStartHook = ObstacleTtsTimer.onTtsStart;
    TTSService.onSpeechSendHook = ObstacleTtsTimer.onTtsSend;
    TTSService.onTtsStopStartHook = ObstacleTtsTimer.onTtsStopStart;
    SosService.onAuthDone = SosRtTimer.onAuthDone;
    SosService.onFirestoreDone = SosRtTimer.onFirestoreDone;
    SosService.onWorkerDone = SosRtTimer.onWorkerDone;
    GpsRtTimer.reset();
    LiveTrackingService.onWriteStart = GpsRtTimer.onWriteStart;
    LiveTrackingService.onBatteryDone = GpsRtTimer.onBatteryDone;
    LiveTrackingService.onGetWriteStartMs = GpsRtTimer.getWriteStartMs;
    LiveTrackingService.onGetSampleNum = GpsRtTimer.getSampleNum;
    RealtimeLiveTrackingService.onRtdbWriteDone = GpsRtTimer.onRtdbWriteDone;
    unawaited(_ttsService.init());
    WidgetsBinding.instance.addObserver(this);
    _mapController = MapController();
    _locationAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_onLocationAnimationTick);
    _latestSmartCaneSensorData = _smartCaneBleService.isConnected
        ? _smartCaneBleService.latestSensorData
        : null;
    _smartCaneBleService.addListener(_handleSmartCaneConnectionChanged);
    _smartCaneBleService.setNavigationHazardAnnouncementsEnabled(false);
    _smartCaneSensorSubscription = _smartCaneBleService.sensorDataStream.listen(
      (data) {
        if (!mounted) return;
        ObstacleTtsTimer.onBleData(data.status, data.timestamp);
        if (!_smartCaneBleService.isConnected) return;
        setState(() => _latestSmartCaneSensorData = data);
        _handleSensorTts(data);
      },
    );
    _smartCaneButtonSubscription = _smartCaneBleService.buttonEventStream
        .listen(_handleSmartCaneButtonEvent);

    // _fallEventSubscription = _smartCaneBleService.fallEventStream
    //     .listen(_onFallDetected);

    // Wait for widget to render, then load places
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _getUserLocation();
      _loadPlaces();
      await speakSafe(
        'Halaman navigasi dibuka. Silahkan pilih tempat tujuan anda',
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _cancelNavigationBecauseAppClosed();
    }
  }

  void _cancelNavigationBecauseAppClosed() {
    final tripId = _currentTripId;
    final startedAt = _tripStartedAt ?? _navigationStartTime;
    final durationSeconds = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inSeconds;

    if (tripId != null) {
      double? endLat;
      double? endLng;
      final gpsPosition = _lastKnownGpsPosition;

      if (gpsPosition != null && !_isUsingPredictedPosition) {
        endLat = gpsPosition.latitude;
        endLng = gpsPosition.longitude;
      } else if (_animatedUserLocation.latitude != 0.0 ||
          _animatedUserLocation.longitude != 0.0) {
        endLat = _animatedUserLocation.latitude;
        endLng = _animatedUserLocation.longitude;
      } else if (_userLocation.latitude != 0.0 ||
          _userLocation.longitude != 0.0) {
        endLat = _userLocation.latitude;
        endLng = _userLocation.longitude;
      }

      _currentTripId = null;
      _tripStartedAt = null;
      unawaited(
        _navigationHistoryService
            .cancelTrip(
              tripId: tripId,
              durationSeconds: durationSeconds < 0 ? 0 : durationSeconds,
              totalDistanceMeters: _routeDistanceMeters,
              endLat: endLat,
              endLng: endLng,
            )
            .then(
              (_) => _liveTrackingService.updateNavigationTripState(
                currentTripId: null,
                isNavigating: false,
              ),
            ),
      );
      return;
    }

    if (_isNavigating) {
      unawaited(
        _liveTrackingService.updateNavigationTripState(
          currentTripId: null,
          isNavigating: false,
        ),
      );
    }
  }

  void _startVoiceNavigation() {
    if (_navigationSttStarting || _navigationSttActive || !mounted) {
      return;
    }

    _navigationSttStarting = true;
    _localSpeechGeneration++;

    _sttService
        .startListening(
          (result) {
            if (_isSpeaking) return;

            final text = result.toString().toLowerCase();
            if (text.trim().isEmpty) return;

            _handleNavigationCommand(text);
          },
          onNoSpeechDetected: () {
            if (!mounted) return;
            unawaited(
              speakSafe(
                'Tidak ada suara terdeteksi. Tekan dan tahan tombol merah untuk mencoba lagi.',
              ),
            );
          },
          pauseFor: const Duration(seconds: 5),
          finalResultsOnly: true,
          onStatus: (status) {
            _navigationSttActive = status == 'listening';
          },
          onError: (_) {
            _navigationSttActive = false;
          },
        )
        .whenComplete(() {
          _navigationSttStarting = false;
          _navigationSttActive = false;
        });
  }

  Future<void> _stopNavigationStt() async {
    _navigationSttActive = false;
    _navigationSttStarting = false;
    await _sttService.stopListening();
  }

  Future<void> _finishNavigationStt() async {
    await _sttService.finishListening();
    _navigationSttActive = false;
    _navigationSttStarting = false;
  }

  void _handleSmartCaneConnectionChanged() {
    if (!mounted) return;

    final nextSensorData = _smartCaneBleService.isConnected
        ? _smartCaneBleService.latestSensorData
        : null;

    if (identical(_latestSmartCaneSensorData, nextSensorData)) return;

    setState(() {
      _latestSmartCaneSensorData = nextSensorData;
      if (nextSensorData == null) {
        _lastSensorTtsAt = null;
        _lastSensorLevel = 0;
        _safePathDetectedAt = null;
      }
    });
  }

  Future<void> _handleNavigationCommand(String command) async {
    final cleanedCommand = command.trim();
    if (cleanedCommand.length < 2) return;

    await _stopNavigationStt();

    if (TunaNetraVoiceCommands.isCloseAppCommand(cleanedCommand)) {
      await _confirmCloseAppFromNavigationVoice();
      return;
    }

    if (TunaNetraVoiceCommands.isHomeCommand(cleanedCommand)) {
      _suppressTtsStopOnDispose = true;
      await speakSafe('Membuka halaman utama');
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.tunaNetraHome, (route) => false);
      return;
    }

    if (TunaNetraVoiceCommands.isSosCommand(cleanedCommand)) {
      await _triggerNavigationSos();
      return;
    }

    if (TunaNetraVoiceCommands.isReconnectSmartCaneCommand(cleanedCommand)) {
      await _reconnectSmartCaneFromNavigationVoice();
      return;
    }

    if (_isCheckDistanceCommand(cleanedCommand)) {
      await _speakNavigationDistance();
      return;
    }

    if (_isCheckEstimatedTimeCommand(cleanedCommand)) {
      await _speakNavigationEstimatedTime();
      return;
    }

    if (!_isFreeMode && !_isNavigating && cleanedCommand.contains('jelajah')) {
      _enterFreeMode();
      return;
    }

    if (cleanedCommand.contains('hentikan')) {
      if (_isFreeMode) {
        _exitFreeMode();
        await speakSafe(
          'Mode jelajah dihentikan. Kembali ke halaman pilih tempat.',
        );
      } else {
        await speakSafe('Navigasi dihentikan');
        await _endNavigationSession();
      }
      return;
    }

    if (TunaNetraVoiceCommands.isPageStatusCommand(cleanedCommand)) {
      await speakSafe('Anda sedang berada di halaman Navigasi');
      return;
    }

    if (TunaNetraVoiceCommands.isBackCommand(cleanedCommand)) {
      if (_isFreeMode) {
        _exitFreeMode();
        await speakSafe('Kembali ke halaman pilih tempat.');
      } else {
        _suppressTtsStopOnDispose = true;
        if (!mounted) return;
        Navigator.of(context).pop();
      }
      return;
    }

    final matchedPlace = _findPlaceFromCommand(cleanedCommand);
    if (matchedPlace != null) {
      if (!mounted) return;
      setState(() {
        _selectedPlace = matchedPlace;
        _isLoadingRoute = true;
        _routeLoadError = '';
      });

      await speakSafe('Memilih ${_formatPlaceName(matchedPlace.name)}');
      _startLocationStreaming();
      return;
    }

    await speakSafe(
      'Perintah tidak dikenali. Tekan dan tahan tombol merah untuk mencoba kembali.',
    );
  }

  Future<void> _reconnectSmartCaneFromNavigationVoice() async {
    if (_smartCaneBleService.isConnected) {
      await speakSafe('SmartCane sudah terhubung.');
      return;
    }

    if (_smartCaneBleService.isConnecting ||
        _smartCaneBleService.isAutoConnecting) {
      await speakSafe('SmartCane sedang dihubungkan. Mohon tunggu.');
      return;
    }

    final rememberedCaneId = await _smartCaneBleService
        .getRememberedCaneRemoteId();
    if (rememberedCaneId == null) {
      await speakSafe(
        'Belum ada SmartCane tersimpan. Buka menu koneksi untuk menghubungkan SmartCane.',
      );
      return;
    }

    await speakSafe('Mencoba menghubungkan ulang SmartCane.');
    await _smartCaneBleService.initializeAutoReconnect(
      force: true,
      maxAttempts: 5,
      log: debugPrint,
    );

    await speakSafe(
      _smartCaneBleService.isConnected
          ? 'SmartCane berhasil terhubung kembali.'
          : 'SmartCane belum dapat terhubung. Pastikan SmartCane menyala dan berada di dekat Anda.',
    );
  }

  Future<void> _confirmCloseAppFromNavigationVoice() async {
    await speakSafe(
      'Apakah Anda yakin ingin menutup aplikasi? Jawab ya untuk menutup, atau tidak untuk batal.',
    );

    await _sttService.startListening(
      (answer) async {
        await _stopNavigationStt();
        final text = answer.toLowerCase();
        if (TunaNetraVoiceCommands.isAcceptCommand(text)) {
          await speakSafe('Menutup aplikasi. Semua layanan dihentikan.');
          await _endNavigationSession();
          await AppExitService.closeApp();
          return;
        }

        await speakSafe('Batal menutup aplikasi.');
      },
      onNoSpeechDetected: () {
        unawaited(speakSafe('Tidak ada jawaban. Batal menutup aplikasi.'));
      },
      onStatus: (status) {
        _navigationSttActive = status == 'listening';
      },
      onError: (_) {
        _navigationSttActive = false;
      },
      pauseFor: const Duration(seconds: 4),
      finalResultsOnly: true,
    );
  }

  bool _isCheckDistanceCommand(String command) {
    return command.contains('cek jarak');
  }

  bool _isCheckEstimatedTimeCommand(String command) {
    return command.contains('cek waktu');
  }

  Future<void> _speakNavigationDistance() async {
    if (!_hasActiveRouteForVoice()) {
      await speakSafe('Rute navigasi belum tersedia.');
      return;
    }

    await speakSafe(
      'Sisa jarak ke ${_selectedPlace!.name} ${_formatRouteDistanceSpeech(_routeDistanceMeters)}.',
    );
  }

  Future<void> _speakNavigationEstimatedTime() async {
    if (!_hasActiveRouteForVoice()) {
      await speakSafe('Rute navigasi belum tersedia.');
      return;
    }

    await speakSafe(
      'Estimasi waktu menuju ${_selectedPlace!.name} ${_formatRouteDurationSpeech(_routeDurationMinutes)}.',
    );
  }

  bool _hasActiveRouteForVoice() {
    return _isNavigating &&
        _selectedPlace != null &&
        _routeDistanceMeters > 0 &&
        _routeDurationMinutes > 0;
  }

  PlaceModel? _findPlaceFromCommand(String command) {
    final normalizedCommand = _normalizeSearchText(command);

    for (final place in _places) {
      final normalizedName = _normalizeSearchText(place.name);
      final normalizedCategory = _normalizeSearchText(place.category);
      final normalizedAddress = _normalizeSearchText(place.address);

      if (normalizedCommand.contains(normalizedName) ||
          normalizedName.contains(normalizedCommand) ||
          normalizedCommand.contains(normalizedCategory) ||
          normalizedCategory.contains(normalizedCommand) ||
          normalizedCommand.contains(normalizedAddress) ||
          normalizedAddress.contains(normalizedCommand)) {
        return place;
      }
    }

    return null;
  }

  String _normalizeSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _onLocationAnimationTick() {
    if (!mounted || _latAnimation == null || _lngAnimation == null) return;

    final nextPoint = LatLng(_latAnimation!.value, _lngAnimation!.value);

    setState(() {
      _animatedUserLocation = nextPoint;
    });

    if (_isNavigating) {
      _safeMoveMap(nextPoint);
    }
  }

  Future<void> _handleSmartCaneButtonEvent(SmartCaneButtonEvent event) async {
    debugPrint('[SMARTCANE_BUTTON] Navigasi menerima event: ${event.type}');
    if (!mounted) return;

    if (event.isVoiceAssistantStop) {
      debugPrint('[SMARTCANE_BUTTON] Navigasi mematikan STT');
      await _finishNavigationStt();
      return;
    }

    if (event.isSos) {
      debugPrint('[SMARTCANE_BUTTON] Navigasi mengirim SOS');
      await _triggerNavigationSos();
      return;
    }

    if (!event.isVoiceAssistantStart) return;

    await _stopNavigationStt();

    if (!mounted) return;
    debugPrint('[SMARTCANE_BUTTON] Navigasi menyalakan STT');
    _startVoiceNavigation();
  }

  Future<void> _triggerNavigationSos() async {
    if (_isSendingSos) return;
    if (!TunaNetraVoiceCommands.claimSosTrigger()) return;
    SosRtTimer.onTrigger();

    _isSendingSos = true;
    await _stopNavigationStt();
    recordSosPressedEvent();

    try {
      await speakSafe(
        'Mengirim SOS darurat',
        priority: TtsPriority.critical,
        deduplicationKey: 'navigation-sos-sending',
      );
      SosRtTimer.onSendStart();
      final result = await _sosService.sendSosAlert();
      if (!mounted) return;
      AppFeedback.show(
        context,
        result.feedbackMessage,
        type: result.deliveredToAnyFamily
            ? AppFeedbackType.success
            : AppFeedbackType.warning,
      );
      unawaited(_announceSosStatus(result.spokenMessage));
    } catch (error) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        error,
        fallback:
            'SOS belum dapat dikirim. Periksa koneksi dan coba kembali segera.',
        announce: true,
      );
      unawaited(_announceSosStatus('Status SOS, gagal dikirim'));
    } finally {
      _isSendingSos = false;
    }
  }

  // Future<void> _onFallDetected(SmartCaneFallEvent event) async {
  //   if (!mounted) return;

  // TTS langsung — tidak perlu cek _isNavigating,
  // jatuh tetap diumumkan meski navigasi belum aktif
  // unawaited(
  //   speakSafe(
  //     'Peringatan! Terdeteksi jatuh. Apakah Anda baik-baik saja?',
  //     priority: TtsPriority.critical,
  //     deduplicationKey: 'fall-detected',
  //     replacementKey: 'sensor-hazard',
  //   ),
  // );

  // Tunda dialog 1.5 detik supaya TTS sempat mulai dulu
  // await Future.delayed(const Duration(milliseconds: 1500));
  // if (!mounted) return;

  // showDialog(
  //   context: context,
  //   barrierDismissible: false,
  //   builder: (_) => AlertDialog(
  //     title: const Text('Terdeteksi Jatuh'),
  //     content: Text(
  //       'Sistem mendeteksi kemungkinan jatuh '
  //       '(${(event.probability * 100).toStringAsFixed(0)}%).\n\n'
  //       'Apakah Anda membutuhkan bantuan?',
  //     ),
  //     actions: [
  //       TextButton(
  //         onPressed: () => Navigator.pop(context),
  //         child: const Text('Saya Baik-Baik Saja'),
  //       ),
  //       TextButton(
  //         style: TextButton.styleFrom(foregroundColor: Colors.red),
  //         onPressed: () {
  //           Navigator.pop(context);
  //           unawaited(_triggerNavigationSos());
  //         },
  //         child: const Text('Kirim SOS'),
  //       ),
  //     ],
  //   ),
  // );
  // }

  Future<void> _announceSosStatus(String message) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await speakSafe(
      message,
      priority: TtsPriority.critical,
      deduplicationKey: 'navigation-sos-status-$message',
    );
  }

  void _safeMoveMap(LatLng center, [double? zoom]) {
    if (!_isMapReady) {
      _pendingMapCenter = center;
      _pendingMapZoom = zoom;
      return;
    }

    _mapController.move(center, zoom ?? _mapController.camera.zoom);
  }

  void _onMapReady() {
    _isMapReady = true;
    final pendingCenter = _pendingMapCenter;
    final pendingZoom = _pendingMapZoom;
    _pendingMapCenter = null;
    _pendingMapZoom = null;

    if (pendingCenter != null) {
      _safeMoveMap(pendingCenter, pendingZoom);
    }
  }

  double _normalizeHeading(double heading) {
    final normalized = heading % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  double _smoothHeading(double current, double target, {double factor = 0.35}) {
    final delta = ((target - current + 540) % 360) - 180;
    return _normalizeHeading(current + (delta * factor));
  }

  double _bearingBetween(LatLng start, LatLng end) {
    final startLat = start.latitude * math.pi / 180;
    final endLat = end.latitude * math.pi / 180;
    final deltaLng = (end.longitude - start.longitude) * math.pi / 180;
    final y = math.sin(deltaLng) * math.cos(endLat);
    final x =
        math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(deltaLng);
    return _normalizeHeading(math.atan2(y, x) * 180 / math.pi);
  }

  double _headingDifference(double first, double second) {
    return (((first - second + 540) % 360) - 180).abs();
  }

  _GpsAccuracyStatus _gpsAccuracyStatus(double accuracy) {
    if (!accuracy.isFinite) return _GpsAccuracyStatus.weak;
    if (accuracy <= _goodGpsAccuracyMeters) return _GpsAccuracyStatus.good;
    if (accuracy <= _fairGpsAccuracyMeters) return _GpsAccuracyStatus.fair;
    return _GpsAccuracyStatus.weak;
  }

  _GpsAccuracyStatus _stableGpsAccuracyStatusFor(double accuracy) {
    final rawStatus = _gpsAccuracyStatus(accuracy);
    final stableStatus = _stableGpsAccuracyStatus;

    if (stableStatus == null) {
      _stableGpsAccuracyStatus = rawStatus;
      _pendingGpsAccuracyStatus = null;
      _pendingGpsAccuracyStatusCount = 0;
      return rawStatus;
    }

    if (rawStatus == stableStatus) {
      _pendingGpsAccuracyStatus = null;
      _pendingGpsAccuracyStatusCount = 0;
      return stableStatus;
    }

    if (_pendingGpsAccuracyStatus == rawStatus) {
      _pendingGpsAccuracyStatusCount++;
    } else {
      _pendingGpsAccuracyStatus = rawStatus;
      _pendingGpsAccuracyStatusCount = 1;
    }

    if (_pendingGpsAccuracyStatusCount >= _requiredGpsStatusChangeSamples) {
      _stableGpsAccuracyStatus = rawStatus;
      _pendingGpsAccuracyStatus = null;
      _pendingGpsAccuracyStatusCount = 0;
      return rawStatus;
    }

    return stableStatus;
  }

  void _resetGpsAccuracyStatusStabilizer() {
    _stableGpsAccuracyStatus = null;
    _pendingGpsAccuracyStatus = null;
    _pendingGpsAccuracyStatusCount = 0;
  }

  bool _canUseGpsForNavigation(double accuracy) {
    return (_stableGpsAccuracyStatus ?? _gpsAccuracyStatus(accuracy)) !=
        _GpsAccuracyStatus.weak;
  }

  void _addGpsCueSample(LatLng location) {
    _gpsCueWindow.add(location);
    if (_gpsCueWindow.length > _gpsCueWindowSize) {
      _gpsCueWindow.removeAt(0);
    }
  }

  LatLng _getStabilizedCueLocation(LatLng fallback) {
    if (_gpsCueWindow.isEmpty) return fallback;

    final latitudes = _gpsCueWindow.map((point) => point.latitude).toList()
      ..sort();
    final longitudes = _gpsCueWindow.map((point) => point.longitude).toList()
      ..sort();
    final middle = _gpsCueWindow.length ~/ 2;
    final stabilized = LatLng(latitudes[middle], longitudes[middle]);
    final snapResult = _snapPositionToRoute(stabilized);
    return snapResult.snapped ? snapResult.position : stabilized;
  }

  double? _polylineHeading(List<LatLng> points, {required bool fromEnd}) {
    if (points.length < 2) return null;

    if (fromEnd) {
      for (var index = points.length - 1; index > 0; index--) {
        if (_distanceBetweenPoints(points[index - 1], points[index]) >= 1) {
          return _bearingBetween(points[index - 1], points[index]);
        }
      }
      return null;
    }

    for (var index = 0; index < points.length - 1; index++) {
      if (_distanceBetweenPoints(points[index], points[index + 1]) >= 1) {
        return _bearingBetween(points[index], points[index + 1]);
      }
    }
    return null;
  }

  List<LatLng> _mergePolylinePoints(List<LatLng> first, List<LatLng> second) {
    final merged = <LatLng>[];

    for (final point in [...first, ...second]) {
      final isDuplicate =
          merged.isNotEmpty && _distanceBetweenPoints(merged.last, point) < 0.5;
      if (!isDuplicate) {
        merged.add(point);
      }
    }

    return merged;
  }

  LatLng? _nearestPolylinePoint(
    List<LatLng> points,
    LatLng target, {
    double maxDistanceMeters = double.infinity,
  }) {
    LatLng? nearest;
    var nearestDistance = double.infinity;

    for (final point in points) {
      final distance = _distanceBetweenPoints(point, target);
      if (distance < nearestDistance) {
        nearest = point;
        nearestDistance = distance;
      }
    }

    if (nearestDistance > maxDistanceMeters) return null;
    return nearest;
  }

  int _previousPointIndexAtLeast(
    List<LatLng> points,
    int fromIndex,
    double minDistanceMeters,
  ) {
    var traveledMeters = 0.0;
    for (var index = fromIndex; index > 0; index--) {
      traveledMeters += _distanceBetweenPoints(
        points[index],
        points[index - 1],
      );
      if (traveledMeters >= minDistanceMeters) {
        return index - 1;
      }
    }
    return 0;
  }

  int _nextPointIndexAtLeast(
    List<LatLng> points,
    int fromIndex,
    double minDistanceMeters,
  ) {
    var traveledMeters = 0.0;
    for (var index = fromIndex; index < points.length - 1; index++) {
      traveledMeters += _distanceBetweenPoints(
        points[index],
        points[index + 1],
      );
      if (traveledMeters >= minDistanceMeters) {
        return index + 1;
      }
    }
    return points.length - 1;
  }

  LatLng? _findGeometryTurnAnchor({
    required List<LatLng> currentPolyline,
    required List<LatLng> nextPolyline,
    required LatLng maneuverLocation,
  }) {
    final points = _mergePolylinePoints(currentPolyline, nextPolyline);
    if (points.length < 3) return null;

    LatLng? bestPoint;
    var bestScore = double.negativeInfinity;

    for (var index = 1; index < points.length - 1; index++) {
      final candidate = points[index];
      final distanceToManeuver = _distanceBetweenPoints(
        candidate,
        maneuverLocation,
      );
      if (distanceToManeuver > _turnAnchorSearchRadiusMeters) continue;

      final previousIndex = _previousPointIndexAtLeast(points, index, 3);
      final nextIndex = _nextPointIndexAtLeast(points, index, 3);
      if (previousIndex == index || nextIndex == index) continue;

      final incomingHeading = _bearingBetween(points[previousIndex], candidate);
      final outgoingHeading = _bearingBetween(candidate, points[nextIndex]);
      final angle = _headingDifference(incomingHeading, outgoingHeading);
      if (angle < _turnAnchorMinimumAngleDegrees) continue;

      final score = angle - (distanceToManeuver * 0.25);
      if (score > bestScore) {
        bestScore = score;
        bestPoint = candidate;
      }
    }

    return bestPoint;
  }

  LatLng? _resolveTurnAnchor(
    NavigationInstruction currentInstruction,
    int nextInstructionIndex,
  ) {
    if (nextInstructionIndex >= _navigationInstructions.length) {
      if (_selectedPlace == null) return null;
      return LatLng(_selectedPlace!.latitude, _selectedPlace!.longitude);
    }

    final nextInstruction = _navigationInstructions[nextInstructionIndex];
    final geometryAnchor = _findGeometryTurnAnchor(
      currentPolyline: currentInstruction.polylinePoints,
      nextPolyline: nextInstruction.polylinePoints,
      maneuverLocation: nextInstruction.location,
    );
    if (geometryAnchor != null) return geometryAnchor;

    final nearestToManeuver = _nearestPolylinePoint(
      _mergePolylinePoints(
        currentInstruction.polylinePoints,
        nextInstruction.polylinePoints,
      ),
      nextInstruction.location,
      maxDistanceMeters: _turnAnchorSearchRadiusMeters,
    );
    return nearestToManeuver ?? nextInstruction.location;
  }

  double _maneuverZoneMeters(double gpsAccuracy) {
    final accuracyStatus =
        _stableGpsAccuracyStatus ?? _gpsAccuracyStatus(gpsAccuracy);
    return switch (accuracyStatus) {
      _GpsAccuracyStatus.good => _turnAreaDistanceMeters,
      _GpsAccuracyStatus.fair => _turnAreaDistanceMeters * 0.8,
      _GpsAccuracyStatus.weak => 0,
    };
  }

  String _turnAreaInstruction(TurnType turnType, String instruction) {
    switch (turnType) {
      case TurnType.uturn:
        return 'area balik arah';
      case TurnType.sharpRight:
        return 'area belok kanan tajam';
      case TurnType.right:
        return 'area belok kanan';
      case TurnType.slightRight:
        return 'area belok kanan sedikit';
      case TurnType.straight:
        return 'area lanjut lurus';
      case TurnType.slightLeft:
        return 'area belok kiri sedikit';
      case TurnType.left:
        return 'area belok kiri';
      case TurnType.sharpLeft:
        return 'area belok kiri tajam';
      case TurnType.unknown:
        break;
    }

    final normalized = instruction.toLowerCase();
    if (normalized.contains('balik arah')) return 'area untuk balik arah';
    if (normalized.contains('belok kanan tajam')) {
      return 'area belok kanan tajam';
    }
    if (normalized.contains('belok kiri tajam')) {
      return 'area belok kiri tajam';
    }
    if (normalized.contains('belok kanan')) return 'area belok kanan';
    if (normalized.contains('belok kiri')) return 'area belok kiri';
    if (normalized.contains('lurus') || normalized.contains('lanjut')) {
      return 'area lanjut lurus';
    }
    return 'area manuver berikutnya';
  }

  double _currentMovementHeading() {
    final position = _lastKnownGpsPosition;
    if (position != null &&
        position.heading >= 0 &&
        position.speed.isFinite &&
        position.speed >= 0.3) {
      return position.heading;
    }
    return _markerHeading;
  }

  void _clearPendingTurn() {
    final sourceInstructionIndex = _pendingTurnSourceInstructionIndex;
    if (sourceInstructionIndex != null) {
      _turnCompletionConfirmationCounts.remove(sourceInstructionIndex);
    }
    _pendingTurnSourceInstructionIndex = null;
    _pendingTurnNextInstructionIndex = null;
    _pendingTurnExpectedHeading = null;
    _pendingTurnStartLocation = null;
  }

  void _confirmPendingTurn(LatLng stabilizedLocation) {
    final sourceInstructionIndex = _pendingTurnSourceInstructionIndex;
    final nextInstructionIndex = _pendingTurnNextInstructionIndex;
    final expectedHeading = _pendingTurnExpectedHeading;
    final turnStartLocation = _pendingTurnStartLocation;

    if (sourceInstructionIndex == null ||
        nextInstructionIndex == null ||
        expectedHeading == null ||
        turnStartLocation == null) {
      return;
    }

    if (!_isNavigating ||
        sourceInstructionIndex != _currentInstructionIndex ||
        nextInstructionIndex >= _navigationInstructions.length) {
      _clearPendingTurn();
      return;
    }

    final nextInstruction = _navigationInstructions[nextInstructionIndex];
    if (!_isDirectionalTurn(nextInstruction.turnType)) {
      _clearPendingTurn();
      return;
    }

    final distanceAfterCue = _distanceBetweenPoints(
      turnStartLocation,
      stabilizedLocation,
    );
    if (distanceAfterCue < _turnCompletionMinimumDistanceMeters) return;

    final movementHeading = _currentMovementHeading();
    final hasEnteredNextSegment =
        _headingDifference(movementHeading, expectedHeading) <=
        _turnCompletionHeadingToleranceDegrees;
    final distanceToNextSegment = _distanceToPolyline(
      stabilizedLocation,
      nextInstruction.polylinePoints,
    );
    final isNearNextSegment =
        distanceToNextSegment <= _turnCompletionRouteToleranceMeters;
    if (!hasEnteredNextSegment || !isNearNextSegment) {
      _turnCompletionConfirmationCounts[sourceInstructionIndex] = 0;
      return;
    }

    final confirmationCount =
        (_turnCompletionConfirmationCounts[sourceInstructionIndex] ?? 0) + 1;
    _turnCompletionConfirmationCounts[sourceInstructionIndex] =
        confirmationCount;
    if (confirmationCount < _requiredTurnCompletionConfirmations) return;

    if (mounted) {
      setState(() {
        _currentInstructionIndex = nextInstructionIndex;
        _currentInstructionRemainingMeters = null;
        _clearPendingTurn();
      });
    }

    unawaited(
      speakSafe(
        'Belok berhasil. Lanjutkan perjalanan.',
        priority: TtsPriority.navigation,
        replacementKey: 'navigation-guidance',
        maxAge: const Duration(seconds: 8),
      ),
    );
    _updateLiveInstructionDistance(stabilizedLocation, allowVoiceCue: false);
  }

  void _animateUserLocation(LatLng target) {
    final begin = _animatedUserLocation;
    _locationAnimationController.stop();

    _latAnimation = Tween<double>(begin: begin.latitude, end: target.latitude)
        .animate(
          CurvedAnimation(
            parent: _locationAnimationController,
            curve: Curves.linear,
          ),
        );
    _lngAnimation = Tween<double>(begin: begin.longitude, end: target.longitude)
        .animate(
          CurvedAnimation(
            parent: _locationAnimationController,
            curve: Curves.linear,
          ),
        );

    _locationAnimationController
      ..reset()
      ..forward();
  }

  LatLng _moveByMeters({
    required LatLng start,
    required double bearingDeg,
    required double distanceMeters,
  }) {
    const earthRadiusMeters = 6378137.0;
    final angularDistance = distanceMeters / earthRadiusMeters;
    final bearing = bearingDeg * (math.pi / 180.0);

    final lat1 = start.latitude * (math.pi / 180.0);
    final lon1 = start.longitude * (math.pi / 180.0);

    final sinLat1 = math.sin(lat1);
    final cosLat1 = math.cos(lat1);
    final sinAngular = math.sin(angularDistance);
    final cosAngular = math.cos(angularDistance);

    final lat2 = math.asin(
      sinLat1 * cosAngular + cosLat1 * sinAngular * math.cos(bearing),
    );
    final lon2 =
        lon1 +
        math.atan2(
          math.sin(bearing) * sinAngular * cosLat1,
          cosAngular - sinLat1 * math.sin(lat2),
        );

    return LatLng(lat2 * (180.0 / math.pi), lon2 * (180.0 / math.pi));
  }

  void _startSensorFusion() {
    _stopSensorFusion();

    _userAccelerometerSubscription = userAccelerometerEventStream().listen((
      event,
    ) {
      final magnitude = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _smoothedAccelMagnitude =
          (_smoothedAccelMagnitude * 0.8) + (magnitude * 0.2);
    });

    _gyroscopeSubscription = gyroscopeEventStream().listen((event) {
      final now = DateTime.now();
      if (_lastGyroEventAt == null) {
        _lastGyroEventAt = now;
        return;
      }

      final dtSeconds =
          now.difference(_lastGyroEventAt!).inMilliseconds / 1000.0;
      _lastGyroEventAt = now;
      if (dtSeconds <= 0 || dtSeconds > 0.2) return;

      final deltaDeg = event.z * dtSeconds * (180.0 / math.pi);
      _markerHeading = _normalizeHeading(_markerHeading + deltaDeg);
    });

    _predictionTimer = Timer.periodic(_predictionTickInterval, (_) {
      _applyPredictedMotionStep();
    });
  }

  void _stopSensorFusion() {
    _userAccelerometerSubscription?.cancel();
    _userAccelerometerSubscription = null;
    _gyroscopeSubscription?.cancel();
    _gyroscopeSubscription = null;
    _predictionTimer?.cancel();
    _predictionTimer = null;
    _lastGyroEventAt = null;
    _lastPredictionTickAt = null;
    _predictedDistanceSinceLastGps = 0.0;
    _isUsingPredictedPosition = false;
  }

  void _onGpsPositionUpdate(Position position) {
    final accuracyStatus = _stableGpsAccuracyStatusFor(position.accuracy);
    final canUseGpsForNavigation = accuracyStatus != _GpsAccuracyStatus.weak;
    final hasGoodAccuracy = accuracyStatus == _GpsAccuracyStatus.good;
    final now = DateTime.now();
    String? gpsRecoveryMessage;

    if (!canUseGpsForNavigation) {
      _arrivalConfirmationCount = 0;
      debugPrint(
        '[NAVIGATION] GPS low accuracy: ${position.accuracy.toStringAsFixed(1)}m',
      );
      final shouldAnnounceWeakGps =
          _lastGpsWeakAnnouncementAt == null ||
          now.difference(_lastGpsWeakAnnouncementAt!) >=
              _gpsWeakAnnouncementInterval;
      if (shouldAnnounceWeakGps) {
        final isFirstWeakAnnouncement = !_wasGpsWeak;
        final weakGpsMessage = isFirstWeakAnnouncement
            ? 'GPS lemah. Mohon berpindah ke area terbuka.'
            : 'GPS masih lemah.';
        _lastGpsWeakAnnouncementAt = now;
        unawaited(
          speakSafe(
            weakGpsMessage,
            priority: TtsPriority.warning,
            deduplicationKey: 'navigation-gps-weak-$weakGpsMessage',
            replacementKey: 'navigation-guidance',
            maxAge: const Duration(seconds: 10),
          ),
        );
        if (mounted) {
          AppFeedback.warning(context, weakGpsMessage);
        }
      }
      _wasGpsWeak = true;
    } else {
      _lastGpsWeakAnnouncementAt = null;
      if (_wasGpsWeak) {
        _wasGpsWeak = false;
        gpsRecoveryMessage = hasGoodAccuracy
            ? 'Akurasi GPS baik. Navigasi dilanjutkan.'
            : 'Akurasi GPS cukup. Navigasi dilanjutkan.';
        if (mounted) {
          AppFeedback.success(context, gpsRecoveryMessage);
        }
      }
    }

    final updatedLocation = LatLng(position.latitude, position.longitude);

    if (_lastGpsUpdateAt != null && _lastGpsLocation != null) {
      final dtSeconds =
          now.difference(_lastGpsUpdateAt!).inMilliseconds / 1000.0;
      if (dtSeconds > 0) {
        final distanceMeters = Geolocator.distanceBetween(
          _lastGpsLocation!.latitude,
          _lastGpsLocation!.longitude,
          updatedLocation.latitude,
          updatedLocation.longitude,
        );
        final instantSpeed = distanceMeters / dtSeconds;
        _estimatedSpeedMs =
            (_estimatedSpeedMs * 0.65) +
            (instantSpeed.clamp(0.0, _maxWalkingSpeedMs) * 0.35);
      }
    }

    _lastGpsUpdateAt = now;
    _lastGpsLocation = updatedLocation;
    _lastKnownGpsPosition = position;
    _lastPredictionTickAt = now;
    _predictedDistanceSinceLastGps = 0.0;

    final snapThresholdMeters = switch (accuracyStatus) {
      _GpsAccuracyStatus.good => _routeSnapThresholdMeters,
      _GpsAccuracyStatus.fair => _routeSnapThresholdMeters * 0.6,
      _GpsAccuracyStatus.weak => 0.0,
    };
    final snapResult = _snapPositionToRoute(
      updatedLocation,
      thresholdMeters: snapThresholdMeters,
    );
    final displayLocation = canUseGpsForNavigation
        ? snapResult.position
        : updatedLocation;

    setState(() {
      _userLocation = updatedLocation;
      _isUsingPredictedPosition = false;
      _currentSnappedRoutePoint = canUseGpsForNavigation && snapResult.snapped
          ? displayLocation
          : null;
      if (position.heading >= 0) {
        _markerHeading = _smoothHeading(
          _markerHeading,
          _normalizeHeading(position.heading),
        );
      }

      if (!_isLocationReady) {
        _isLocationReady = true;
      }
    });

    _animateUserLocation(displayLocation);

    if (canUseGpsForNavigation) {
      _addGpsCueSample(updatedLocation);
      final stabilizedCueLocation = _getStabilizedCueLocation(displayLocation);
      _confirmPendingTurn(stabilizedCueLocation);
    }

    if (hasGoodAccuracy && _confirmArrivalFromGps(updatedLocation)) {
      unawaited(_handleArrival());
      return;
    }

    if (canUseGpsForNavigation) {
      _updateLiveInstructionDistance(
        displayLocation,
        allowVoiceCue: gpsRecoveryMessage == null,
      );
      if (gpsRecoveryMessage != null) {
        _announceGpsRecoveryGuidance(gpsRecoveryMessage, displayLocation);
      }
      _updateRouteProgress(
        snapResult.segmentIndex,
        snapResult.distanceToRouteMeters,
      );
    }
    unawaited(
      _handleOffRouteDetection(
        distanceToRouteMeters: snapResult.distanceToRouteMeters,
        snapped: snapResult.snapped,
        gpsAccuracy: position.accuracy,
      ),
    );
    unawaited(
      _saveRoutePointIfNeeded(
        position: updatedLocation,
        isPredicted: false,
        heading: position.heading >= 0 ? position.heading : _markerHeading,
        speed: position.speed,
        accuracy: position.accuracy,
      ),
    );
  }

  void _applyPredictedMotionStep() {
    if (!mounted || !_isNavigating || _lastGpsUpdateAt == null) return;

    final now = DateTime.now();
    final gpsAge = now.difference(_lastGpsUpdateAt!);
    if (gpsAge < _gpsStaleThreshold) return;
    if (_predictedDistanceSinceLastGps >= _maxPredictionDistanceMeters) return;

    final tickFrom = _lastPredictionTickAt ?? now;
    _lastPredictionTickAt = now;
    final dtSeconds = now.difference(tickFrom).inMilliseconds / 1000.0;
    if (dtSeconds <= 0 || dtSeconds > 1.2) return;

    final isLikelyMoving = _smoothedAccelMagnitude > 0.08;
    if (!isLikelyMoving && _estimatedSpeedMs < 0.35) return;

    final accelBoost = (_smoothedAccelMagnitude * 0.55).clamp(0.0, 0.6);
    final predictedSpeed = (_estimatedSpeedMs + accelBoost).clamp(
      0.2,
      _maxWalkingSpeedMs,
    );
    final stepMeters = (predictedSpeed * dtSeconds).clamp(0.05, 1.2);

    final predictedTarget = _moveByMeters(
      start: _animatedUserLocation,
      bearingDeg: _markerHeading,
      distanceMeters: stepMeters,
    );
    _predictedDistanceSinceLastGps += stepMeters;

    final snapResult = _snapPositionToRoute(predictedTarget);
    final displayLocation = snapResult.position;

    setState(() {
      _animatedUserLocation = displayLocation;
      _isUsingPredictedPosition = true;
    });

    if (_isNavigating) {
      _safeMoveMap(displayLocation);
    }

    // Posisi prediksi hanya menghaluskan marker. Progres rute, instruksi,
    // deteksi keluar jalur, dan riwayat tetap menunggu GPS asli.
  }

  void _updateRouteProgress(int segmentIndex, double distanceToRouteMeters) {
    if (!_isNavigating || _routePoints.length < 2) return;

    if (distanceToRouteMeters > _routeTrimThresholdMeters) return;

    if (segmentIndex <= _lastPassedRouteIndex) return;

    if (mounted) {
      setState(() {
        _lastPassedRouteIndex = segmentIndex;
      });
    }
    unawaited(_syncRemainingRoutePolyline());
  }

  double _distanceBetweenPoints(LatLng start, LatLng end) {
    return Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
  }

  bool _isDirectionalTurn(TurnType turnType) {
    return switch (turnType) {
      TurnType.uturn ||
      TurnType.sharpRight ||
      TurnType.right ||
      TurnType.slightRight ||
      TurnType.slightLeft ||
      TurnType.left ||
      TurnType.sharpLeft => true,
      TurnType.straight || TurnType.unknown => false,
    };
  }

  double _distanceToPolyline(LatLng position, List<LatLng> polylinePoints) {
    if (polylinePoints.isEmpty) return double.infinity;
    if (polylinePoints.length == 1) {
      return _distanceBetweenPoints(position, polylinePoints.first);
    }

    var bestDistance = double.infinity;
    for (var i = 0; i < polylinePoints.length - 1; i++) {
      final projected = _projectPointToSegment(
        position,
        polylinePoints[i],
        polylinePoints[i + 1],
      );
      final distance = _distanceBetweenPoints(position, projected);
      if (distance < bestDistance) {
        bestDistance = distance;
      }
    }
    return bestDistance;
  }

  bool _hasReachedDestination(LatLng currentLocation) {
    if (!_isNavigating || _hasArrivedAtDestination || _selectedPlace == null) {
      return false;
    }

    final destination = LatLng(
      _selectedPlace!.latitude,
      _selectedPlace!.longitude,
    );
    final distanceToDestination = _distanceBetweenPoints(
      currentLocation,
      destination,
    );

    if (distanceToDestination <= _arrivalThresholdMeters) {
      return true;
    }

    final remainingRouteMeters = _remainingDistanceAlongPolyline(
      currentLocation,
      _routePoints,
    );
    return remainingRouteMeters != null &&
        remainingRouteMeters <= _routeEndArrivalThresholdMeters &&
        distanceToDestination <= _routeEndDestinationToleranceMeters;
  }

  bool _confirmArrivalFromGps(LatLng currentLocation) {
    if (!_hasReachedDestination(currentLocation)) {
      _arrivalConfirmationCount = 0;
      return false;
    }

    _arrivalConfirmationCount++;
    return _arrivalConfirmationCount >= _requiredArrivalConfirmations;
  }

  double? _remainingDistanceAlongPolyline(
    LatLng currentPosition,
    List<LatLng> polylinePoints,
  ) {
    if (polylinePoints.isEmpty) return null;
    if (polylinePoints.length == 1) {
      return _distanceBetweenPoints(currentPosition, polylinePoints.first);
    }

    var bestSegmentIndex = 0;
    var bestProjectedPoint = polylinePoints.first;
    var bestDistanceToSegment = double.infinity;

    for (var i = 0; i < polylinePoints.length - 1; i++) {
      final projected = _projectPointToSegment(
        currentPosition,
        polylinePoints[i],
        polylinePoints[i + 1],
      );
      final distanceToSegment = _distanceBetweenPoints(
        currentPosition,
        projected,
      );

      if (distanceToSegment < bestDistanceToSegment) {
        bestDistanceToSegment = distanceToSegment;
        bestSegmentIndex = i;
        bestProjectedPoint = projected;
      }
    }

    var remainingMeters = _distanceBetweenPoints(
      bestProjectedPoint,
      polylinePoints[bestSegmentIndex + 1],
    );

    for (var i = bestSegmentIndex + 1; i < polylinePoints.length - 1; i++) {
      remainingMeters += _distanceBetweenPoints(
        polylinePoints[i],
        polylinePoints[i + 1],
      );
    }

    return remainingMeters;
  }

  double? _remainingDistanceToAnchorAlongPolyline(
    LatLng currentPosition,
    List<LatLng> polylinePoints,
    LatLng anchor,
  ) {
    if (polylinePoints.isEmpty) return null;
    if (polylinePoints.length == 1) {
      return _distanceBetweenPoints(currentPosition, anchor);
    }

    var bestAnchorSegmentIndex = 0;
    var bestProjectedAnchor = polylinePoints.last;
    var bestAnchorDistance = double.infinity;

    for (var index = 0; index < polylinePoints.length - 1; index++) {
      final projected = _projectPointToSegment(
        anchor,
        polylinePoints[index],
        polylinePoints[index + 1],
      );
      final distance = _distanceBetweenPoints(anchor, projected);
      if (distance < bestAnchorDistance) {
        bestAnchorDistance = distance;
        bestAnchorSegmentIndex = index;
        bestProjectedAnchor = projected;
      }
    }

    final pointsUntilAnchor = <LatLng>[
      ...polylinePoints.sublist(0, bestAnchorSegmentIndex + 1),
      bestProjectedAnchor,
    ];

    return _remainingDistanceAlongPolyline(currentPosition, pointsUntilAnchor);
  }

  void _updateLiveInstructionDistance(
    LatLng displayLocation, {
    required bool allowVoiceCue,
  }) {
    if (!_isNavigating ||
        _navigationInstructions.isEmpty ||
        _currentInstructionIndex >= _navigationInstructions.length) {
      if (_currentInstructionRemainingMeters != null && mounted) {
        setState(() {
          _currentInstructionRemainingMeters = null;
        });
      }
      return;
    }

    final instruction = _navigationInstructions[_currentInstructionIndex];
    final remainingMeters = _remainingDistanceAlongPolyline(
      displayLocation,
      instruction.polylinePoints,
    );
    if (remainingMeters == null) return;

    final previousRemaining = _currentInstructionRemainingMeters;
    final shouldUpdateUi =
        previousRemaining == null ||
        (previousRemaining - remainingMeters).abs() >= 1.0;

    if (shouldUpdateUi && mounted) {
      setState(() {
        _currentInstructionRemainingMeters = remainingMeters;
      });
    }

    if (allowVoiceCue) {
      _announceInstructionCueIfNeeded(remainingMeters, displayLocation);
    }
  }

  void _announceGpsRecoveryGuidance(
    String recoveryMessage,
    LatLng displayLocation,
  ) {
    var guidanceMessage = recoveryMessage;

    if (_isNavigating &&
        _navigationInstructions.isNotEmpty &&
        _currentInstructionIndex < _navigationInstructions.length) {
      final instruction = _navigationInstructions[_currentInstructionIndex];
      final remainingMeters =
          _remainingDistanceAlongPolyline(
            displayLocation,
            instruction.polylinePoints,
          ) ??
          _currentInstructionRemainingMeters ??
          instruction.distance;
      final distanceText = _formatRouteDistanceSpeech(remainingMeters);
      guidanceMessage =
          '$recoveryMessage Instruksi saat ini, ${instruction.instruction}. '
          'Sisa sekitar $distanceText.';
    }

    unawaited(
      speakSafe(
        guidanceMessage,
        priority: TtsPriority.navigation,
        deduplicationKey: 'navigation-gps-recovered-guidance',
        replacementKey: 'navigation-guidance',
        maxAge: const Duration(seconds: 10),
      ),
    );
  }

  void _announceInstructionCueIfNeeded(
    double remainingMeters,
    LatLng displayLocation,
  ) {
    if (_currentInstructionIndex >= _navigationInstructions.length) return;
    if (_pendingTurnSourceInstructionIndex == _currentInstructionIndex) return;
    if (_isSpeaking) return;

    final gpsAccuracy = _lastKnownGpsPosition?.accuracy;
    if (gpsAccuracy == null || !_canUseGpsForNavigation(gpsAccuracy)) {
      _maneuverConfirmationCounts[_currentInstructionIndex] = 0;
      return;
    }
    final isFairAccuracy =
        (_stableGpsAccuracyStatus ?? _gpsAccuracyStatus(gpsAccuracy)) ==
        _GpsAccuracyStatus.fair;

    final instruction = _navigationInstructions[_currentInstructionIndex];
    final nextInstructionIndex = _currentInstructionIndex + 1;
    final hasNextInstruction =
        nextInstructionIndex < _navigationInstructions.length;
    final nextInstruction = hasNextInstruction
        ? _navigationInstructions[nextInstructionIndex]
        : null;
    final hasNextTurn =
        nextInstruction != null && _isDirectionalTurn(nextInstruction.turnType);
    final cueInstruction = nextInstruction != null
        ? nextInstruction.instruction
        : 'tujuan berada di depan';
    final cueLocation = _resolveTurnAnchor(instruction, nextInstructionIndex);
    final distanceToCueLocation = cueLocation == null
        ? remainingMeters
        : _distanceBetweenPoints(displayLocation, cueLocation);
    final remainingToCueMeters = cueLocation == null
        ? remainingMeters
        : _remainingDistanceToAnchorAlongPolyline(
                displayLocation,
                instruction.polylinePoints,
                cueLocation,
              ) ??
              remainingMeters;
    final conservativeDistance = math.max(
      remainingToCueMeters,
      distanceToCueLocation,
    );
    final previousDistance = _lastDistanceToManeuver[_currentInstructionIndex];
    final isApproaching =
        previousDistance == null ||
        distanceToCueLocation <= previousDistance + 0.5;
    _lastDistanceToManeuver[_currentInstructionIndex] = distanceToCueLocation;

    final gpsSpeed = _lastKnownGpsPosition?.speed ?? 0;
    final effectiveSpeed = math.max(
      gpsSpeed.isFinite && gpsSpeed >= 0 ? gpsSpeed : 0,
      _estimatedSpeedMs,
    );
    final isWalking =
        effectiveSpeed >= _minimumWalkingSpeedMs &&
        effectiveSpeed <= _maximumWalkingCueSpeedMs;
    final maneuverZone = _maneuverZoneMeters(gpsAccuracy);
    final canConfirmTurnArea =
        hasNextTurn &&
        maneuverZone > 0 &&
        remainingToCueMeters <= maneuverZone &&
        distanceToCueLocation <= maneuverZone + 2 &&
        isApproaching &&
        isWalking;

    if (canConfirmTurnArea) {
      final now = DateTime.now();
      final lastConfirmation =
          _lastManeuverConfirmationAt[_currentInstructionIndex];
      if (lastConfirmation != null &&
          now.difference(lastConfirmation) < _maneuverConfirmationInterval) {
        return;
      }

      _lastManeuverConfirmationAt[_currentInstructionIndex] = now;
      final confirmationCount =
          (_maneuverConfirmationCounts[_currentInstructionIndex] ?? 0) + 1;
      _maneuverConfirmationCounts[_currentInstructionIndex] = confirmationCount;
      final requiredConfirmations = isFairAccuracy
          ? _requiredFairAccuracyManeuverConfirmations
          : _requiredManeuverConfirmations;
      if (confirmationCount < requiredConfirmations) {
        return;
      }

      _announceTurnArea(
        sourceInstructionIndex: _currentInstructionIndex,
        nextInstructionIndex: nextInstructionIndex,
        cueInstruction: cueInstruction,
        displayLocation: displayLocation,
      );
      return;
    }

    if (!hasNextTurn &&
        conservativeDistance <= _turnAreaDistanceMeters &&
        _announcedNowInstructionIndexes.add(_currentInstructionIndex)) {
      unawaited(
        speakSafe(
          'Tujuan berada di depan.',
          priority: TtsPriority.navigation,
          deduplicationKey:
              'navigation-destination-ahead-$_currentInstructionIndex',
          replacementKey: 'navigation-guidance',
          maxAge: const Duration(seconds: 8),
        ),
      );
      return;
    }

    _maneuverConfirmationCounts[_currentInstructionIndex] = 0;
    _lastManeuverConfirmationAt.remove(_currentInstructionIndex);

    final cueMeters = conservativeDistance <= 20
        ? 20
        : conservativeDistance <= 30
        ? 30
        : conservativeDistance <= 50
        ? 50
        : null;
    if (cueMeters == null) return;

    final announcedCueMeters = _announcedInstructionCueMeters.putIfAbsent(
      _currentInstructionIndex,
      () => <int>{},
    );
    if (cueMeters == 50 &&
        (announcedCueMeters.contains(30) || announcedCueMeters.contains(20))) {
      return;
    }
    if (cueMeters == 30 && announcedCueMeters.contains(20)) return;
    if (!announcedCueMeters.add(cueMeters)) return;

    unawaited(
      speakSafe(
        "Dalam $cueMeters meter, $cueInstruction",
        priority: TtsPriority.navigation,
        deduplicationKey: 'navigation-cue-$_currentInstructionIndex-$cueMeters',
        replacementKey: 'navigation-guidance',
        maxAge: const Duration(seconds: 8),
      ),
    );
  }

  void _announceTurnArea({
    required int sourceInstructionIndex,
    required int nextInstructionIndex,
    required String cueInstruction,
    required LatLng displayLocation,
  }) {
    if (!_announcedNowInstructionIndexes.add(sourceInstructionIndex)) return;

    unawaited(
      _speakTurnAreaThenWaitForTurn(
        sourceInstructionIndex: sourceInstructionIndex,
        nextInstructionIndex: nextInstructionIndex,
        cueInstruction: cueInstruction,
        displayLocation: displayLocation,
      ),
    );
  }

  Future<void> _speakTurnAreaThenWaitForTurn({
    required int sourceInstructionIndex,
    required int nextInstructionIndex,
    required String cueInstruction,
    required LatLng displayLocation,
  }) async {
    if (!mounted ||
        !_isNavigating ||
        _currentInstructionIndex != sourceInstructionIndex) {
      return;
    }

    if (nextInstructionIndex < _navigationInstructions.length) {
      final nextInstruction = _navigationInstructions[nextInstructionIndex];
      final outgoingHeading =
          _polylineHeading(nextInstruction.polylinePoints, fromEnd: false) ??
          _normalizeHeading(nextInstruction.bearing);

      _pendingTurnSourceInstructionIndex = sourceInstructionIndex;
      _pendingTurnNextInstructionIndex = nextInstructionIndex;
      _pendingTurnExpectedHeading = outgoingHeading;
      _pendingTurnStartLocation = displayLocation;
    }

    final turnAreaInstruction =
        nextInstructionIndex < _navigationInstructions.length
        ? _turnAreaInstruction(
            _navigationInstructions[nextInstructionIndex].turnType,
            cueInstruction,
          )
        : _turnAreaInstruction(TurnType.unknown, cueInstruction);

    await speakSafe(
      'Anda sudah masuk $turnAreaInstruction.',
      priority: TtsPriority.navigation,
      deduplicationKey: 'navigation-turn-area-$sourceInstructionIndex',
      replacementKey: 'navigation-guidance',
      maxAge: const Duration(seconds: 6),
    );

    if (!mounted ||
        !_isNavigating ||
        _currentInstructionIndex != sourceInstructionIndex ||
        nextInstructionIndex >= _navigationInstructions.length) {
      return;
    }

    if (_pendingTurnSourceInstructionIndex == sourceInstructionIndex) {
      _confirmPendingTurn(_getStabilizedCueLocation(displayLocation));
      return;
    }

    setState(() {
      _currentInstructionIndex = nextInstructionIndex;
      _currentInstructionRemainingMeters = null;
    });

    _updateLiveInstructionDistance(displayLocation, allowVoiceCue: false);
  }

  Future<void> _syncRemainingRoutePolyline() async {
    final tripId = _currentTripId;
    if (tripId == null) return;

    final remainingPoints = _getRemainingRoutePoints();
    if (remainingPoints.isEmpty) return;

    await _navigationHistoryService.updateRemainingRoutePolyline(
      tripId: tripId,
      remainingRoutePolyline: remainingPoints,
    );
  }

  Future<void> _handleOffRouteDetection({
    required double distanceToRouteMeters,
    required bool snapped,
    required double gpsAccuracy,
  }) async {
    if (!_isNavigating || _selectedPlace == null) return;
    if (_isLoadingRoute) return;

    final now = DateTime.now();

    final accuracyAllowance = gpsAccuracy.isFinite
        ? gpsAccuracy.clamp(0.0, 20.0) * 0.5
        : 0.0;
    final effectiveOffRouteThreshold =
        _offRouteThresholdMeters + accuracyAllowance;

    if (snapped || distanceToRouteMeters <= effectiveOffRouteThreshold) {
      _updateOffRouteEventState(false, location: _userLocation);
      _offRouteSince = null;
      if (_isOffRouteWarningVisible && mounted) {
        setState(() {
          _isOffRouteWarningVisible = false;
        });
      }
      return;
    }

    if (!_isOffRouteWarningVisible && mounted) {
      setState(() {
        _isOffRouteWarningVisible = true;
      });
    }

    final inCooldown =
        _lastRerouteAt != null &&
        now.difference(_lastRerouteAt!) < _rerouteCooldown;
    if (inCooldown) return;

    _offRouteSince ??= now;
    if (now.difference(_offRouteSince!) < _offRouteConfirmDuration) return;

    _offRouteSince = null;
    _lastRerouteAt = now;
    _updateOffRouteEventState(true, location: _userLocation);

    await _analyticsService.logOffRouteDetected(
      destinationName: _selectedPlace?.name ?? 'unknown',
      distanceToRouteMeters: distanceToRouteMeters,
    );

    if (mounted) {
      setState(() {
        _isOffRouteWarningVisible = false;
      });
    }

    if (!mounted) return;

    unawaited(
      speakSafe(
        'Anda keluar jalur. Menghitung ulang rute',
        priority: TtsPriority.warning,
        deduplicationKey: 'navigation-off-route',
        replacementKey: 'navigation-guidance',
        maxAge: const Duration(seconds: 10),
      ),
    );

    AppFeedback.warning(
      context,
      'Anda keluar jalur. Rute sedang dihitung ulang.',
    );

    await _loadRoute();
  }

  List<LatLng> _getPassedRoutePoints() {
    if (_routePoints.length < 2) {
      return [];
    }

    final snappedPoint = _currentSnappedRoutePoint;
    if (snappedPoint == null) {
      if (_lastPassedRouteIndex <= 0) return [];
      final endIndex = (_lastPassedRouteIndex + 1)
          .clamp(0, _routePoints.length)
          .toInt();
      final points = _routePoints.sublist(0, endIndex);
      return points.length >= 2 ? points : [];
    }

    final endIndex = (_lastPassedRouteIndex + 1)
        .clamp(0, _routePoints.length - 1)
        .toInt();
    final points = <LatLng>[..._routePoints.sublist(0, endIndex), snappedPoint];
    return points.length >= 2 ? points : [];
  }

  List<LatLng> _getRemainingRoutePoints() {
    if (_routePoints.length < 2) {
      return [];
    }

    final snappedPoint = _currentSnappedRoutePoint;
    if (snappedPoint == null) {
      final startIndex = _lastPassedRouteIndex
          .clamp(0, _routePoints.length - 1)
          .toInt();
      final points = _routePoints.sublist(startIndex);
      return points.length >= 2 ? points : [];
    }

    final startIndex = (_lastPassedRouteIndex + 1)
        .clamp(0, _routePoints.length - 1)
        .toInt();
    final points = <LatLng>[snappedPoint, ..._routePoints.sublist(startIndex)];
    return points.length >= 2 ? points : [];
  }

  LatLng _projectPointToSegment(LatLng point, LatLng start, LatLng end) {
    final referenceLatitude =
        (point.latitude + start.latitude + end.latitude) / 3;
    final latitudeScale = math.cos(referenceLatitude * (math.pi / 180.0));
    final safeScale = latitudeScale.abs() < 1e-8 ? 1.0 : latitudeScale;

    final ax = start.longitude * safeScale;
    final ay = start.latitude;
    final bx = end.longitude * safeScale;
    final by = end.latitude;
    final px = point.longitude * safeScale;
    final py = point.latitude;

    final dx = bx - ax;
    final dy = by - ay;

    if (dx == 0 && dy == 0) {
      return start;
    }

    final t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
    final clampedT = t.clamp(0.0, 1.0).toDouble();

    final projectedX = ax + clampedT * dx;
    final projectedY = ay + clampedT * dy;

    return LatLng(projectedY, projectedX / safeScale);
  }

  ({
    LatLng position,
    double distanceToRouteMeters,
    bool snapped,
    int segmentIndex,
  })
  _snapPositionToRoute(
    LatLng currentPosition, {
    double thresholdMeters = _routeSnapThresholdMeters,
  }) {
    if (_routePoints.length < 2) {
      return (
        position: currentPosition,
        distanceToRouteMeters: double.infinity,
        snapped: false,
        segmentIndex: 0,
      );
    }

    final searchFrom = math.max(0, _lastPassedRouteIndex - 3);
    var bestDistance = double.infinity;
    LatLng bestPosition = currentPosition;
    var bestSegmentIndex = _lastPassedRouteIndex
        .clamp(0, _routePoints.length - 2)
        .toInt();

    for (var i = searchFrom; i < _routePoints.length - 1; i++) {
      final start = _routePoints[i];
      final end = _routePoints[i + 1];
      final projected = _projectPointToSegment(currentPosition, start, end);
      final distanceToRoute = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        projected.latitude,
        projected.longitude,
      );

      if (distanceToRoute < bestDistance) {
        bestDistance = distanceToRoute;
        bestPosition = projected;
        bestSegmentIndex = i;
      }
    }

    if (bestDistance <= thresholdMeters) {
      return (
        position: bestPosition,
        distanceToRouteMeters: bestDistance,
        snapped: true,
        segmentIndex: bestSegmentIndex,
      );
    }

    return (
      position: currentPosition,
      distanceToRouteMeters: bestDistance,
      snapped: false,
      segmentIndex: bestSegmentIndex,
    );
  }

  /// Load places from Firestore
  Future<void> _loadPlaces() async {
    try {
      final places = await _placesService.getAllPlaces();

      setState(() {
        _places = places;
        _isLoadingPlaces = false;
      });
    } catch (e) {
      setState(() => _isLoadingPlaces = false);
      // Fallback: use mock locations
      setState(() {
        _places = [];
      });
    }
  }

  Future<void> _getUserLocation() async {
    try {
      // Check if location service is enabled
      bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!isServiceEnabled) {
        setState(() {
          _userLocation = defaultLocation;
          _isLocationReady = false;
        });
        AppFeedback.warning(
          context,
          'Layanan lokasi belum aktif. Aktifkan GPS untuk memulai navigasi.',
          actionLabel: 'Buka pengaturan',
          onAction: () => unawaited(Geolocator.openLocationSettings()),
          announce: true,
        );
        return;
      }

      // Check and request location permission
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _userLocation = defaultLocation;
          _isLocationReady = false; // Keep false - using default location
        });
        AppFeedback.warning(
          context,
          'Izin lokasi dinonaktifkan permanen. Buka pengaturan aplikasi lalu izinkan lokasi.',
          actionLabel: 'Buka pengaturan',
          onAction: () => unawaited(Geolocator.openAppSettings()),
          announce: true,
        );
        return;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        try {
          Position position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              timeLimit: Duration(seconds: 60),
            ),
          );

          if (mounted) {
            setState(() {
              _userLocation = LatLng(position.latitude, position.longitude);
              _animatedUserLocation = _userLocation;
              if (position.heading >= 0) {
                _markerHeading = _normalizeHeading(position.heading);
              }
              _isLocationReady = true;
            });

            _safeMoveMap(_userLocation, 18.0);
          }
        } catch (e) {
          setState(() {
            _userLocation = defaultLocation;
            _isLocationReady = false; // Keep false - using default location
          });
        }
      }
    } catch (e) {
      setState(() {
        _userLocation = defaultLocation;
        _isLocationReady = false; // Keep false - using default location
      });
    }
  }

  /// Start continuous location streaming for detailed navigation
  /// Called when user starts navigating to a destination
  void _startLocationStreaming() {
    if (_selectedPlace != null) {
      speakSafe("Memulai navigasi ke ${_selectedPlace!.name}");
    }

    _startSensorFusion();

    bool hasLoadedRouteOnceFromStreaming =
        false; // Track if route loaded from streaming

    unawaited(
      _liveTrackingService.startNavigationTracking(
        destinationName: _selectedPlace?.name,
        onPosition: (Position position) {
          if (mounted) {
            _onGpsPositionUpdate(position);

            // Bentuk rute dari pembacaan GPS pertama. Akurasi GPS tetap
            // divalidasi saat memperbarui progres rute dan status tiba.
            if (!hasLoadedRouteOnceFromStreaming && _selectedPlace != null) {
              _loadRoute();
              hasLoadedRouteOnceFromStreaming = true;
            }
          }
        },
        onError: (e) {
          // ignore location stream errors during navigation
        },
      ),
    );
  }

  /// Stop continuous location streaming to save battery
  void _stopLocationStreaming() {
    unawaited(_liveTrackingService.stopNavigationTracking());
    _stopSensorFusion();
  }

  String _formatRouteDistanceSpeech(double distanceMeters) {
    if (distanceMeters >= 1000) {
      return "${(distanceMeters / 1000).toStringAsFixed(1)} kilometer";
    }

    return "${distanceMeters.round()} meter";
  }

  String _formatRouteDurationSpeech(double durationMinutes) {
    if (durationMinutes < 1) {
      return "kurang dari satu menit";
    }

    return "${durationMinutes.round()} menit";
  }

  bool shouldSaveRoutePoint(LatLng currentPosition) {
    if (_currentTripId == null) return false;

    final lastLocation = _lastRoutePointLocation;
    if (lastLocation == null) return true;

    final distanceMeters = Geolocator.distanceBetween(
      lastLocation.latitude,
      lastLocation.longitude,
      currentPosition.latitude,
      currentPosition.longitude,
    );
    if (distanceMeters >= 5) return true;

    final lastSavedAt = _lastRoutePointSavedAt;
    if (lastSavedAt == null) return true;

    return DateTime.now().difference(lastSavedAt).inSeconds >= 5;
  }

  Future<void> _saveRoutePointIfNeeded({
    required LatLng position,
    required bool isPredicted,
    double? heading,
    double? speed,
    double? accuracy,
    bool force = false,
  }) async {
    final tripId = _currentTripId;
    if (tripId == null) return;
    if (!force && !shouldSaveRoutePoint(position)) return;

    final savedAt = DateTime.now();
    _lastRoutePointLocation = position;
    _lastRoutePointSavedAt = savedAt;

    await _navigationHistoryService.addRoutePoint(
      tripId: tripId,
      lat: position.latitude,
      lng: position.longitude,
      heading: heading ?? _markerHeading,
      speed: speed ?? _estimatedSpeedMs,
      accuracy: accuracy ?? _lastKnownGpsPosition?.accuracy ?? 0.0,
      isPredicted: isPredicted,
    );
  }

  Future<void> _saveFinalRoutePointIfAvailable() async {
    final tripId = _currentTripId;
    if (tripId == null) return;

    final lastGpsPosition = _lastKnownGpsPosition;
    if (lastGpsPosition != null && !_isUsingPredictedPosition) {
      await _saveRoutePointIfNeeded(
        position: LatLng(lastGpsPosition.latitude, lastGpsPosition.longitude),
        isPredicted: false,
        heading: lastGpsPosition.heading >= 0
            ? lastGpsPosition.heading
            : _markerHeading,
        speed: lastGpsPosition.speed,
        accuracy: lastGpsPosition.accuracy,
        force: true,
      );
      return;
    }

    await _saveRoutePointIfNeeded(
      position: _animatedUserLocation,
      isPredicted: _isUsingPredictedPosition,
      heading: _markerHeading,
      speed: _estimatedSpeedMs,
      accuracy: lastGpsPosition?.accuracy ?? 0.0,
      force: true,
    );
  }

  Future<void> _addTripEvent({required String type, LatLng? location}) async {
    final tripId = _currentTripId;
    if (tripId == null) return;

    final eventLocation = location ?? _lastEventLocation();
    await _navigationHistoryService.addTripEvent(
      tripId: tripId,
      type: type,
      lat: eventLocation?.latitude,
      lng: eventLocation?.longitude,
    );
  }

  LatLng? _lastEventLocation() {
    final gpsPosition = _lastKnownGpsPosition;
    if (gpsPosition != null && !_isUsingPredictedPosition) {
      return LatLng(gpsPosition.latitude, gpsPosition.longitude);
    }

    if (_animatedUserLocation != defaultLocation) {
      return _animatedUserLocation;
    }

    if (_userLocation != defaultLocation) {
      return _userLocation;
    }

    return null;
  }

  void _updateOffRouteEventState(bool offRouteNow, {LatLng? location}) {
    if (offRouteNow && !_wasOffRoute) {
      unawaited(_addTripEvent(type: 'off_route', location: location));
    } else if (!offRouteNow && _wasOffRoute) {
      unawaited(_addTripEvent(type: 'back_to_route', location: location));
    }

    _wasOffRoute = offRouteNow;
  }

  void recordSosPressedEvent() {
    unawaited(_addTripEvent(type: 'sos_pressed'));
  }

  Future<void> _startTripHistoryIfNeeded() async {
    if (_currentTripId != null || _isStartingTripHistory) return;
    if (_selectedPlace == null || !_isNavigating) return;

    _isStartingTripHistory = true;
    try {
      final selectedPlace = _selectedPlace!;
      final tripId = await _navigationHistoryService.startTrip(
        originName: 'Lokasi awal',
        destinationName: selectedPlace.name,
        originLat: _userLocation.latitude,
        originLng: _userLocation.longitude,
        destinationLat: selectedPlace.latitude,
        destinationLng: selectedPlace.longitude,
        totalDistanceMeters: _routeDistanceMeters,
        routePolyline: _routePoints,
        remainingRoutePolyline: _routePoints,
      );

      if (tripId == null) return;

      if (!mounted || !_isNavigating) {
        final startedAt = _tripStartedAt ?? _navigationStartTime;
        final durationSeconds = startedAt == null
            ? 0
            : DateTime.now().difference(startedAt).inSeconds;
        await _navigationHistoryService.cancelTrip(
          tripId: tripId,
          durationSeconds: durationSeconds < 0 ? 0 : durationSeconds,
          totalDistanceMeters: _routeDistanceMeters,
        );
        await _liveTrackingService.updateNavigationTripState(
          currentTripId: null,
          isNavigating: false,
        );
        return;
      }

      _currentTripId = tripId;
      _tripStartedAt ??= _navigationStartTime ?? DateTime.now();
      await _liveTrackingService.updateNavigationTripState(
        currentTripId: tripId,
        isNavigating: true,
      );
      _lastRoutePointLocation = null;
      _lastRoutePointSavedAt = null;
      await _saveRoutePointIfNeeded(
        position: _userLocation,
        isPredicted: false,
        heading: _markerHeading,
        speed: _lastKnownGpsPosition?.speed ?? _estimatedSpeedMs,
        accuracy: _lastKnownGpsPosition?.accuracy ?? 0.0,
        force: true,
      );
      await _addTripEvent(type: 'navigation_started', location: _userLocation);
      debugPrint('[NAV_HISTORY] Started trip: $tripId');
    } catch (e, st) {
      debugPrint('[NAV_HISTORY] Failed to start trip history: $e');
      debugPrintStack(stackTrace: st);
    } finally {
      _isStartingTripHistory = false;
    }
  }

  Future<void> _finishCurrentTripHistory({
    required bool completed,
    required int durationSeconds,
    required double totalDistanceMeters,
  }) async {
    final tripId = _currentTripId;
    if (tripId == null) return;

    try {
      await _saveFinalRoutePointIfAvailable();

      // Get the last known position for end coordinates
      double? endLat;
      double? endLng;

      final gpsPosition = _lastKnownGpsPosition;
      if (gpsPosition != null && !_isUsingPredictedPosition) {
        endLat = gpsPosition.latitude;
        endLng = gpsPosition.longitude;
      } else if (_animatedUserLocation.latitude != 0.0 ||
          _animatedUserLocation.longitude != 0.0) {
        endLat = _animatedUserLocation.latitude;
        endLng = _animatedUserLocation.longitude;
      } else if (_userLocation.latitude != 0.0 ||
          _userLocation.longitude != 0.0) {
        endLat = _userLocation.latitude;
        endLng = _userLocation.longitude;
      }

      if (completed) {
        await _navigationHistoryService.finishTrip(
          tripId: tripId,
          durationSeconds: durationSeconds,
          totalDistanceMeters: totalDistanceMeters,
          endLat: endLat,
          endLng: endLng,
        );
      } else {
        await _navigationHistoryService.cancelTrip(
          tripId: tripId,
          durationSeconds: durationSeconds,
          totalDistanceMeters: totalDistanceMeters,
          endLat: endLat,
          endLng: endLng,
        );
      }
      debugPrint(
        '[NAV_HISTORY] ${completed ? 'Completed' : 'Cancelled'} trip: $tripId',
      );
    } catch (e, st) {
      debugPrint('[NAV_HISTORY] Failed to finish trip history: $e');
      debugPrintStack(stackTrace: st);
    } finally {
      await _liveTrackingService.updateNavigationTripState(
        currentTripId: null,
        isNavigating: false,
      );
      _currentTripId = null;
      _tripStartedAt = null;
      _lastRoutePointLocation = null;
      _lastRoutePointSavedAt = null;
      _lastKnownGpsPosition = null;
      _wasOffRoute = false;
    }
  }

  Future<void> _endNavigationSession({
    bool returnToPlaceList = true,
    String endReason = 'manual_exit',
  }) async {
    await _ttsService.cancelByReplacementKey('navigation-guidance');

    final wasNavigating = _isNavigating;
    final navigationStartedAt = _tripStartedAt ?? _navigationStartTime;
    final destinationName = _selectedPlace?.name ?? 'unknown';
    final remainingDistanceKm = _routeDistanceKm;
    final totalDistanceMeters = _routeDistanceMeters;
    final durationSeconds = navigationStartedAt == null
        ? 0
        : DateTime.now().difference(navigationStartedAt).inSeconds;

    if (wasNavigating) {
      unawaited(
        _analyticsService.logEndNavigation(
          destinationName: destinationName,
          endReason: endReason,
          durationSeconds: durationSeconds < 0 ? 0 : durationSeconds,
          remainingDistanceKm: remainingDistanceKm,
        ),
      );
    }

    if (wasNavigating && _currentTripId != null) {
      await _addTripEvent(
        type: endReason == 'arrived' ? 'arrived' : 'navigation_cancelled',
      );
    }

    await _finishCurrentTripHistory(
      completed: endReason == 'arrived',
      durationSeconds: durationSeconds < 0 ? 0 : durationSeconds,
      totalDistanceMeters: totalDistanceMeters,
    );

    if (!mounted) return;

    _stopLocationStreaming();
    _stopNavigationTracking();

    setState(() {
      _routePoints.clear();
      _lastPassedRouteIndex = 0;
      _currentSnappedRoutePoint = null;
      _offRouteSince = null;
      _lastRerouteAt = null;
      _isOffRouteWarningVisible = false;
      _lastGpsWeakAnnouncementAt = null;
      _wasGpsWeak = false;
      _resetGpsAccuracyStatusStabilizer();
      _navigationInstructions = [];
      _currentInstructionIndex = 0;
      _currentInstructionRemainingMeters = null;
      _announcedInstructionCueMeters.clear();
      _announcedNowInstructionIndexes.clear();
      _maneuverConfirmationCounts.clear();
      _turnCompletionConfirmationCounts.clear();
      _lastManeuverConfirmationAt.clear();
      _lastDistanceToManeuver.clear();
      _gpsCueWindow.clear();
      _clearPendingTurn();
      _routeDistanceKm = 0.0;
      _routeDurationMinutes = 0.0;
      _routeDistanceMeters = 0.0;
      _routeDurationSeconds = 0.0;
      _routeLoadError = '';
      _isLoadingRoute = false;
      _hasArrivedAtDestination = false;
      _arrivalConfirmationCount = 0;
      _isUsingPredictedPosition = false;
      _tripStartedAt = null;
      if (returnToPlaceList) {
        _selectedPlace = null;
      }
    });
  }

  @override
  void dispose() {
    TTSService.onSpeechStartHook = null;
    TTSService.onSpeechSendHook = null;
    TTSService.onTtsStopStartHook = null;
    SosService.onAuthDone = null;
    SosService.onFirestoreDone = null;
    SosService.onWorkerDone = null;
    LiveTrackingService.onWriteStart = null;
    LiveTrackingService.onBatteryDone = null;
    LiveTrackingService.onGetWriteStartMs = null;
    LiveTrackingService.onGetSampleNum = null;
    RealtimeLiveTrackingService.onRtdbWriteDone = null;
    WidgetsBinding.instance.removeObserver(this);
    _smartCaneBleService.setNavigationHazardAnnouncementsEnabled(false);
    _smartCaneBleService.removeListener(_handleSmartCaneConnectionChanged);
    if (_currentTripId != null) {
      final startedAt = _tripStartedAt ?? _navigationStartTime;
      final durationSeconds = startedAt == null
          ? 0
          : DateTime.now().difference(startedAt).inSeconds;
      unawaited(
        _finishCurrentTripHistory(
          completed: false,
          durationSeconds: durationSeconds < 0 ? 0 : durationSeconds,
          totalDistanceMeters: _routeDistanceMeters,
        ),
      );
    }
    _mapController.dispose();
    _stopSensorFusion();
    _durationUpdateTimer?.cancel(); // Cancel duration update timer
    _smartCaneSensorSubscription?.cancel();
    _smartCaneButtonSubscription?.cancel();
    // _fallEventSubscription?.cancel();
    _locationAnimationController
      ..removeListener(_onLocationAnimationTick)
      ..dispose();
    unawaited(_liveTrackingService.stopNavigationTracking());
    if (!_suppressTtsStopOnDispose) unawaited(_ttsService.stop());
    _stopNavigationStt();
    super.dispose();
  }

  void _goToLocation(LatLng location) {
    _safeMoveMap(location, 18.0);
  }

  String get _ultrasonicSensorText {
    final data = _latestSmartCaneSensorData;
    if (!_smartCaneBleService.isConnected) {
      return 'Sensor dan model belum terhubung';
    }
    if (data == null) {
      return 'Menunggu data dari SmartCane.';
    }

    final base = data.displayText;
    if (data.detections.isEmpty) return base;

    final detectedLabels = data.detections
        .map((d) => d.localizedLabel)
        .toSet()
        .join(', ');

    // Hindari duplikasi jika label sudah muncul di teks dasar
    final baseLower = base.toLowerCase();
    final firstLabel = detectedLabels.split(',').first.trim().toLowerCase();
    if (firstLabel.isNotEmpty && baseLower.contains(firstLabel)) return base;

    return '$base\nObjek: $detectedLabels';
  }

  void _goToCurrentLocation() {
    _safeMoveMap(_userLocation, 18.0);
    AppFeedback.info(
      context,
      'Peta dipusatkan ke posisi Anda.',
      announce: true,
    );
  }

  /// Show route info panel (bottom sheet)
  void _showRouteInfoPanel() {
    final destinationName = _selectedPlace == null
        ? 'Tujuan'
        : _formatPlaceName(_selectedPlace!.name);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppDialogStyle.barrierColor,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateBottomSheet) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
            border: const Border(
              top: BorderSide(color: AppDialogStyle.borderColor),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.045),
                blurRadius: 14,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.route_rounded,
                        color: AppColors.primaryDark,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Rute Perjalanan',
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ke $destinationName',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _buildRouteMetricCard(
                        icon: Icons.straighten_rounded,
                        label: 'Total Jarak',
                        value: '${_routeDistanceKm.toStringAsFixed(1)} km',
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildRouteMetricCard(
                        icon: Icons.directions_walk_rounded,
                        label: 'Durasi',
                        value:
                            '${_routeDurationMinutes.toStringAsFixed(0)} menit',
                        color: const Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildRouteInfoRow(
                        icon: Icons.my_location_rounded,
                        label: 'Asal',
                        value: 'Posisi Anda Saat Ini',
                        color: const Color(0xFFB45309),
                      ),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 52,
                        color: Color(0xFFEFF3F7),
                      ),
                      _buildRouteInfoRow(
                        icon: _getCategoryIcon(_selectedPlace?.category),
                        label: 'Tujuan',
                        value: destinationName,
                        color: AppColors.primaryDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.schedule_rounded,
                          color: AppColors.primaryDark,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tiba di',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _calculateArrivalTime(),
                              style: AppTextStyles.heading2.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 2,
              overflow: TextOverflow.fade,
            ),
          ),
        ],
      ),
    );
  }

  /// Calculate arrival time
  String _calculateArrivalTime() {
    final now = DateTime.now();
    final durationInMinutes = _routeDurationMinutes.toInt();
    final arrivalTime = now.add(Duration(minutes: durationInMinutes));

    final hour = arrivalTime.hour.toString().padLeft(2, '0');
    final minute = arrivalTime.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  /// Load route dari user location ke selected place
  Future<void> _loadRoute() async {
    if (_selectedPlace == null) return;

    final wasNavigating = _isNavigating;

    setState(() {
      _isLoadingRoute = true;
      _routePoints = [];
      _lastPassedRouteIndex = 0;
      _currentSnappedRoutePoint = null;
      _offRouteSince = null;
      _lastRerouteAt = null;
      _isOffRouteWarningVisible = false;
      _lastGpsWeakAnnouncementAt = null;
      _wasGpsWeak = false;
      _resetGpsAccuracyStatusStabilizer();
      _routeDistanceKm = 0.0;
      _routeDurationMinutes = 0.0;
      _routeLoadError = '';
      _navigationInstructions = [];
      _currentInstructionIndex = 0;
      _currentInstructionRemainingMeters = null;
      _announcedInstructionCueMeters.clear();
      _announcedNowInstructionIndexes.clear();
      _maneuverConfirmationCounts.clear();
      _turnCompletionConfirmationCounts.clear();
      _lastManeuverConfirmationAt.clear();
      _lastDistanceToManeuver.clear();
      _gpsCueWindow.clear();
      _clearPendingTurn();
      _isLoadingInstructions = false;
      _instructionLoadError = '';
      _hasArrivedAtDestination = false;
      _arrivalConfirmationCount = 0;
    });

    try {
      final destination = LatLng(
        _selectedPlace!.latitude,
        _selectedPlace!.longitude,
      );

      // Get route polyline
      final points = await _routingService.getRoute(
        origin: _userLocation,
        destination: destination,
      );

      // Get route info in walking mode only
      final routeInfo = await _routingService.getRouteInfo(
        origin: _userLocation,
        destination: destination,
        profile: 'foot',
      );

      // Get turn-by-turn navigation instructions
      final instructions = await _routingService.getNavigationInstructions(
        origin: _userLocation,
        destination: destination,
        profile: 'foot',
      );

      if (mounted) {
        final tripStartedAt = DateTime.now();
        setState(() {
          _routePoints = points;
          _lastPassedRouteIndex = 0;
          _currentSnappedRoutePoint = null;
          _offRouteSince = null;
          _lastRerouteAt = null;
          _isOffRouteWarningVisible = false;
          _lastGpsWeakAnnouncementAt = null;
          _wasGpsWeak = false;
          _resetGpsAccuracyStatusStabilizer();
          _isLoadingRoute = false;
          _routeLoadError = '';
          _navigationInstructions = instructions;
          _currentInstructionIndex = 0;
          _currentInstructionRemainingMeters = null;
          _announcedInstructionCueMeters.clear();
          _announcedNowInstructionIndexes.clear();
          _maneuverConfirmationCounts.clear();
          _turnCompletionConfirmationCounts.clear();
          _lastManeuverConfirmationAt.clear();
          _lastDistanceToManeuver.clear();
          _gpsCueWindow.clear();
          _clearPendingTurn();
          _isLoadingInstructions = false;

          // Foot mode (default)
          _routeDistanceMeters = (routeInfo['distance'] as num).toDouble();
          _initialDurationSeconds = _routeDistanceMeters / _pedestrianSpeedMs;
          _routeDurationSeconds = _initialDurationSeconds;
          _routeDistanceKm = (routeInfo['distance_km'] as num).toDouble();
          _routeDurationMinutes = _initialDurationSeconds / 60;

          // Start navigation tracking
          _isNavigating = true;
          _navigationStartTime = tripStartedAt;
          _tripStartedAt ??= tripStartedAt;
          _lastDurationUpdateTime = tripStartedAt;
          _destinationName = _selectedPlace?.name ?? 'unknown';
        });
        _smartCaneBleService.setNavigationHazardAnnouncementsEnabled(true);

        _updateLiveInstructionDistance(_userLocation, allowVoiceCue: false);

        final firstInstruction = instructions.isEmpty
            ? 'Ikuti rute yang ditampilkan.'
            : '${instructions.first.instruction}.';
        if (wasNavigating) {
          await speakSafe(
            'Rute baru ditemukan. $firstInstruction',
            priority: TtsPriority.navigation,
            replacementKey: 'navigation-guidance',
            maxAge: const Duration(seconds: 10),
          );
        } else {
          await speakSafe(
            'Rute ditemukan. Silakan mulai navigasi. $firstInstruction',
            priority: TtsPriority.navigation,
            replacementKey: 'navigation-guidance',
            maxAge: const Duration(seconds: 12),
          );
        }

        if (!wasNavigating) {
          await _startTripHistoryIfNeeded();
        } else {
          unawaited(_syncRemainingRoutePolyline());
        }

        // Start timer to update duration every 5 seconds
        _startDurationUpdateTimer();

        if (!wasNavigating) {
          unawaited(
            _analyticsService.logStartNavigation(
              destinationName: _selectedPlace?.name ?? 'unknown',
              destinationCategory: _selectedPlace?.category ?? 'unknown',
              initialDistanceKm: _routeDistanceKm,
            ),
          );
        }
      }
    } catch (error) {
      if (!wasNavigating) {
        _smartCaneBleService.setNavigationHazardAnnouncementsEnabled(false);
      }
      if (mounted) {
        final userFriendlyMsg = AppErrorMessage.from(
          error,
          fallback:
              'Rute belum dapat dihitung. Periksa tujuan dan coba kembali.',
        );

        setState(() {
          _isLoadingRoute = false;
          _routeLoadError = userFriendlyMsg;
        });

        final isConnectivityError = error.toString().toLowerCase().contains(
          'tidak ada koneksi internet',
        );

        if (wasNavigating && isConnectivityError) {
          unawaited(
            speakSafe(
              'Tidak ada koneksi internet. Rute tidak dapat dihitung ulang. '
              'Harap berhati-hati, panduan mungkin tidak sesuai dengan posisi Anda saat ini.',
              priority: TtsPriority.warning,
              deduplicationKey: 'navigation-reroute-offline',
              replacementKey: 'navigation-guidance',
              maxAge: const Duration(seconds: 10),
            ),
          );
        }

        AppFeedback.show(
          context,
          userFriendlyMsg,
          type: AppFeedbackType.error,
          announce: !(wasNavigating && isConnectivityError),
        );
      }
    }
  }

  /// Start timer to update remaining duration every 15 seconds
  void _startDurationUpdateTimer() {
    // Cancel existing timer if any
    _durationUpdateTimer?.cancel();

    // Update duration immediately
    _updateRemainingDuration();

    // Then update every 15 seconds
    _durationUpdateTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isNavigating && _selectedPlace != null) {
        _updateRemainingDuration();
      }
    });
  }

  /// Update remaining duration based on current location
  /// This will call OSRM API to get new duration from current location to destination in walking mode
  /// Instruction advancement is handled on each GPS update for better timing.
  Future<void> _updateRemainingDuration() async {
    if (!_isNavigating || _selectedPlace == null) return;

    try {
      // Debounce: only update if at least 3 seconds have passed since last update
      final now = DateTime.now();
      if (_lastDurationUpdateTime != null) {
        final timeSinceLastUpdate = now
            .difference(_lastDurationUpdateTime!)
            .inSeconds;
        if (timeSinceLastUpdate < 3) {
          return; // Skip this update
        }
      }

      final destination = LatLng(
        _selectedPlace!.latitude,
        _selectedPlace!.longitude,
      );

      // Get updated route info in walking mode
      final routeInfo = await _routingService.getRouteInfo(
        origin: _userLocation,
        destination: destination,
        profile: 'foot',
      );

      if (mounted) {
        final distanceMeters = (routeInfo['distance'] as num).toDouble();
        final newFootDurationSeconds = distanceMeters / _pedestrianSpeedMs;
        final newDistanceKm = (routeInfo['distance_km'] as num).toDouble();
        // Instruction changes are handled by GPS-triggered maneuver cues.
        final nextInstructionIndex = _currentInstructionIndex;
        var forwardInstruction = false;
        var instructionText = '';

        setState(() {
          // Update walking mode
          _routeDistanceMeters = distanceMeters;
          _routeDurationSeconds = newFootDurationSeconds;
          _routeDurationMinutes = newFootDurationSeconds / 60;
          _routeDistanceKm = newDistanceKm;

          // Update current instruction index
          if (nextInstructionIndex >= 0 &&
              nextInstructionIndex != _currentInstructionIndex) {
            _currentInstructionIndex = nextInstructionIndex;
            _currentInstructionRemainingMeters = null;

            final instruction =
                _navigationInstructions[_currentInstructionIndex];
            instructionText = instruction.instruction;

            // Tandai bahwa kita perlu memicu suara SETELAH setState selesai
            forwardInstruction = true;
          }
          _lastDurationUpdateTime = now;
        });

        if (forwardInstruction && instructionText.isNotEmpty) {
          await speakSafe(
            instructionText,
            priority: TtsPriority.navigation,
            replacementKey: 'navigation-guidance',
            maxAge: const Duration(seconds: 8),
          );
          _updateLiveInstructionDistance(_userLocation, allowVoiceCue: false);
        }
      }
    } catch (e) {
      // Silently fail - don't show error to user during navigation
    }
  }

  Future<void> _handleArrival() async {
    if (!mounted || _hasArrivedAtDestination) return;

    final destinationName = _selectedPlace?.name ?? 'tujuan';
    final routeDistanceKm = _routeDistanceKm;
    final navigationStartedAt = _navigationStartTime;
    final durationSeconds = navigationStartedAt == null
        ? 0
        : DateTime.now().difference(navigationStartedAt).inSeconds;

    setState(() {
      _hasArrivedAtDestination = true;
      _currentInstructionIndex = _navigationInstructions.length;
      _currentInstructionRemainingMeters = null;
      _routeDurationSeconds = 0.0;
      _routeDurationMinutes = 0.0;
    });

    unawaited(
      _analyticsService.logArrivedDestination(
        destinationName: destinationName,
        durationSeconds: durationSeconds < 0 ? 0 : durationSeconds,
        routeDistanceKm: routeDistanceKm,
      ),
    );

    await speakSafe(
      "Anda telah tiba di $destinationName",
      priority: TtsPriority.critical,
      deduplicationKey: 'navigation-arrived-$destinationName',
      replacementKey: 'navigation-guidance',
    );
    await _endNavigationSession(endReason: 'arrived');

    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.tunaNetraHome, (route) => false);
  }

  /// Stop navigation tracking and cleanup timers
  void _stopNavigationTracking({bool clearDuration = true}) {
    _smartCaneBleService.setNavigationHazardAnnouncementsEnabled(false);
    _durationUpdateTimer?.cancel();
    _durationUpdateTimer = null;
    setState(() {
      _isNavigating = false;
      _navigationStartTime = null;
      _initialDurationSeconds = 0.0;
      if (clearDuration) {
        _routeDurationSeconds = 0.0;
        _routeDurationMinutes = 0.0;
      }
    });
  }

  ({int index, double? distanceMeters, bool isLookAhead})
  _resolveDisplayedInstruction() {
    final currentIndex = _currentInstructionIndex;
    var displayDistance = _currentInstructionRemainingMeters;

    if (!_isNavigating ||
        currentIndex >= _navigationInstructions.length ||
        currentIndex + 1 >= _navigationInstructions.length) {
      return (
        index: currentIndex,
        distanceMeters: displayDistance,
        isLookAhead: false,
      );
    }

    final currentInstruction = _navigationInstructions[currentIndex];
    final nextInstruction = _navigationInstructions[currentIndex + 1];
    if (!_isDirectionalTurn(nextInstruction.turnType)) {
      return (
        index: currentIndex,
        distanceMeters: displayDistance,
        isLookAhead: false,
      );
    }

    final displayLocation = _currentSnappedRoutePoint ?? _animatedUserLocation;
    final cueLocation = _resolveTurnAnchor(
      currentInstruction,
      currentIndex + 1,
    );
    if (cueLocation == null) {
      return (
        index: currentIndex,
        distanceMeters: displayDistance,
        isLookAhead: false,
      );
    }

    final directDistance = _distanceBetweenPoints(displayLocation, cueLocation);
    final routeDistance =
        _remainingDistanceToAnchorAlongPolyline(
          displayLocation,
          currentInstruction.polylinePoints,
          cueLocation,
        ) ??
        directDistance;
    final conservativeDistance = math.max(routeDistance, directDistance);

    if (conservativeDistance <= _instructionLookAheadMeters) {
      return (
        index: currentIndex + 1,
        distanceMeters: conservativeDistance,
        isLookAhead: true,
      );
    }

    displayDistance ??= currentInstruction.distance;
    return (
      index: currentIndex,
      distanceMeters: displayDistance,
      isLookAhead: false,
    );
  }

  /// Build next instruction card for turn-by-turn navigation
  Widget _buildNextInstructionCard() {
    if (_navigationInstructions.isEmpty ||
        _currentInstructionIndex >= _navigationInstructions.length) {
      return const SizedBox.shrink();
    }

    final displayInfo = _resolveDisplayedInstruction();
    final instruction = _navigationInstructions[displayInfo.index];
    final emoji = ManeuverParser.getTurnEmoji(instruction.turnType);
    final displayDistance = displayInfo.distanceMeters ?? instruction.distance;
    final distanceText = displayDistance > 1000
        ? '${(displayDistance / 1000).toStringAsFixed(1)} km'
        : '${displayDistance.toStringAsFixed(0)} m';

    final stepText =
        '${displayInfo.index + 1} dari ${_navigationInstructions.length} langkah';
    final semanticsPrefix = displayInfo.isLookAhead
        ? 'Bersiap instruksi berikutnya'
        : 'Instruksi berikutnya';
    final distancePrefix = displayInfo.isLookAhead ? 'Dalam' : 'Setelah';
    final routeSummary =
        '${_routeDistanceKm.toStringAsFixed(1)} km · ${_routeDurationMinutes.toStringAsFixed(0)} menit';

    return Semantics(
      button: true,
      label: '$semanticsPrefix: ${instruction.instruction}, $stepText',
      hint: 'Menampilkan detail rute',
      child: GestureDetector(
        onTap: _showRouteInfoPanel,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 21)),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        instruction.instruction,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.fade,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.directions_rounded,
                            size: 12,
                            color: AppColors.primaryDark,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$distancePrefix $distanceText',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            stepText,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.primaryDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        routeSummary,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Get icon based on place category
  IconData _getCategoryIcon(String? category) {
    final normalized = category
        ?.trim()
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');

    if (normalized == null || normalized.isEmpty) {
      return Icons.location_on_rounded;
    }

    if (normalized.contains('rumah') || normalized == 'home') {
      return Icons.home_rounded;
    }
    if (normalized.contains('kos') ||
        normalized.contains('kost') ||
        normalized.contains('tempat tinggal')) {
      return Icons.apartment_rounded;
    }
    if (normalized.contains('halte') ||
        normalized.contains('bus') ||
        normalized.contains('trans')) {
      return Icons.directions_bus_rounded;
    }
    if (normalized.contains('stasiun') ||
        normalized.contains('station') ||
        normalized.contains('train')) {
      return Icons.train_rounded;
    }
    if (normalized.contains('toko') ||
        normalized.contains('minimarket') ||
        normalized.contains('market')) {
      return Icons.storefront_rounded;
    }

    switch (normalized) {
      case 'rumah':
      case 'home':
        return Icons.home_rounded;
      case 'kos':
      case 'kost':
      case 'tempat tinggal':
        return Icons.apartment_rounded;
      case 'halte bus':
      case 'halte':
      case 'bus_stop':
        return Icons.directions_bus_rounded;
      case 'stasiun':
      case 'train_station':
        return Icons.train_rounded;
      case 'toko':
      case 'minimarket':
      case 'market':
        return Icons.storefront_rounded;
      case 'mall':
        return Icons.shopping_bag_rounded;
      case 'mosque':
        return Icons.mosque_rounded;
      case 'hospital':
        return Icons.local_hospital_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'bookstore':
        return Icons.menu_book_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'park':
        return Icons.park_rounded;
      case 'bank':
        return Icons.atm_rounded;
      case 'pharmacy':
        return Icons.local_pharmacy_rounded;
      case 'police':
        return Icons.local_police_rounded;
      case 'gas_station':
        return Icons.local_gas_station_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFreeMode) {
      return _buildFreeModeScreen();
    }

    // Jika belum memilih place, tampilkan list
    if (_selectedPlace == null) {
      return _buildPlacesListScreen();
    }

    // Jika sudah memilih, tampilkan map
    return _buildMapScreen();
  }

  /// Build list screen menampilkan semua places
  Widget _buildPlacesListScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      body: SafeArea(
        child: Column(
          children: [
            _buildPlacesHeader(),
            Expanded(
              child: _isLoadingPlaces
                  ? Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                          child: _buildFreeModeCard(),
                        ),
                        Expanded(child: _buildPlacesLoadingState()),
                      ],
                    )
                  : _places.isEmpty
                  ? Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                          child: _buildFreeModeCard(),
                        ),
                        Expanded(child: _buildPlacesEmptyState()),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: _places.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) return _buildFreeModeCard();
                        return _buildPlaceListItem(_places[index - 1]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlacesHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Kembali',
            hint: 'Menutup pemilihan tempat',
            child: Material(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(12),
                child: const ExcludeSemantics(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pilih Tempat',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.heading3.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _isLoadingPlaces
                      ? 'Memuat tempat tujuan'
                      : '${_places.length} tempat tersedia',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlacesLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryDark),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Memuat tempat tujuan...',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlacesEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.location_off_rounded,
                size: 32,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Belum ada tempat',
              textAlign: TextAlign.center,
              style: AppTextStyles.heading3.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tambahkan tempat tujuan agar navigasi bisa digunakan.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _enterFreeMode() {
    setState(() => _isFreeMode = true);
    _smartCaneBleService.setNavigationHazardAnnouncementsEnabled(true);
    unawaited(speakSafe('Mode jelajah aktif.'));
  }

  void _exitFreeMode() {
    _smartCaneBleService.setNavigationHazardAnnouncementsEnabled(false);
    _lastSensorTtsAt = null;
    _lastSensorLevel = 0;
    _safePathDetectedAt = null;
    setState(() => _isFreeMode = false);
  }

  Widget _buildFreeModeCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Semantics(
        button: true,
        label: 'Mode Jelajah, deteksi rintangan tanpa navigasi ke tujuan',
        hint: 'Mengaktifkan mode jelajah',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _enterFreeMode,
            borderRadius: BorderRadius.circular(14),
            child: ExcludeSemantics(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryDark,
                      AppColors.primaryDark.withValues(alpha: 0.82),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.sensors_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Mode Jelajah',
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Deteksi rintangan tanpa navigasi ke tujuan',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFreeModeScreen() {
    final isConnected = _smartCaneBleService.isConnected;
    final data = isConnected ? _latestSmartCaneSensorData : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimary.withValues(alpha: 0.045),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Kembali',
                    hint: 'Keluar dari mode jelajah',
                    child: Material(
                      color: AppColors.primaryDark,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () {
                          _exitFreeMode();
                          unawaited(_ttsService.stop());
                          unawaited(
                            speakSafe('Kembali ke halaman pilih tempat.'),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: const ExcludeSemantics(
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mode Jelajah',
                          style: AppTextStyles.heading3.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Deteksi lingkungan aktif',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  children: [
                    // Connection & sensor status card
                    _buildFreeModeStatusCard(
                      isConnected: isConnected,
                      data: data,
                    ),

                    // Detections card
                    if (data != null && data.detections.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildFreeModeDetectionsCard(data),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFreeModeStatusCard({
    required bool isConnected,
    required SmartCaneSensorData? data,
  }) {
    final statusColor = !isConnected
        ? AppColors.textSecondary
        : data == null
        ? AppColors.textSecondary
        : data.isDanger || data.hasDangerDetection
        ? const Color(0xFFDC2626)
        : data.isWarning
        ? const Color(0xFFD97706)
        : const Color(0xFF16A34A);

    final statusLabel = !isConnected
        ? 'SmartCane belum terhubung'
        : data == null
        ? 'Menunggu data sensor...'
        : data.isDanger || data.hasDangerDetection
        ? 'Bahaya terdeteksi'
        : data.isWarning
        ? 'Hati-hati'
        : 'Aman';

    final statusIcon = !isConnected
        ? Icons.bluetooth_disabled_rounded
        : data == null
        ? Icons.hourglass_empty_rounded
        : data.isDanger || data.hasDangerDetection
        ? Icons.warning_rounded
        : data.isWarning
        ? Icons.warning_amber_rounded
        : Icons.check_circle_rounded;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(statusIcon, color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusLabel,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (data != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Data sensor realtime',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Sensor distances
          if (data != null &&
              (data.leftCm != null ||
                  data.centerCm != null ||
                  data.rightCm != null)) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFEFF3F7)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildFreeModeDistanceChip('Kiri', data.leftCm),
                _buildFreeModeDistanceChip('Tengah', data.centerCm),
                _buildFreeModeDistanceChip('Kanan', data.rightCm),
              ],
            ),
          ],

          // Decision
          if (data != null && data.guidanceDecisionText != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFEFF3F7)),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.navigation_rounded,
                  size: 17,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 7),
                Text(
                  'Saran: ${data.guidanceDecisionText}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFreeModeDistanceChip(String label, double? valueCm) {
    final hasValue = valueCm != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          valueCm != null ? '${valueCm.round()} cm' : '-',
          style: AppTextStyles.bodyLarge.copyWith(
            color: hasValue ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFreeModeDetectionsCard(SmartCaneSensorData data) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Objek Terdeteksi',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          ...data.detections.map((detection) => _buildDetectionRow(detection)),
        ],
      ),
    );
  }

  Widget _buildDetectionRow(SmartCaneDetection detection) {
    final isDangerLabel = const {
      'pothole',
      'obstacle',
      'stair',
      'road',
    }.contains(detection.label);
    final labelColor = isDangerLabel
        ? const Color(0xFFDC2626)
        : const Color(0xFF16A34A);
    final bgColor = isDangerLabel
        ? const Color(0xFFFEF2F2)
        : const Color(0xFFF0FDF4);

    final positionLabel = switch (detection.position.toLowerCase()) {
      'kiri' || 'left' => 'Kiri',
      'kanan' || 'right' => 'Kanan',
      _ => 'Tengah',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isDangerLabel ? Icons.warning_rounded : Icons.visibility_rounded,
              color: labelColor,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    detection.localizedLabel,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: labelColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    positionLabel,
                    style: AppTextStyles.caption.copyWith(
                      color: labelColor.withValues(alpha: 0.75),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (detection.confidence > 0)
              Text(
                '${(detection.confidence * 100).toStringAsFixed(0)}%',
                style: AppTextStyles.caption.copyWith(
                  color: labelColor.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceListItem(PlaceModel place) {
    final isFamilyPlace = place.isPrivate;
    const familyAccent = Color(0xFF0F766E);
    const familyAccentSoft = Color(0xFFECFDF5);
    final accentColor = isFamilyPlace ? familyAccent : AppColors.info;
    final borderColor = isFamilyPlace
        ? familyAccent.withValues(alpha: 0.16)
        : const Color(0xFFE2E8F0);
    final categoryLabel = _formatPlaceCategory(place.category);
    final addressText = _formatPlaceAddress(
      place.address,
      categoryLabel,
      name: place.name,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Semantics(
        button: true,
        label:
            '${_formatPlaceName(place.name)}, ${_formatPlaceAddress(place.address, categoryLabel, name: place.name)}',
        hint: 'Memilih tujuan ini',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedPlace = place;
                _isLoadingRoute = true;
              });

              // Start continuous location streaming immediately.
              // Route will load automatically from first streaming GPS update.
              _startLocationStreaming();

              // Center map ke lokasi user (bukan tempat tujuan)
              Future.delayed(const Duration(milliseconds: 300), () {
                _safeMoveMap(_userLocation, 18.0);
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: ExcludeSemantics(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textPrimary.withValues(alpha: 0.035),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    if (isFamilyPlace)
                      Positioned.fill(
                        left: 0,
                        right: null,
                        child: Container(
                          width: 2.5,
                          color: familyAccent.withValues(alpha: 0.82),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isFamilyPlace ? 16 : 13,
                        11,
                        12,
                        11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isFamilyPlace
                                  ? familyAccentSoft.withValues(alpha: 0.86)
                                  : AppColors.infoLight.withValues(alpha: 0.54),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _getCategoryIcon(place.category),
                              color: accentColor,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatPlaceName(place.name),
                                  maxLines: 2,
                                  overflow: TextOverflow.fade,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                    height: 1.18,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  addressText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 12.5,
                                    height: 1.28,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Text(
                                      categoryLabel.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: accentColor.withValues(
                                          alpha: 0.82,
                                        ),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                    if (isFamilyPlace) ...[
                                      const SizedBox(width: 6),
                                      _buildFamilyPlaceBadge(),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.9,
                              ),
                              size: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFamilyPlaceBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFBBF7D0).withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.people_alt_rounded,
            size: 10,
            color: Color(0xFF0F766E),
          ),
          const SizedBox(width: 3),
          Text(
            'Dari keluarga',
            style: AppTextStyles.caption.copyWith(
              color: const Color(0xFF0F766E),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPlaceName(String value) {
    final trimmed = value.trim();
    if (_isPlaceholderText(trimmed)) return 'Tempat tujuan';
    var normalized = trimmed.replaceAll(
      RegExp(r'\balun\s+alun\b', caseSensitive: false),
      'alun-alun',
    );
    normalized = normalized.replaceAll(
      RegExp(r'\bhalte\s+damri\s+kota\s+baru\s+p.*$', caseSensitive: false),
      'Halte Damri Kota Baru',
    );
    return _toTitleCase(normalized);
  }

  String _toTitleCase(String value) {
    return value
        .split(' ')
        .where((word) => word.trim().isNotEmpty)
        .map((word) {
          final lower = word.toLowerCase();
          return lower
              .split('-')
              .map((part) {
                if (part.isEmpty) return part;
                return '${part[0].toUpperCase()}${part.substring(1)}';
              })
              .join('-');
        })
        .join(' ');
  }

  String _formatPlaceCategory(String value) {
    final trimmed = value.trim();
    if (_isPlaceholderText(trimmed)) return 'Tempat';
    final normalized = trimmed.toLowerCase().replaceAll('_', ' ');
    if (normalized.contains('halte') || normalized.contains('bus')) {
      return 'Halte Bus';
    }
    if (normalized.contains('train') ||
        normalized.contains('stasiun') ||
        normalized.contains('station')) {
      return 'Stasiun';
    }
    if (normalized.contains('rumah') || normalized == 'home') {
      return 'Rumah';
    }
    return _toTitleCase(normalized);
  }

  String _formatPlaceAddress(String value, String category, {String? name}) {
    final trimmed = value.trim();
    if (_isPlaceholderText(trimmed)) {
      final normalizedName = (name ?? '').trim().toLowerCase();
      if (normalizedName.contains('indomaret')) {
        return 'Minimarket terdekat';
      }
      if (normalizedName.contains('kos') || normalizedName.contains('kost')) {
        return 'Lokasi kos pengguna';
      }
      if (category.toLowerCase().contains('rumah')) {
        return 'Lokasi rumah utama';
      }
      if (category.toLowerCase().contains('tinggal') ||
          category.toLowerCase().contains('kos')) {
        return 'Lokasi tempat tinggal';
      }
      return 'Alamat tempat tujuan';
    }

    final parts = trimmed
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= 3) return trimmed;
    return parts.take(3).join(', ');
  }

  bool _isPlaceholderText(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == '-' ||
        normalized == 'xxx' ||
        normalized == 'unknown' ||
        normalized == 'unknown place';
  }

  /// Build map screen setelah memilih place
  Widget _buildNavigationAlertBadge({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFF2C56B)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.05),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFFB45309), size: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color(0xFF92400E),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapScreen() {
    final topInset = MediaQuery.of(context).padding.top;
    final fusionBadgeTop = topInset + 94;
    final passedRoutePoints = _getPassedRoutePoints();
    final remainingRoutePoints = _getRemainingRoutePoints();
    final hasActiveInstruction =
        _navigationInstructions.isNotEmpty &&
        _currentInstructionIndex < _navigationInstructions.length &&
        !_isLoadingRoute &&
        _routeLoadError.isEmpty;
    final destinationName = _selectedPlace == null
        ? 'Navigasi'
        : _formatPlaceName(_selectedPlace!.name);
    final destinationAddress = _selectedPlace == null
        ? 'Pilih tempat untuk memulai navigasi'
        : _formatPlaceAddress(
            _selectedPlace!.address,
            _selectedPlace!.category,
          );

    return Scaffold(
      body: Stack(
        children: [
          // Map - Full screen background
          SizedBox.expand(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _userLocation,
                initialZoom: 18.0,
                minZoom: 5.0,
                maxZoom: 18.0,
                onMapReady: _onMapReady,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                // OpenStreetMap Tile Layer
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.my_app',
                  maxZoom: 18.0,
                ),

                // Dynamic route polyline: passed segment + remaining segment
                if (passedRoutePoints.isNotEmpty ||
                    remainingRoutePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      if (passedRoutePoints.isNotEmpty)
                        Polyline(
                          points: passedRoutePoints,
                          color: Colors.grey.shade500,
                          strokeWidth: 4.0,
                          borderColor: Colors.grey.shade300,
                          borderStrokeWidth: 6.0,
                        ),
                      if (remainingRoutePoints.isNotEmpty)
                        Polyline(
                          points: remainingRoutePoints,
                          color: AppColors.primary,
                          strokeWidth: 4.0,
                          borderColor: AppColors.primary.withOpacity(0.5),
                          borderStrokeWidth: 6.0,
                        ),
                    ],
                  ),

                // Markers
                MarkerLayer(
                  markers: [
                    // User current location marker
                    Marker(
                      point: _animatedUserLocation,
                      width: 86,
                      height: 92,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF22C55E),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.textPrimary.withValues(
                                      alpha: 0.16,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                              child: Center(
                                child: Transform.rotate(
                                  angle: _markerHeading * (math.pi / 180),
                                  child: const Icon(
                                    Icons.navigation_rounded,
                                    color: Colors.white,
                                    size: 21,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A),
                                borderRadius: BorderRadius.circular(7),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.textPrimary.withValues(
                                      alpha: 0.08,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Posisi Saya',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Destination marker (selected place)
                    if (_selectedPlace != null)
                      Marker(
                        point: LatLng(
                          _selectedPlace!.latitude,
                          _selectedPlace!.longitude,
                        ),
                        width: 90,
                        height: 90,
                        child: Semantics(
                          button: true,
                          label: 'Penanda tujuan ${_selectedPlace!.name}',
                          hint: 'Memusatkan peta ke tujuan',
                          child: GestureDetector(
                            onTap: () {
                              _goToLocation(
                                LatLng(
                                  _selectedPlace!.latitude,
                                  _selectedPlace!.longitude,
                                ),
                              );
                              AppFeedback.info(
                                context,
                                'Peta dipusatkan ke ${_selectedPlace!.name}.',
                                announce: true,
                              );
                            },
                            child: ExcludeSemantics(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Pin icon
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.primaryDark,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.textPrimary
                                              .withValues(alpha: 0.12),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        _getCategoryIcon(
                                          _selectedPlace!.category,
                                        ),
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  // Pin pointer
                                  CustomPaint(
                                    size: const Size(0, 8),
                                    painter: PinPointerPainter(),
                                  ),
                                  // Place name
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryDark,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      destinationName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          Positioned(
            top: fusionBadgeTop,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildNavigationAlertBadge(
                  icon: Icons.sensors_rounded,
                  text: _ultrasonicSensorText,
                ),
                if (_isOffRouteWarningVisible) ...[
                  const SizedBox(height: 4),
                  _buildNavigationAlertBadge(
                    icon: Icons.route_outlined,
                    text: _lastRerouteAt != null
                        ? 'Keluar jalur. Menghitung ulang rute...'
                        : 'Keluar jalur. Menyesuaikan navigasi...',
                  ),
                ],
              ],
            ),
          ),

          // Header with back button (Floating overlay)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textPrimary.withValues(alpha: 0.045),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      label: 'Kembali',
                      hint: 'Menghentikan navigasi',
                      child: Material(
                        color: AppColors.primaryDark,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () {
                            unawaited(_ttsService.stop());
                            unawaited(
                              speakSafe('Kembali ke halaman pilih tempat.'),
                            );
                            unawaited(_endNavigationSession());
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: const ExcludeSemantics(
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            destinationName,
                            style: AppTextStyles.heading3.copyWith(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            destinationAddress,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Current location control (Right side)
          Positioned(
            bottom: 154,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimary.withValues(alpha: 0.09),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Semantics(
                button: true,
                label: 'Posisi saya',
                hint: 'Memusatkan peta ke lokasi Anda',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _goToCurrentLocation,
                    borderRadius: BorderRadius.circular(12),
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.my_location_rounded,
                          color: AppColors.primaryDark,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Route info panel (Bottom)
          if (_selectedPlace != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Next instruction card (Turn-by-turn guidance)
                  if (hasActiveInstruction) _buildNextInstructionCard(),

                  // Route info panel
                  _isLoadingRoute
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight.withValues(
                                    alpha: 0.16,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Menghitung Rute...',
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Menunggu data dari server',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : _routeLoadError.isNotEmpty
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF3C8C8)),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.error_outline_rounded,
                                  color: AppColors.error,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Rute Tidak Dapat Dihitung',
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.error,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _routeLoadError,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: Colors.red[600],
                                        height: 1.4,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : _routeDistanceKm > 0 && !hasActiveInstruction
                      ? Semantics(
                          button: true,
                          label:
                              'Tujuan: $destinationName, ${_routeDistanceKm.toStringAsFixed(1)} km, ${_routeDurationMinutes.toStringAsFixed(0).split(".")[0]} menit',
                          hint: 'Menampilkan detail rute',
                          child: GestureDetector(
                            onTap: _showRouteInfoPanel,
                            child: ExcludeSemantics(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.textPrimary.withValues(
                                        alpha: 0.08,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight
                                            .withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: Icon(
                                        Icons.route_rounded,
                                        color: AppColors.primaryDark,
                                        size: 25,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Tujuan: $destinationName',
                                            style: AppTextStyles.bodyLarge
                                                .copyWith(
                                                  color: AppColors.textPrimary,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                ),
                                            maxLines: 2,
                                            overflow: TextOverflow.fade,
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Text(
                                                '${_routeDistanceKm.toStringAsFixed(1)} km',
                                                style: TextStyle(
                                                  color: AppColors.primaryDark,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Container(
                                                width: 1,
                                                height: 16,
                                                color: const Color(0xFFE2E8F0),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                '${_routeDurationMinutes.toStringAsFixed(0).split(".")[0]} menit',
                                                style: const TextStyle(
                                                  color: Color(0xFF16A34A),
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: Icon(
                                        Icons.chevron_right_rounded,
                                        color: AppColors.primaryDark,
                                        size: 26,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom painter untuk pin pointer
class PinPointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = ui.Paint()
      ..color = AppColors.primary
      ..style = ui.PaintingStyle.fill;

    // Simple triangle pointing down
    final path = ui.Path()
      ..moveTo(size.width / 2, 8)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(PinPointerPainter oldDelegate) => false;
}
