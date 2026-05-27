import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import '../../utils/constants.dart';
import '../../models/place_model.dart';
import '../../models/navigation_instruction_model.dart';
import '../../services/places_service.dart';
import '../../services/routing_service.dart';
import '../../services/analytics_service.dart';
import '../../services/live_tracking_service.dart';
import '../../services/navigation_history_service.dart';
import '../../services/stt_service.dart';
import '../../services/tts_service.dart';
import '../../services/tunanetra_voice_command_service.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with SingleTickerProviderStateMixin {
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
  final TTSService _ttsService = TTSService();
  final STTService _sttService = STTService();
  bool _hasSpoken = false;
  bool _isSpeaking = false;
  bool _navigationSttEnabled = false;
  bool _navigationSttActive = false;
  bool _navigationSttStarting = false;
  Timer? _navigationSttWatchdog;
  static const double _pedestrianSpeedMs = 1.4;
  static const double _arrivalThresholdMeters = 5.0;

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
  static const double _routeSnapThresholdMeters = 20.0;
  static const double _offRouteThresholdMeters = 35.0;
  static const Duration _offRouteConfirmDuration = Duration(seconds: 2);
  static const Duration _rerouteCooldown = Duration(seconds: 20);
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
  static const String _ultrasonicSensorText =
      'Sensor ultrasonik: data belum tersedia.';

  // Navigation instructions (Turn-by-turn guidance)
  List<NavigationInstruction> _navigationInstructions = [];
  int _currentInstructionIndex = 0; // Index of current/next instruction
  double? _currentInstructionRemainingMeters;
  final Map<int, Set<int>> _announcedInstructionCueMeters = {};
  final Set<int> _announcedNowInstructionIndexes = {};
  bool _isLoadingInstructions = false;
  String _instructionLoadError = '';
  bool _hasArrivedAtDestination = false;
  String _destinationName = '';

  Future<void> speakSafe(String text) async {
    _isSpeaking = true;
    await _ttsService.speak(text);
    _isSpeaking = false;
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _userLocation = defaultLocation;
    _animatedUserLocation = defaultLocation;
    _locationAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addListener(_onLocationAnimationTick);

    // Wait for widget to render, then load places
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _getUserLocation();
      _loadPlaces();

      await speakSafe("Halaman navigasi dibuka. Silakan sebutkan tujuan anda");

      _startVoiceNavigation();
    });
  }

  void _startVoiceNavigation() {
    if (_navigationSttStarting || _navigationSttActive || !mounted) return;

    _navigationSttEnabled = true;
    _navigationSttStarting = true;
    _startNavigationSttWatchdog();

    _sttService
        .startListening(
          (result) {
            if (_isSpeaking) return;

            final text = result.toLowerCase();
            String cleanedText = text.replaceAll('-', ' ').toLowerCase();
            print("🎤 NAV: $cleanedText");

            _handleNavigationCommand(cleanedText);
          },
          onStatus: (status) {
            _navigationSttActive = status == 'listening';

            if ((status == 'notListening' || status == 'done') &&
                mounted &&
                _navigationSttEnabled &&
                !_isSpeaking) {
              Future.delayed(
                const Duration(milliseconds: 1500),
                _startVoiceNavigation,
              );
            }
          },
          onError: (_) {
            _navigationSttActive = false;
            if (mounted && _navigationSttEnabled && !_isSpeaking) {
              Future.delayed(const Duration(seconds: 2), _startVoiceNavigation);
            }
          },
        )
        .whenComplete(() {
          _navigationSttStarting = false;
        });
  }

  Future<void> _stopNavigationStt() async {
    _navigationSttEnabled = false;
    _navigationSttActive = false;
    _navigationSttWatchdog?.cancel();
    _navigationSttWatchdog = null;
    await _sttService.stopListening();
  }

  void _startNavigationSttWatchdog() {
    _navigationSttWatchdog?.cancel();
    _navigationSttWatchdog = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || !_navigationSttEnabled || _isSpeaking) return;

      if (!_sttService.isActuallyListening && !_navigationSttStarting) {
        _navigationSttActive = false;
        _startVoiceNavigation();
      }
    });
  }

  void _handleNavigationCommand(String command) async {
    if (command.length < 2) return;

    if (TunaNetraVoiceCommands.isHomeCommand(command)) {
      await _stopNavigationStt();
      await speakSafe("Membuka halaman utama");
      await _endNavigationSession();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.tunaNetraHome,
        (route) => false,
        arguments: {'announceHomeOpened': true},
      );
      return;
    }

    for (final place in _places) {
      if (command.contains(place.name.replaceAll('-', ' ').toLowerCase())) {
        await _stopNavigationStt();

        setState(() {
          _selectedPlace = place;
        });

        _startLocationStreaming();
        await _loadRoute();
        if (mounted) {
          _startVoiceNavigation();
        }

        return;
      }
    }

    if (command.contains("berhenti")) {
      await _stopNavigationStt();

      await speakSafe("Navigasi dihentikan");

      await _endNavigationSession();

      Navigator.pop(context);
    }
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
    final now = DateTime.now();
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

    final snapResult = _snapPositionToRoute(updatedLocation);
    final displayLocation = snapResult.position;

    setState(() {
      _userLocation = updatedLocation;
      _isUsingPredictedPosition = false;
      _currentSnappedRoutePoint = snapResult.snapped ? displayLocation : null;
      if (position.heading >= 0) {
        _markerHeading = _smoothHeading(
          _markerHeading,
          _normalizeHeading(position.heading),
        );
      }

      if (!_isLocationReady) {
        _isLocationReady = true;
        print('[NAVIGATION] ✅ Real GPS location obtained from streaming!');
      }
    });

    _animateUserLocation(displayLocation);
    _updateLiveInstructionDistance(displayLocation, allowVoiceCue: true);
    _updateRouteProgress(
      snapResult.segmentIndex,
      snapResult.distanceToRouteMeters,
    );
    unawaited(
      _handleOffRouteDetection(
        distanceToRouteMeters: snapResult.distanceToRouteMeters,
        snapped: snapResult.snapped,
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
      _currentSnappedRoutePoint = snapResult.snapped ? displayLocation : null;
    });

    if (_isNavigating) {
      _safeMoveMap(displayLocation);
    }

    _updateRouteProgress(
      snapResult.segmentIndex,
      snapResult.distanceToRouteMeters,
    );
    _updateLiveInstructionDistance(displayLocation, allowVoiceCue: false);
    unawaited(
      _handleOffRouteDetection(
        distanceToRouteMeters: snapResult.distanceToRouteMeters,
        snapped: snapResult.snapped,
      ),
    );
    unawaited(
      _saveRoutePointIfNeeded(
        position: displayLocation,
        isPredicted: true,
        heading: _markerHeading,
        speed: predictedSpeed,
        accuracy: _lastKnownGpsPosition?.accuracy ?? 0.0,
      ),
    );
  }

  int _findClosestRoutePointIndex(
    LatLng currentPosition, {
    required int fromIndex,
  }) {
    if (_routePoints.isEmpty) return 0;

    final startIndex = fromIndex.clamp(0, _routePoints.length - 1);
    var closestIndex = startIndex;
    var minDistance = double.infinity;

    for (var i = startIndex; i < _routePoints.length; i++) {
      final routePoint = _routePoints[i];
      final distance = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        routePoint.latitude,
        routePoint.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    return closestIndex;
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

  void _announceInstructionCueIfNeeded(
    double remainingMeters,
    LatLng displayLocation,
  ) {
    if (_currentInstructionIndex >= _navigationInstructions.length) return;

    final nextInstructionIndex = _currentInstructionIndex + 1;
    final cueInstruction = nextInstructionIndex < _navigationInstructions.length
        ? _navigationInstructions[nextInstructionIndex].instruction
        : 'tujuan berada di depan';

    if (remainingMeters <= 2) {
      _announceNowCueAndAdvance(
        sourceInstructionIndex: _currentInstructionIndex,
        nextInstructionIndex: nextInstructionIndex,
        cueInstruction: cueInstruction,
        displayLocation: displayLocation,
      );
      return;
    }

    final cueMeters = remainingMeters <= 10
        ? 10
        : remainingMeters <= 30
        ? 30
        : null;
    if (cueMeters == null) return;

    final announcedCueMeters = _announcedInstructionCueMeters.putIfAbsent(
      _currentInstructionIndex,
      () => <int>{},
    );
    if (!announcedCueMeters.add(cueMeters)) return;

    unawaited(speakSafe("Dalam $cueMeters meter, $cueInstruction"));
  }

  void _announceNowCueAndAdvance({
    required int sourceInstructionIndex,
    required int nextInstructionIndex,
    required String cueInstruction,
    required LatLng displayLocation,
  }) {
    if (!_announcedNowInstructionIndexes.add(sourceInstructionIndex)) return;

    unawaited(
      _speakNowCueThenAdvance(
        sourceInstructionIndex: sourceInstructionIndex,
        nextInstructionIndex: nextInstructionIndex,
        cueInstruction: cueInstruction,
        displayLocation: displayLocation,
      ),
    );
  }

  Future<void> _speakNowCueThenAdvance({
    required int sourceInstructionIndex,
    required int nextInstructionIndex,
    required String cueInstruction,
    required LatLng displayLocation,
  }) async {
    await speakSafe("Sekarang $cueInstruction");

    if (!mounted ||
        !_isNavigating ||
        _currentInstructionIndex != sourceInstructionIndex ||
        nextInstructionIndex >= _navigationInstructions.length) {
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
  }) async {
    if (!_isNavigating || _selectedPlace == null) return;
    if (_isLoadingRoute) return;

    final now = DateTime.now();

    if (snapped || distanceToRouteMeters <= _offRouteThresholdMeters) {
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

    unawaited(speakSafe("Anda keluar jalur. Menghitung ulang rute"));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Anda keluar jalur. Menghitung ulang rute...'),
        duration: Duration(seconds: 3),
      ),
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
      print('[NAVIGATION] Loading places from Firestore...');
      final places = await _placesService.getAllPlaces();

      // Debug: Print each place
      for (var place in places) {
        print(
          '[NAVIGATION] 📍 Place: ${place.name} (${place.category}) at [${place.latitude}, ${place.longitude}]',
        );
      }

      setState(() {
        _places = places;
        _isLoadingPlaces = false;
      });
      print('[NAVIGATION] ✅ Loaded ${places.length} places');
    } catch (e) {
      print('[NAVIGATION] ❌ Error loading places: $e');
      setState(() => _isLoadingPlaces = false);
      // Fallback: use mock locations
      setState(() {
        _places = [];
      });
    }
  }

  Future<void> _getUserLocation() async {
    try {
      print('[NAVIGATION] Requesting location permission...');

      // Check if location service is enabled
      bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        print('[NAVIGATION] ❌ Location service is disabled');
        setState(() {
          _userLocation = defaultLocation;
          _isLocationReady = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aktifkan layanan lokasi terlebih dahulu'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Check and request location permission
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        print('[NAVIGATION] Permission denied, requesting...');
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        print('[NAVIGATION] ❌ Permission permanently denied');
        setState(() {
          _userLocation = defaultLocation;
          _isLocationReady = false; // Keep false - using default location
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Izin lokasi diperlukan'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        try {
          print(
            '[NAVIGATION] Getting initial GPS location (one-time, battery friendly)...',
          );
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation,
            timeLimit: const Duration(seconds: 60),
          );

          print(
            '[NAVIGATION] ✅ Initial location obtained: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy.toStringAsFixed(1)}m)',
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
          print('[NAVIGATION] ❌ Error getting position: $e');
          setState(() {
            _userLocation = defaultLocation;
            _isLocationReady = false; // Keep false - using default location
          });
        }
      }
    } catch (e) {
      print('[NAVIGATION] ❌ Error: $e');
      setState(() {
        _userLocation = defaultLocation;
        _isLocationReady = false; // Keep false - using default location
      });
    }
  }

  /// Start continuous location streaming for detailed navigation
  /// Called when user starts navigating to a destination
  void _startLocationStreaming() {
    print(
      '[NAVIGATION] Starting continuous location streaming for navigation...',
    );

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
          print(
            '[NAVIGATION] 📍 Navigation position: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy.toStringAsFixed(1)}m)',
          );

          if (mounted) {
            _onGpsPositionUpdate(position);

            // Load route on first GPS location to ensure accuracy
            if (!hasLoadedRouteOnceFromStreaming && _selectedPlace != null) {
              print(
                '[NAVIGATION] Loading route with real GPS location from streaming...',
              );
              _loadRoute();
              hasLoadedRouteOnceFromStreaming = true;
            }
          }
        },
        onError: (e) {
          print('[NAVIGATION] ❌ Location stream error during navigation: $e');
        },
      ),
    );
  }

  /// Stop continuous location streaming to save battery
  void _stopLocationStreaming() {
    print('[NAVIGATION] Stopping location streaming (battery save mode)...');
    unawaited(_liveTrackingService.stopNavigationTracking());
    _stopSensorFusion();
  }

  String _getFusionStatusLabel() {
    if (_isUsingPredictedPosition) {
      return 'Mode Prediksi';
    }
    return 'GPS Live';
  }

  Color _getFusionStatusColor() {
    if (_isUsingPredictedPosition) {
      return Colors.orange;
    }
    return Colors.green;
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

      if (completed) {
        await _navigationHistoryService.finishTrip(
          tripId: tripId,
          durationSeconds: durationSeconds,
          totalDistanceMeters: totalDistanceMeters,
        );
      } else {
        await _navigationHistoryService.cancelTrip(
          tripId: tripId,
          durationSeconds: durationSeconds,
          totalDistanceMeters: totalDistanceMeters,
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
      _navigationInstructions = [];
      _currentInstructionIndex = 0;
      _currentInstructionRemainingMeters = null;
      _announcedInstructionCueMeters.clear();
      _announcedNowInstructionIndexes.clear();
      _routeDistanceKm = 0.0;
      _routeDurationMinutes = 0.0;
      _routeDistanceMeters = 0.0;
      _routeDurationSeconds = 0.0;
      _routeLoadError = '';
      _isLoadingRoute = false;
      _hasArrivedAtDestination = false;
      _isUsingPredictedPosition = false;
      _tripStartedAt = null;
      if (returnToPlaceList) {
        _selectedPlace = null;
      }
    });
  }

  @override
  void dispose() {
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
    _locationAnimationController
      ..removeListener(_onLocationAnimationTick)
      ..dispose();
    unawaited(_liveTrackingService.stopNavigationTracking());
    _stopNavigationStt();
    super.dispose();
  }

  void _goToLocation(LatLng location) {
    _safeMoveMap(location, 18.0);
  }

  void _zoomIn() {
    if (!_isMapReady) return;
    _safeMoveMap(_mapController.camera.center, _mapController.camera.zoom + 1);
  }

  void _zoomOut() {
    if (!_isMapReady) return;
    _safeMoveMap(_mapController.camera.center, _mapController.camera.zoom - 1);
  }

  void _goToCurrentLocation() {
    _safeMoveMap(_userLocation, 18.0);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Moving to current location: ${_userLocation.latitude.toStringAsFixed(4)}, ${_userLocation.longitude.toStringAsFixed(4)}',
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Zoom map to fit all markers (user location + all places)
  void _zoomToFitAllMarkers() {
    if (_places.isEmpty) {
      _safeMoveMap(_userLocation, 18.0);
      return;
    }

    // Collect all coordinates
    List<LatLng> allPoints = [_userLocation];
    allPoints.addAll(
      _places.map((place) => LatLng(place.latitude, place.longitude)),
    );

    // Calculate bounds
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (var point in allPoints) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }

    // Calculate center and zoom
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final padding = 0.1; // 10% padding
    final latRange = (maxLat - minLat) * (1 + padding * 2);
    final lngRange = (maxLng - minLng) * (1 + padding * 2);

    // Approximate zoom level
    double zoom = 16;
    if (latRange > 0.01 || lngRange > 0.01) {
      zoom = 15;
    }
    if (latRange > 0.05 || lngRange > 0.05) {
      zoom = 13;
    }
    if (latRange > 0.1 || lngRange > 0.1) {
      zoom = 12;
    }

    _safeMoveMap(center, zoom);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Menampilkan ${_places.length} tempat + posisi Anda'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Show route info panel (bottom sheet)
  void _showRouteInfoPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateBottomSheet) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.route_rounded,
                        color: Colors.white,
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
                            'Rute Perjalanan',
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'Ke ${_selectedPlace?.name ?? 'Tujuan'}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Route details
                _buildRouteDetailItem(
                  icon: Icons.straighten_rounded,
                  label: 'Total Jarak',
                  value: '${_routeDistanceKm.toStringAsFixed(1)} km',
                  color: Colors.blue,
                ),
                const SizedBox(height: 16),
                _buildRouteDetailItem(
                  icon: Icons.directions_walk_rounded,
                  label: 'Durasi Jalan Kaki',
                  value: '${_routeDurationMinutes.toStringAsFixed(0)} menit',
                  color: Colors.green,
                ),
                const SizedBox(height: 16),
                _buildRouteDetailItem(
                  icon: Icons.my_location_rounded,
                  label: 'Asal',
                  value: 'Posisi Anda Saat Ini',
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                _buildRouteDetailItem(
                  icon: _getCategoryIcon(_selectedPlace?.category),
                  label: 'Tujuan',
                  value: _selectedPlace?.name ?? '-',
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                // Calculate arrival time
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.1),
                        AppColors.primary.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tiba di',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _calculateArrivalTime(),
                        style: AppTextStyles.heading2.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build route detail item widget
  Widget _buildRouteDetailItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
      _routeDistanceKm = 0.0;
      _routeDurationMinutes = 0.0;
      _routeLoadError = '';
      _navigationInstructions = [];
      _currentInstructionIndex = 0;
      _currentInstructionRemainingMeters = null;
      _announcedInstructionCueMeters.clear();
      _announcedNowInstructionIndexes.clear();
      _isLoadingInstructions = false;
      _instructionLoadError = '';
      _hasArrivedAtDestination = false;
    });

    try {
      print('[ROUTING] Loading route to ${_selectedPlace?.name}...');
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
      print('[NAVIGATION] 🔍 Fetching walking duration...');
      final routeInfo = await _routingService.getRouteInfo(
        origin: _userLocation,
        destination: destination,
        profile: 'foot',
      );

      // Get turn-by-turn navigation instructions
      print('[NAVIGATION] 📍 Fetching turn-by-turn instructions...');
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
          _isLoadingRoute = false;
          _routeLoadError = '';
          _navigationInstructions = instructions;
          _currentInstructionIndex = 0;
          _currentInstructionRemainingMeters = null;
          _announcedInstructionCueMeters.clear();
          _announcedNowInstructionIndexes.clear();
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

        _updateLiveInstructionDistance(_userLocation, allowVoiceCue: false);

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
      print('[NAVIGATION] ============ FINAL VALUES ============');
      print(
        '[NAVIGATION] 🚶 Foot - Distance: $_routeDistanceKm km, Duration: $_routeDurationMinutes minutes',
      );
      print(
        '[NAVIGATION] 📍 Turn-by-turn instructions: ${_navigationInstructions.length} steps',
      );
      print('[NAVIGATION] ==========================================');
      print(
        '[ROUTING] ✅ Route loaded (Foot: ${_routeDurationMinutes.toStringAsFixed(0)} min)',
      );
    } catch (e) {
      print('[ROUTING] ❌ Error loading route: $e');
      if (mounted) {
        // Extract and format error message with better descriptions
        String errorMsg = e.toString().replaceFirst('Exception: ', '');

        // Map generic messages to user-friendly Indonesian messages
        String userFriendlyMsg = errorMsg;
        if (errorMsg.contains('Failed') || errorMsg.contains('network')) {
          userFriendlyMsg =
              '❌ Tidak dapat terhubung ke server.\nPastikan koneksi internet Anda stabil.';
        } else if (errorMsg.contains('timeout') || errorMsg.contains('Time')) {
          userFriendlyMsg =
              '⏱️ Koneksi lambat atau server tidak merespons.\nCoba lagi dalam beberapa saat.';
        } else if (errorMsg.contains('connection')) {
          userFriendlyMsg =
              '📡 Tidak ada koneksi internet.\nSilakan periksa jaringan Anda.';
        } else {
          userFriendlyMsg = '⚠️ Gagal menghitung rute.\nPesan: $errorMsg';
        }

        setState(() {
          _isLoadingRoute = false;
          _routeLoadError = userFriendlyMsg;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFriendlyMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
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

    print('[NAVIGATION] ⏱️ Duration update timer started (update every 5s)');
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
        final hasArrivedNow =
            !_hasArrivedAtDestination &&
            distanceMeters < _arrivalThresholdMeters;
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

            print(
              '[NAVIGATION] 📍 Updated to instruction ${_currentInstructionIndex + 1}',
            );
          }
          _lastDurationUpdateTime = now;
        });

        if (forwardInstruction && instructionText.isNotEmpty) {
          await speakSafe(instructionText);
          _updateLiveInstructionDistance(_userLocation, allowVoiceCue: false);
        }

        if (hasArrivedNow) {
          print(
            '[NAVIGATION] ✅ Arrived at destination (< ${_arrivalThresholdMeters.toStringAsFixed(0)}m)',
          );
          _handleArrival();
          return;
        }

        print(
          '[NAVIGATION] ⏱️ Duration updated - Foot: ${_routeDurationMinutes.toStringAsFixed(0)} min, Instruction: ${_currentInstructionIndex + 1}/${_navigationInstructions.length}',
        );
      }
    } catch (e) {
      print('[NAVIGATION] ⚠️ Error updating duration: $e');
      // Silently fail - don't show error to user during navigation
    }
  }

  void _handleArrival() async {
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

    unawaited(_endNavigationSession(endReason: 'arrived'));
    unawaited(speakSafe("Anda telah tiba di ${_selectedPlace?.name}"));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Anda telah tiba di $destinationName. Navigasi selesai.'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Stop navigation tracking and cleanup timers
  void _stopNavigationTracking({bool clearDuration = true}) {
    print('[NAVIGATION] ⏹️ Stopping navigation tracking');
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

  /// Build next instruction card for turn-by-turn navigation
  Widget _buildNextInstructionCard() {
    if (_navigationInstructions.isEmpty ||
        _currentInstructionIndex >= _navigationInstructions.length) {
      return const SizedBox.shrink();
    }

    final instruction = _navigationInstructions[_currentInstructionIndex];
    final emoji = ManeuverParser.getTurnEmoji(instruction.turnType);
    final displayDistance =
        _currentInstructionRemainingMeters ?? instruction.distance;
    final distanceText = displayDistance > 1000
        ? '${(displayDistance / 1000).toStringAsFixed(1)} km'
        : '${displayDistance.toStringAsFixed(0)} m';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.white.withOpacity(0.96)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: AppColors.primary.withOpacity(0.14),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Turn emoji/icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 12),
          // Instruction details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  instruction.instruction,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.directions_rounded,
                      size: 12,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Setelah $distanceText',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${_currentInstructionIndex + 1}/${_navigationInstructions.length})',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Get icon based on place category
  IconData _getCategoryIcon(String? category) {
    switch (category?.toLowerCase()) {
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
      case 'market':
        return Icons.storefront_rounded;
      case 'gas_station':
        return Icons.local_gas_station_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFAFBFC),
              AppColors.primaryLight.withOpacity(0.08),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.white, Colors.white.withOpacity(0.95)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.15),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                AppColors.primaryGradient.createShader(bounds),
                            child: Text(
                              'Pilih Tempat',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isLoadingPlaces
                                ? 'Memuat tempat...'
                                : '${_places.length} Tempat Tersedia',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
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
                child: _isLoadingPlaces
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              'Memuat tempat...',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _places.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_off_rounded,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Tidak ada tempat tersedia',
                              style: AppTextStyles.heading3.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Silakan tambahkan tempat terlebih dahulu',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: _places.length,
                        itemBuilder: (context, index) {
                          final place = _places[index];
                          final isPrivatePlace = place.isPrivate;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
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
                                  Future.delayed(
                                    const Duration(milliseconds: 300),
                                    () {
                                      _safeMoveMap(_userLocation, 18.0);
                                    },
                                  );
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isPrivatePlace
                                          ? [
                                              AppColors.primary,
                                              const Color(0xFF1565C0),
                                            ]
                                          : [
                                              Colors.white,
                                              Colors.white.withOpacity(0.95),
                                            ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isPrivatePlace
                                            ? AppColors.primary.withOpacity(
                                                0.24,
                                              )
                                            : Colors.black.withOpacity(0.08),
                                        blurRadius: 15,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: isPrivatePlace
                                          ? Colors.white.withOpacity(0.28)
                                          : AppColors.primary.withOpacity(0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Icon Container
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          gradient: isPrivatePlace
                                              ? LinearGradient(
                                                  colors: [
                                                    Colors.white,
                                                    Colors.white.withOpacity(
                                                      0.92,
                                                    ),
                                                  ],
                                                )
                                              : AppColors.primaryGradient,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: isPrivatePlace
                                                  ? Colors.black.withOpacity(
                                                      0.12,
                                                    )
                                                  : AppColors.primary
                                                        .withOpacity(0.3),
                                              blurRadius: 12,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          _getCategoryIcon(place.category),
                                          color: isPrivatePlace
                                              ? AppColors.primary
                                              : Colors.white,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      // Place Details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              place.name,
                                              style: AppTextStyles.bodyLarge
                                                  .copyWith(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: isPrivatePlace
                                                        ? Colors.white
                                                        : AppColors.textPrimary,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              place.address,
                                              style: AppTextStyles.bodySmall
                                                  .copyWith(
                                                    color: isPrivatePlace
                                                        ? Colors.white
                                                              .withOpacity(0.82)
                                                        : AppColors
                                                              .textSecondary,
                                                    fontSize: 13,
                                                  ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              place.category.toUpperCase(),
                                              style: TextStyle(
                                                color: isPrivatePlace
                                                    ? Colors.white
                                                    : AppColors.primary,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Arrow Icon
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isPrivatePlace
                                              ? Colors.white.withOpacity(0.16)
                                              : AppColors.primary.withOpacity(
                                                  0.1,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.arrow_forward_rounded,
                                          color: isPrivatePlace
                                              ? Colors.white
                                              : AppColors.primary,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build map screen setelah memilih place
  Widget _buildNavigationAlertBadge({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapScreen() {
    final topInset = MediaQuery.of(context).padding.top;
    final fusionBadgeTop = topInset + 125;
    final passedRoutePoints = _getPassedRoutePoints();
    final remainingRoutePoints = _getRemainingRoutePoints();

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
                      width: 100,
                      height: 110,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.green.shade400,
                                    Colors.green.shade600,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withOpacity(0.6),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Transform.rotate(
                                  angle: _markerHeading * (math.pi / 180),
                                  child: const Icon(
                                    Icons.navigation_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withOpacity(0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Posisi Saya',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
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
                        child: GestureDetector(
                          onTap: () {
                            _goToLocation(
                              LatLng(
                                _selectedPlace!.latitude,
                                _selectedPlace!.longitude,
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Navigasi ke ${_selectedPlace!.name}',
                                ),
                                backgroundColor: AppColors.primary,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
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
                                  gradient: AppColors.primaryGradient,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.5),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                      spreadRadius: 1,
                                    ),
                                  ],
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    _getCategoryIcon(_selectedPlace!.category),
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
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _selectedPlace!.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
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
                  ],
                ),
              ],
            ),
          ),

          Positioned(
            top: fusionBadgeTop,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildNavigationAlertBadge(
                  icon: Icons.sensors_rounded,
                  text: _ultrasonicSensorText,
                ),
                if (_isOffRouteWarningVisible) ...[
                  const SizedBox(height: 8),
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
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.white, Colors.white.withOpacity(0.95)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.15),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Back button
                    GestureDetector(
                      onTap: () {
                        unawaited(_endNavigationSession());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Selected place info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                AppColors.primaryGradient.createShader(bounds),
                            child: Text(
                              _selectedPlace?.name ?? 'Navigasi',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedPlace != null
                                ? _selectedPlace!.address
                                : 'Pilih tempat untuk memulai navigasi',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
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

          // Zoom controls (Right side)
          Positioned(
            bottom: 200,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Zoom in button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _zoomIn,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.add_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Zoom out button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _zoomOut,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.remove_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Go to current location
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _goToCurrentLocation,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.my_location_rounded,
                          color: Colors.green.shade600,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Route info panel (Bottom)
          if (_selectedPlace != null)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Next instruction card (Turn-by-turn guidance)
                  if (_navigationInstructions.isNotEmpty &&
                      _currentInstructionIndex <
                          _navigationInstructions.length &&
                      !_isLoadingRoute &&
                      _routeLoadError.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildNextInstructionCard(),
                    ),

                  // Route info panel
                  _isLoadingRoute
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white,
                                Colors.white.withOpacity(0.95),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
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
                                        fontWeight: FontWeight.w700,
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
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.red,
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
                                        fontWeight: FontWeight.w700,
                                        color: Colors.red[700],
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
                      : _routeDistanceKm > 0
                      ? GestureDetector(
                          onTap: _showRouteInfoPanel,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white,
                                  Colors.white.withOpacity(0.95),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 20,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Route icon
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.route_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Route details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Rute ke ${_selectedPlace?.name ?? "Tujuan"}',
                                        style: AppTextStyles.bodyLarge.copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Text(
                                            '${_routeDistanceKm.toStringAsFixed(1)} km',
                                            style: const TextStyle(
                                              color: Colors.blue,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Container(
                                            width: 1,
                                            height: 16,
                                            color: AppColors.primary
                                                .withOpacity(0.3),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            '${_routeDurationMinutes.toStringAsFixed(0).split(".")[0]} menit',
                                            style: const TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Arrow icon
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.primary,
                                  size: 28,
                                ),
                              ],
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
