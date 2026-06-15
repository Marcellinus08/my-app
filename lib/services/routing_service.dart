import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../models/navigation_instruction_model.dart';

class RoutingService {
  // Menggunakan OSRM Public (router.project-osrm.org) - gratis, stabil di Android, tidak perlu API key
  // Profiles: 'car' untuk rute kendaraan, 'foot' untuk rute pejalan kaki
  // Fallback logic diterapkan jika OSRM mengembalikan durasi yang sama
  static const String _baseUrlCar =
      'https://router.project-osrm.org/route/v1/car';
  static const String _baseUrlFoot =
      'https://router.project-osrm.org/route/v1/foot';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  /// Get base URL berdasarkan profile
  /// Profiles: 'car' atau 'foot' (default: 'foot')
  String _getBaseUrl(String profile) {
    if (profile == 'car') {
      return _baseUrlCar;
    } else {
      return _baseUrlFoot;
    }
  }

  /// Get polyline route points dari origin ke destination
  /// Returns list of LatLng points yang membentuk rute
  /// Selalu menggunakan profile 'foot' untuk konsistensi polyline
  Future<List<LatLng>> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final baseUrl = _baseUrlFoot;
      // OSRM format: lon,lat;lon,lat
      final coordinates =
          '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
      final url =
          '$baseUrl/$coordinates?geometries=geojson&overview=full&steps=true';

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final data = response.data;

        if (data['code'] != 'Ok') {
          throw Exception(
            'OSRM Error: ${data['code']} - ${data['message'] ?? 'Unknown error'}',
          );
        }

        final routes = data['routes'] as List;
        if (routes.isEmpty) {
          throw Exception('No route found');
        }

        final geometry = routes[0]['geometry'];
        final coordinates = geometry['coordinates'] as List;

        // Convert dari [lon, lat] ke LatLng
        final polylinePoints = coordinates
            .map(
              (coord) => LatLng(
                (coord[1] as num).toDouble(),
                (coord[0] as num).toDouble(),
              ),
            )
            .toList();

        return polylinePoints;
      } else {
        throw Exception('Failed to get route: ${response.statusCode}');
      }
    } catch (e) {
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          throw Exception('Koneksi lambat. Coba lagi dalam beberapa saat.');
        } else if (e.type == DioExceptionType.connectionError) {
          throw Exception(
            'Tidak ada koneksi internet. Silakan periksa jaringan Anda.',
          );
        }
      }
      rethrow;
    }
  }

  /// Get route details (distance, duration, dll)
  /// profile: 'car' atau 'foot' (default: 'foot')
  Future<Map<String, dynamic>> getRouteInfo({
    required LatLng origin,
    required LatLng destination,
    String profile = 'foot',
  }) async {
    try {
      final baseUrl = _getBaseUrl(profile);

      final coordinates =
          '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
      final url = '$baseUrl/$coordinates?overview=full&geometries=geojson';

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final data = response.data;

        if (data['code'] != 'Ok') {
          throw Exception('OSRM Error: ${data['code']}');
        }

        final routes = data['routes'] as List;
        if (routes.isEmpty) {
          throw Exception('No route found');
        }

        final route = routes[0];
        final rawDuration = route['duration']; // dalam detik
        final rawDistance = route['distance']; // dalam meter
        final durationMinutes = (rawDuration as num) / 60;
        final distanceKm = (rawDistance as num) / 1000;

        return {
          'distance': rawDistance, // dalam meter
          'duration': rawDuration, // dalam detik
          'distance_km': distanceKm,
          'duration_minutes': durationMinutes,
        };
      } else {
        throw Exception('Failed to get route info: ${response.statusCode}');
      }
    } catch (e) {
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          throw Exception('Koneksi lambat. Coba lagi dalam beberapa saat.');
        } else if (e.type == DioExceptionType.connectionError) {
          throw Exception(
            'Tidak ada koneksi internet. Silakan periksa jaringan Anda.',
          );
        }
      }
      rethrow;
    }
  }

  /// Get comparison of foot vs car durations directly from OSRM
  /// Tanpa fallback logic - hanya mengambil data langsung dari OSRM
  Future<Map<String, dynamic>> getComparisonDurations({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final footInfo = await getRouteInfo(
        origin: origin,
        destination: destination,
        profile: 'foot',
      );

      final carInfo = await getRouteInfo(
        origin: origin,
        destination: destination,
        profile: 'car',
      );

      // Calculate foot duration menggunakan metode Google Maps
      // Kecepatan pedestrian rata-rata: 1.4 m/s (sama seperti Google Maps)
      final distanceMeters = footInfo['distance'] as num;
      const double pedestrianSpeedMs = 1.4; // meter per second
      final footDuration = (distanceMeters / pedestrianSpeedMs)
          .toInt(); // dalam detik

      final carDuration = carInfo['duration'] as num;

      return {
        'foot_duration': footDuration,
        'foot_duration_minutes': (footDuration as num) / 60,
        'car_duration': carDuration,
        'car_duration_minutes': carDuration / 60,
        'distance': footInfo['distance'],
        'distance_km': footInfo['distance_km'],
      };
    } catch (e) {
      rethrow;
    }
  }

  /// Test method untuk verify OSRM response untuk foot vs car
  Future<void> testOsrmDifference() async {
    try {
      // Test dengan koordinat berbeda yang seharusnya memiliki perbedaan signifikan
      // Dari Alun-alun Bandung ke Tangkuban Perahu (lebih jauh)
      final origin = LatLng(-6.9147, 107.6098);
      final destination = LatLng(-6.7727, 107.5778);

      await getRouteInfo(
        origin: origin,
        destination: destination,
        profile: 'foot',
      );

      await getRouteInfo(
        origin: origin,
        destination: destination,
        profile: 'car',
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Get turn-by-turn navigation instructions
  /// Mengembalikan list NavigationInstruction yang berisi petunjuk belok dan nama jalan
  Future<List<NavigationInstruction>> getNavigationInstructions({
    required LatLng origin,
    required LatLng destination,
    String profile = 'foot',
  }) async {
    try {
      final baseUrl = _getBaseUrl(profile);

      final coordinates =
          '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
      // Tambahkan parameter ?steps=true&annotations=distance,duration untuk mendapat detail steps
      final url =
          '$baseUrl/$coordinates?overview=full&geometries=geojson&steps=true&annotations=distance,duration';

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final data = response.data;

        if (data['code'] != 'Ok') {
          throw Exception('OSRM Error: ${data['code']}');
        }

        final routes = data['routes'] as List;
        if (routes.isEmpty) {
          throw Exception('No route found');
        }

        final route = routes[0];
        final legs = route['legs'] as List;

        List<NavigationInstruction> instructions = [];

        // Iterate through each leg (segment antara 2 waypoint)
        for (var leg in legs) {
          final steps = leg['steps'] as List;

          for (var step in steps) {
            final maneuver = step['maneuver'] as Map;
            final stepGeometry = step['geometry'];
            final stepCoordinates = stepGeometry['coordinates'] as List;

            // Convert geometry to polyline points
            final polylinePoints = stepCoordinates
                .map(
                  (coord) => LatLng(
                    (coord[1] as num).toDouble(),
                    (coord[0] as num).toDouble(),
                  ),
                )
                .toList();

            // Extract maneuver info
            final maneuverType = maneuver['type'] as String?;
            final maneuverModifier = maneuver['modifier'] as String?;
            final bearingBefore =
                (maneuver['bearing_before'] as num?)?.toDouble() ?? 0.0;
            final bearing =
                (maneuver['bearing_after'] as num?)?.toDouble() ?? 0.0;
            final location = LatLng(
              (maneuver['location'][1] as num).toDouble(),
              (maneuver['location'][0] as num).toDouble(),
            );

            // Extract step info
            final roadName = (step['name'] as String?) ?? 'Jalan';
            final distance = ((step['distance'] as num?)?.toDouble()) ?? 0.0;
            final duration = ((step['duration'] as num?)?.toDouble()) ?? 0.0;

            // Parse turn type
            var turnType = ManeuverParser.parseTurnType(
              maneuverType,
              maneuverModifier,
            );
            if (maneuverType?.trim().toLowerCase() != 'depart') {
              turnType = _inferTurnTypeFromBearing(
                turnType,
                bearingBefore: bearingBefore,
                bearingAfter: bearing,
              );
            }

            // Generate readable instruction
            final instruction = ManeuverParser.getInstructionText(
              turnType,
              roadName,
            );

            final normalizedManeuverType =
                maneuverType?.trim().toLowerCase() ?? '';
            final normalizedModifier =
                maneuverModifier?.trim().toLowerCase() ?? '';

            if (normalizedManeuverType == 'arrive') {
              _mergeStepIntoPreviousInstruction(
                instructions,
                distance: distance,
                duration: duration,
                polylinePoints: polylinePoints,
              );
              continue;
            }

            final shouldCreateInstruction =
                instructions.isEmpty ||
                _isActionableManeuver(
                  normalizedManeuverType,
                  normalizedModifier,
                  bearingBefore: bearingBefore,
                  bearingAfter: bearing,
                );

            if (!shouldCreateInstruction) {
              _mergeStepIntoPreviousInstruction(
                instructions,
                distance: distance,
                duration: duration,
                polylinePoints: polylinePoints,
              );
              continue;
            }

            instructions.add(
              NavigationInstruction(
                instruction: instruction,
                roadName: roadName,
                distance: distance,
                duration: duration,
                turnType: turnType,
                bearing: bearing,
                location: location,
                polylinePoints: polylinePoints,
              ),
            );
          }
        }

        return instructions;
      } else {
        throw Exception(
          'Failed to get navigation instructions: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          throw Exception('Koneksi lambat. Coba lagi dalam beberapa saat.');
        } else if (e.type == DioExceptionType.connectionError) {
          throw Exception(
            'Tidak ada koneksi internet. Silakan periksa jaringan Anda.',
          );
        }
      }
      rethrow;
    }
  }

  bool _isActionableManeuver(
    String type,
    String modifier, {
    required double bearingBefore,
    required double bearingAfter,
  }) {
    if (type == 'depart') return true;

    final hasDirectionalModifier =
        modifier.contains('left') ||
        modifier.contains('right') ||
        modifier.contains('uturn');
    if (hasDirectionalModifier) {
      return true;
    }

    final explicitlyActionable = const {
      'uturn',
      'u-turn',
      'end of road',
      'fork',
      'merge',
      'on ramp',
      'off ramp',
      'roundabout',
      'rotary',
      'exit roundabout',
      'exit rotary',
    }.contains(type);
    if (explicitlyActionable) return true;

    final rawBearingDifference = (bearingAfter - bearingBefore).abs() % 360;
    final bearingDifference = rawBearingDifference > 180
        ? 360 - rawBearingDifference
        : rawBearingDifference;

    return bearingDifference >= 25;
  }

  TurnType _inferTurnTypeFromBearing(
    TurnType parsedType, {
    required double bearingBefore,
    required double bearingAfter,
  }) {
    if (parsedType != TurnType.unknown && parsedType != TurnType.straight) {
      return parsedType;
    }

    final signedDifference = ((bearingAfter - bearingBefore + 540) % 360) - 180;
    if (signedDifference.abs() < 25) {
      return parsedType;
    }

    if (signedDifference > 0) {
      return signedDifference >= 60 ? TurnType.right : TurnType.slightRight;
    }
    return signedDifference <= -60 ? TurnType.left : TurnType.slightLeft;
  }

  void _mergeStepIntoPreviousInstruction(
    List<NavigationInstruction> instructions, {
    required double distance,
    required double duration,
    required List<LatLng> polylinePoints,
  }) {
    if (instructions.isEmpty) return;

    final previous = instructions.last;
    final mergedPolyline = <LatLng>[...previous.polylinePoints];

    for (final point in polylinePoints) {
      final isDuplicate =
          mergedPolyline.isNotEmpty &&
          mergedPolyline.last.latitude == point.latitude &&
          mergedPolyline.last.longitude == point.longitude;
      if (!isDuplicate) {
        mergedPolyline.add(point);
      }
    }

    instructions[instructions.length - 1] = NavigationInstruction(
      instruction: previous.instruction,
      roadName: previous.roadName,
      distance: previous.distance + distance,
      duration: previous.duration + duration,
      turnType: previous.turnType,
      bearing: previous.bearing,
      location: previous.location,
      polylinePoints: mergedPolyline,
    );
  }

  /// Find next instruction based on current location
  /// Mengembalikan index instruksi berikutnya atau -1 jika sudah sampai
  /// distanceThreshold: jarak dalam meter untuk dianggap sudah mencapai instruksi
  int findNextInstructionIndex({
    required LatLng currentLocation,
    required List<NavigationInstruction> instructions,
    double distanceThreshold = 50.0, // 50 meter threshold
  }) {
    const Distance distance = Distance();

    for (int i = 0; i < instructions.length; i++) {
      final instruction = instructions[i];
      final distanceToInstruction = distance.as(
        LengthUnit.Meter,
        currentLocation,
        instruction.location,
      );

      if (distanceToInstruction <= distanceThreshold) {
        // Sudah mencapai instruksi ini, return index berikutnya
        return i + 1 < instructions.length ? i + 1 : -1;
      }
    }

    // Belum mencapai instruksi pertama
    return 0;
  }
}
