import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui' as ui;
import 'dart:async';
import '../../utils/constants.dart';
import '../../models/place_model.dart';
import '../../services/places_service.dart';
import '../../services/routing_service.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late MapController _mapController;
  final PlacesService _placesService = PlacesService();
  final RoutingService _routingService = RoutingService();
  
  // Default location: Bandung, Indonesia
  final LatLng defaultLocation = const LatLng(-6.9147, 107.6098);
  late LatLng _userLocation;
  bool _isLocationReady = false; // Track if real user location has been obtained
  StreamSubscription<Position>? _positionStreamSubscription; // For continuous location updates
  
  // Places from Firestore
  List<PlaceModel> _places = [];
  bool _isLoadingPlaces = true;
  
  // Track if user selected a place (untuk show map atau list)
  PlaceModel? _selectedPlace;
  
  // Route polyline points
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  String _routeLoadError = ''; // Error message for route
  
  // Route info (distance, duration)
  double _routeDistanceKm = 0.0;
  double _routeDurationMinutes = 0.0;
  double _routeDistanceMeters = 0.0;
  double _routeDurationSeconds = 0.0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _userLocation = defaultLocation;
    
    // Wait for widget to render, then load places
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getUserLocation();
      _loadPlaces();
    });
  }

  /// Load places from Firestore
  Future<void> _loadPlaces() async {
    try {
      print('[NAVIGATION] Loading places from Firestore...');
      final places = await _placesService.getAllPlaces();
      
      // Debug: Print each place
      for (var place in places) {
        print('[NAVIGATION] 📍 Place: ${place.name} (${place.category}) at [${place.latitude}, ${place.longitude}]');
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
            content: Text('Please enable Location Service'),
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
            content: Text('Location permission is required'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        try {
          print('[NAVIGATION] Getting initial GPS location (one-time, battery friendly)...');
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation,
            timeLimit: const Duration(seconds: 60),
          );

          print('[NAVIGATION] ✅ Initial location obtained: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy.toStringAsFixed(1)}m)');

          if (mounted) {
            setState(() {
              _userLocation = LatLng(position.latitude, position.longitude);
              _isLocationReady = true;
            });

            _mapController.move(_userLocation, 15.0);
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
    print('[NAVIGATION] Starting continuous location streaming for navigation...');
    
    // Cancel previous subscription if exists
    _positionStreamSubscription?.cancel();
    
    bool hasLoadedRouteOnceFromStreaming = false; // Track if route loaded from streaming
    
    // Start listening to location updates with high accuracy
    // Only update every 5 meters for detailed turn-by-turn navigation
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // Update every 5 meters for accurate turn guidance
      ),
    ).listen(
      (Position position) {
        print('[NAVIGATION] 📍 Navigation position: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy.toStringAsFixed(1)}m)');
        
        if (mounted) {
          setState(() {
            _userLocation = LatLng(position.latitude, position.longitude);
            
            // Mark as ready on first GPS location update
            if (!_isLocationReady) {
              _isLocationReady = true;
              print('[NAVIGATION] ✅ Real GPS location obtained from streaming!');
            }
          });
          
          // Load route on first GPS location to ensure accuracy
          if (!hasLoadedRouteOnceFromStreaming && _selectedPlace != null) {
            print('[NAVIGATION] Loading route with real GPS location from streaming...');
            _loadRoute();
            hasLoadedRouteOnceFromStreaming = true;
          }
          
          // Update map in real-time during navigation (with safety check)
          try {
            _mapController.move(_userLocation, 15.0);
          } catch (e) {
            print('[NAVIGATION] ⚠️ MapController not ready yet: $e');
          }
        }
      },
      onError: (e) {
        print('[NAVIGATION] ❌ Location stream error during navigation: $e');
      },
    );
  }

  /// Stop continuous location streaming to save battery
  void _stopLocationStreaming() {
    print('[NAVIGATION] Stopping location streaming (battery save mode)...');
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }

  @override
  void dispose() {
    _mapController.dispose();
    _positionStreamSubscription?.cancel(); // Cancel location subscription
    super.dispose();
  }

  void _goToLocation(LatLng location) {
    _mapController.move(location, 15.0);
  }

  void _zoomIn() {
    _mapController.move(
      _mapController.camera.center,
      _mapController.camera.zoom + 1,
    );
  }

  void _zoomOut() {
    _mapController.move(
      _mapController.camera.center,
      _mapController.camera.zoom - 1,
    );
  }

  void _goToCurrentLocation() {
    _mapController.move(_userLocation, 15.0);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Moving to current location: ${_userLocation.latitude.toStringAsFixed(4)}, ${_userLocation.longitude.toStringAsFixed(4)}'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Zoom map to fit all markers (user location + all places)
  void _zoomToFitAllMarkers() {
    if (_places.isEmpty) {
      _mapController.move(_userLocation, 15.0);
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

    _mapController.move(center, zoom);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Menampilkan ${_places.length} tempat + posisi Anda',
        ),
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
                          'Ke ${_selectedPlace?.name ?? 'Destinasi'}',
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
                icon: Icons.schedule_rounded,
                label: 'Perkiraan Waktu',
                value: '${_routeDurationMinutes.toStringAsFixed(0).split('.')[0]} menit',
                color: Colors.green,
              ),
              const SizedBox(height: 16),
              _buildRouteDetailItem(
                icon: Icons.location_on_rounded,
                label: 'Asal',
                value: 'Posisi Anda Saat Ini',
                color: Colors.orange,
              ),
              const SizedBox(height: 16),
              _buildRouteDetailItem(
                icon: Icons.flag_rounded,
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
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
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

    setState(() {
      _isLoadingRoute = true;
      _routePoints = [];
      _routeDistanceKm = 0.0;
      _routeDurationMinutes = 0.0;
      _routeLoadError = '';
    });

    try {
      print('[ROUTING] Loading route to ${_selectedPlace?.name}...');
      final destination =
          LatLng(_selectedPlace!.latitude, _selectedPlace!.longitude);

      // Get route polyline
      final points = await _routingService.getRoute(
        origin: _userLocation,
        destination: destination,
        profile: 'walking',
      );
      
      // Get route info (distance, duration)
      final routeInfo = await _routingService.getRouteInfo(
        origin: _userLocation,
        destination: destination,
        profile: 'walking',
      );

      if (mounted) {
        setState(() {
          _routePoints = points;
          _isLoadingRoute = false;
          _routeLoadError = '';
          _routeDistanceMeters = (routeInfo['distance'] as num).toDouble();
          _routeDurationSeconds = (routeInfo['duration'] as num).toDouble();
          _routeDistanceKm = (routeInfo['distance_km'] as num).toDouble();
          _routeDurationMinutes = (routeInfo['duration_minutes'] as num).toDouble();
        });
      }
      print('[ROUTING] ✅ Route loaded: ${_routeDistanceKm.toStringAsFixed(1)} km, ${_routeDurationMinutes.toStringAsFixed(0)} minutes');
    } catch (e) {
      print('[ROUTING] ❌ Error loading route: $e');
      if (mounted) {
        // Extract and format error message with better descriptions
        String errorMsg = e.toString().replaceFirst('Exception: ', '');
        
        // Map generic messages to user-friendly Indonesian messages
        String userFriendlyMsg = errorMsg;
        if (errorMsg.contains('Failed') || errorMsg.contains('network')) {
          userFriendlyMsg = '❌ Tidak dapat terhubung ke server.\nPastikan koneksi internet Anda stabil.';
        } else if (errorMsg.contains('timeout') || errorMsg.contains('Time')) {
          userFriendlyMsg = '⏱️ Koneksi lambat atau server tidak merespons.\nCoba lagi dalam beberapa saat.';
        } else if (errorMsg.contains('connection')) {
          userFriendlyMsg = '📡 Tidak ada koneksi internet.\nSilakan periksa jaringan Anda.';
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
                                      
                                      // Start continuous location streaming for detailed navigation
                                      // Route will load automatically from streaming when real GPS location is obtained
                                      Future.delayed(
                                        const Duration(milliseconds: 1500),
                                        () {
                                          if (mounted) {
                                            _startLocationStreaming();
                                          }
                                        },
                                      );
                                      
                                      // Center map ke lokasi user (bukan tempat tujuan)
                                      Future.delayed(
                                        const Duration(milliseconds: 300),
                                        () {
                                          _mapController.move(
                                            _userLocation,
                                            15.0,
                                          );
                                        },
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(16),
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
                                            color: Colors.black.withOpacity(0.08),
                                            blurRadius: 15,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                        border: Border.all(
                                          color: AppColors.primary.withOpacity(0.1),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          // Icon Container
                                          Container(
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              gradient: AppColors.primaryGradient,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppColors.primary
                                                      .withOpacity(0.3),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              _getCategoryIcon(place.category),
                                              color: Colors.white,
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
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  place.address,
                                                  style: AppTextStyles.bodySmall
                                                      .copyWith(
                                                    color: AppColors
                                                        .textSecondary,
                                                    fontSize: 13,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  place.category.toUpperCase(),
                                                  style: TextStyle(
                                                    color: AppColors.primary,
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
                                              color: AppColors.primary
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              Icons.arrow_forward_rounded,
                                              color: AppColors.primary,
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
  Widget _buildMapScreen() {
    return Scaffold(
      body: Stack(
        children: [
          // Map - Full screen background
          SizedBox.expand(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _userLocation,
                initialZoom: 15.0,
                minZoom: 5.0,
                maxZoom: 18.0,
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
                
                // Route Polyline (jika route sudah di-load)
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
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
                      point: _userLocation,
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
                              child: const Center(
                                child: Icon(
                                  Icons.my_location_rounded,
                                  color: Colors.white,
                                  size: 24,
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
                            _goToLocation(LatLng(
                              _selectedPlace!.latitude,
                              _selectedPlace!.longitude,
                            ));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('Navigasi ke ${_selectedPlace!.name}'),
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
                                    _getCategoryIcon(
                                        _selectedPlace!.category),
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
          
          // Debug: Places Count
          Positioned(
            top: 80,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                'Tempat: ${_places.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
                        _stopLocationStreaming(); // Stop detailed tracking when navigation ends
                        setState(() {
                          _selectedPlace = null;
                          _routePoints.clear();
                        });
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
              child: _isLoadingRoute
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
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Rute ke ${_selectedPlace?.name ?? "Destinasi"}',
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
                                                color: AppColors.primary.withOpacity(0.3),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                '${_routeDurationMinutes.toStringAsFixed(0).split(".")[0]} min',
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
