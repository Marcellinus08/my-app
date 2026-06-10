import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/navigation_history_service.dart';

class LiveTrackingScreen extends StatefulWidget {
  final String pairedUserUid; // UID of the visually impaired user being tracked

  const LiveTrackingScreen({super.key, required this.pairedUserUid});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  late final MapController _mapController;
  Timer? _realtimeUpdateTimer;
  LatLng? _lastFocusedUserLocation;
  final NavigationHistoryService _navigationHistoryService =
      NavigationHistoryService();
  final Set<String> _offlineCancellationRequests = {};

  static const LatLng _fallbackCenter = LatLng(-6.9147, 107.6098);
  static const double _initialTrackingZoom = 16.0;
  static const double _minimumCameraMoveMeters = 8.0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _realtimeUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          // Trigger rebuild untuk update status offline dan last update.
        });
      }
    });
  }

  @override
  void dispose() {
    _realtimeUpdateTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  bool isTrackingFresh(Timestamp? updatedAt) {
    if (updatedAt == null) return false;
    final age = DateTime.now().difference(updatedAt.toDate());
    return age.inSeconds <= 60;
  }

  void _cancelNavigationIfUserOffline({
    required bool isNavigating,
    required String? tripId,
    required Timestamp? updatedAt,
  }) {
    final normalizedTripId = tripId?.trim() ?? '';
    final requestKey = widget.pairedUserUid;
    if (updatedAt == null ||
        isTrackingFresh(updatedAt) ||
        !_offlineCancellationRequests.add(requestKey)) {
      return;
    }

    unawaited(
      _navigationHistoryService.cancelOngoingTripsBecauseUserOffline(
        userId: widget.pairedUserUid,
        preferredTripId: isNavigating ? normalizedTripId : null,
      ),
    );
  }

  bool isGpsActiveTracking(Map<String, dynamic>? liveData) {
    if (liveData == null) return false;
    final lat = _parseDouble(liveData['lat']);
    final lng = _parseDouble(liveData['lng']);
    final updatedAt = _parseTimestamp(liveData['updatedAt']);
    return lat != null && lng != null && isTrackingFresh(updatedAt);
  }

  String formatLastUpdate(Timestamp? updatedAt) {
    if (updatedAt == null) return '-';
    final duration = DateTime.now().difference(updatedAt.toDate());
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds} detik lalu';
    }
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} menit lalu';
    }
    if (duration.inHours < 24) {
      return '${duration.inHours} jam lalu';
    }
    return '${duration.inDays} hari lalu';
  }

  String buildGpsStatusText(bool isGpsActive) {
    return isGpsActive ? 'Aktif' : 'Tidak aktif';
  }

  String buildNavigationText(bool isGpsActive, bool isNavigating) {
    if (!isGpsActive) {
      return '-';
    }
    return isNavigating ? 'Aktif' : 'Tidak aktif';
  }

  double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Timestamp? _parseTimestamp(dynamic value) {
    return value is Timestamp ? value : null;
  }

  LatLng? _parseLatLng(dynamic lat, dynamic lng) {
    final parsedLat = _parseDouble(lat);
    final parsedLng = _parseDouble(lng);
    if (parsedLat == null || parsedLng == null) return null;
    return LatLng(parsedLat, parsedLng);
  }

  List<LatLng> _parsePolyline(dynamic value) {
    if (value is! List) return [];

    return value
        .map((point) {
          if (point is Map) {
            return _parseLatLng(point['lat'], point['lng']);
          }
          return null;
        })
        .whereType<LatLng>()
        .toList();
  }

  void _focusMapOnUserLocation(
    LatLng userLocation, {
    required bool hasLocation,
    bool force = false,
  }) {
    if (!hasLocation) return;

    final previousLocation = _lastFocusedUserLocation;
    if (!force && previousLocation != null) {
      final movedMeters = const Distance().as(
        LengthUnit.Meter,
        previousLocation,
        userLocation,
      );
      if (movedMeters < _minimumCameraMoveMeters) return;
    }

    _lastFocusedUserLocation = userLocation;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final currentZoom = _mapController.camera.zoom;
        _mapController.move(
          userLocation,
          currentZoom > 0 ? currentZoom : _initialTrackingZoom,
        );
      } catch (_) {
        // MapController can throw before FlutterMap finishes attaching.
      }
    });
  }

  Widget _buildMap({
    required LatLng userLocation,
    required double heading,
    required bool hasLocation,
    required String gpsStatus,
    List<LatLng> activeRoute = const [],
    LatLng? destination,
  }) {
    _focusMapOnUserLocation(userLocation, hasLocation: hasLocation);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: userLocation,
        initialZoom: _initialTrackingZoom,
        onMapReady: () => _focusMapOnUserLocation(
          userLocation,
          hasLocation: hasLocation,
          force: true,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.app',
        ),
        if (activeRoute.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: activeRoute,
                color: Colors.blue,
                strokeWidth: 5,
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (destination != null)
              Marker(
                point: destination,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(
                    Icons.flag_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            if (hasLocation)
              Marker(
                point: userLocation,
                child: Transform.rotate(
                  angle: heading * (math.pi / 180),
                  child: Container(
                    decoration: BoxDecoration(
                      color: gpsStatus == 'gps_live'
                          ? Colors.blue
                          : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pelacakan Langsung')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('live_tracking')
            .doc(widget.pairedUserUid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Data lokasi belum dapat dimuat. Periksa koneksi lalu coba lagi.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final hasLiveData = snapshot.hasData && snapshot.data?.exists == true;
          final data = hasLiveData ? snapshot.data!.data() : null;

          final lat = _parseDouble(data?['lat']);
          final lng = _parseDouble(data?['lng']);
          final heading = _parseDouble(data?['heading']) ?? 0.0;
          final isNavigating = data?['isNavigating'] as bool? ?? false;
          final currentTripId = data?['currentTripId'] as String?;
          final gpsStatus = data?['gpsStatus'] as String? ?? '-';
          final destinationName =
              (data?['destinationName'] as String?)?.isNotEmpty == true
              ? data!['destinationName'] as String
              : '-';
          final batteryLevel = data?['batteryLevel'];
          final updatedAt = _parseTimestamp(data?['updatedAt']);
          _cancelNavigationIfUserOffline(
            isNavigating: isNavigating,
            tripId: currentTripId,
            updatedAt: updatedAt,
          );
          final isGpsActive = isGpsActiveTracking(data);
          final isNavigationActive = isGpsActive && isNavigating;
          final hasLocation = isGpsActive && lat != null && lng != null;
          final userLocation = hasLocation ? LatLng(lat, lng) : _fallbackCenter;

          final displayDestination = isNavigationActive ? destinationName : '-';
          final navigationText = buildNavigationText(isGpsActive, isNavigating);
          final displayHeading = isNavigationActive
              ? '${heading.toStringAsFixed(0)}°'
              : '-';
          final displayBattery = isGpsActive && batteryLevel != null
              ? '$batteryLevel%'
              : '-';
          final displayLastUpdate = isNavigationActive
              ? formatLastUpdate(updatedAt)
              : '-';
          final gpsStatusText = buildGpsStatusText(isGpsActive);

          return Column(
            children: [
              // Status info
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.blue.shade50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GPS: $gpsStatusText'),
                    Text('Tujuan: $displayDestination'),
                    Text('Navigasi: $navigationText'),
                    Text('Arah: $displayHeading'),
                    Text('Baterai: $displayBattery'),
                    Text('Terakhir diperbarui: $displayLastUpdate'),
                  ],
                ),
              ),
              Expanded(
                child:
                    !isNavigationActive ||
                        currentTripId == null ||
                        currentTripId.isEmpty
                    ? _buildMap(
                        userLocation: userLocation,
                        heading: heading,
                        hasLocation: hasLocation,
                        gpsStatus: gpsStatus,
                      )
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('navigation_history')
                            .doc(currentTripId)
                            .snapshots(),
                        builder: (context, tripSnapshot) {
                          final tripData = tripSnapshot.data?.data();
                          final remainingRoute = _parsePolyline(
                            tripData?['remainingRoutePolyline'],
                          );
                          final routePolyline = _parsePolyline(
                            tripData?['routePolyline'],
                          );
                          final activeRoute = remainingRoute.isNotEmpty
                              ? remainingRoute
                              : routePolyline;
                          final destination = _parseLatLng(
                            tripData?['destinationLat'],
                            tripData?['destinationLng'],
                          );

                          return _buildMap(
                            userLocation: hasLocation || activeRoute.isEmpty
                                ? userLocation
                                : activeRoute.first,
                            heading: heading,
                            hasLocation: hasLocation,
                            gpsStatus: gpsStatus,
                            activeRoute: activeRoute,
                            destination: destination,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
