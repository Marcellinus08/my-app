import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class RoutingService {
  // Menggunakan OSRM (Open Source Routing Machine) - gratis, tidak perlu API key
  static const String _baseUrl = 'https://router.project-osrm.org/route/v1/driving';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  /// Get polyline route points dari origin ke destination
  /// Returns list of LatLng points yang membentuk rute
  Future<List<LatLng>> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      // OSRM format: lon,lat;lon,lat
      final coordinates =
          '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
      final url = '$_baseUrl/$coordinates?geometries=geojson&overview=full';

      print('[ROUTING] Requesting route from: $url');

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final data = response.data;
        
        if (data['code'] != 'Ok') {
          throw Exception('OSRM Error: ${data['code']} - ${data['message'] ?? 'Unknown error'}');
        }

        final routes = data['routes'] as List;
        if (routes.isEmpty) {
          throw Exception('No route found');
        }

        final geometry = routes[0]['geometry'];
        final coordinates = geometry['coordinates'] as List;

        // Convert dari [lon, lat] ke LatLng
        final polylinePoints = coordinates
            .map((coord) => LatLng(coord[1] as double, coord[0] as double))
            .toList();

        return polylinePoints;
      } else {
        throw Exception('Failed to get route: ${response.statusCode}');
      }
    } catch (e) {
      print('[ROUTING] ❌ Error getting route: $e');
      rethrow;
    }
  }

  /// Get route details (distance, duration, dll)
  Future<Map<String, dynamic>> getRouteInfo({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final coordinates =
          '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
      final url = '$_baseUrl/$coordinates?overview=full';

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

        return {
          'distance': route['distance'], // dalam meter
          'duration': route['duration'], // dalam detik
          'distance_km': (route['distance'] as num) / 1000,
          'duration_minutes': (route['duration'] as num) / 60,
        };
      } else {
        throw Exception('Failed to get route info: ${response.statusCode}');
      }
    } catch (e) {
      print('[ROUTING] ❌ Error getting route info: $e');
      rethrow;
    }
  }
}
