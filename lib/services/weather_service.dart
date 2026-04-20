import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class WeatherData {
  final double temperature;
  final int humidity;
  final double windSpeed;
  final String weatherCondition;
  final String locationName;

  WeatherData({
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.weatherCondition,
    required this.locationName,
  });
}

class WeatherService {
  static const String _openMeteoUrl = 'https://api.open-meteo.com/v1/forecast';
  static const String _reverseGeoUrl =
      'https://nominatim.openstreetmap.org/reverse';

  /// Get current weather based on user's GPS location
  Future<WeatherData?> getWeatherByLocation() async {
    try {
      print('[WEATHER] Starting weather fetch...');
      
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      print('[WEATHER] Initial permission: $permission');
      
      if (permission == LocationPermission.denied) {
        print('[WEATHER] Requesting location permission...');
        permission = await Geolocator.requestPermission();
        print('[WEATHER] Permission after request: $permission');
        if (permission == LocationPermission.denied) {
          print('[WEATHER] Location permission denied');
          return _getMockWeather();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('[WEATHER] Location permission permanently denied');
        return _getMockWeather();
      }

      print('[WEATHER] Getting current position...');
      // Get current position with longer timeout
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 30),
      );

      print('[WEATHER] Got location: ${position.latitude}, ${position.longitude}');

      // Get location name from coordinates
      final locationName =
          await _getLocationName(position.latitude, position.longitude);

      // Fetch weather data from Open-Meteo
      final weatherData = await _fetchWeather(
        position.latitude,
        position.longitude,
        locationName,
      );

      return weatherData ?? _getMockWeather();
    } catch (e) {
      print('[WEATHER] Error getting weather: $e');
      // Return mock data for development
      return _getMockWeather();
    }
  }

  /// Fetch weather data from Open-Meteo API
  Future<WeatherData?> _fetchWeather(
    double latitude,
    double longitude,
    String locationName,
  ) async {
    try {
      print('[WEATHER] Fetching weather for $latitude, $longitude...');
      
      final url = Uri.parse(
        '$_openMeteoUrl?latitude=$latitude&longitude=$longitude&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&timezone=auto',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('Weather API timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final current = data['current'];

        // Map weather codes to descriptions
        final weatherCondition = _getWeatherDescription(current['weather_code']);

        final weatherData = WeatherData(
          temperature: (current['temperature_2m'] as num).toDouble(),
          humidity: current['relative_humidity_2m'] as int,
          windSpeed: (current['wind_speed_10m'] as num).toDouble(),
          weatherCondition: weatherCondition,
          locationName: locationName,
        );

        print(
            '[WEATHER] Got weather: ${weatherData.temperature}°C, ${weatherData.weatherCondition}');
        return weatherData;
      } else {
        print('[WEATHER] Failed to fetch weather: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('[WEATHER] Error fetching weather data: $e');
      return null;
    }
  }

  /// Get location name from coordinates using Nominatim (OpenStreetMap)
  Future<String> _getLocationName(double latitude, double longitude) async {
    try {
      print('[WEATHER] Fetching location name for $latitude, $longitude...');
      
      final url = Uri.parse(
        '$_reverseGeoUrl?format=json&lat=$latitude&lon=$longitude&zoom=10&addressdetails=1',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Nominatim timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'];

        // Try to get city name, fallback to suburb or village
        final city = address['city'] ??
            address['town'] ??
            address['suburb'] ??
            address['village'] ??
            'Lokasi Saat Ini';

        print('[WEATHER] Location name: $city');
        return city;
      } else {
        print('[WEATHER] Failed to get location name: ${response.statusCode}');
        return 'Lokasi Saat Ini';
      }
    } catch (e) {
      print('[WEATHER] Error getting location name: $e');
      return 'Lokasi Saat Ini';
    }
  }

  /// Convert WMO weather codes to readable descriptions
  String _getWeatherDescription(int code) {
    switch (code) {
      case 0:
        return 'Cerah';
      case 1:
      case 2:
        return 'Berawan';
      case 3:
        return 'Mendung';
      case 45:
      case 48:
        return 'Berkabut';
      case 51:
      case 53:
      case 55:
        return 'Gerimis';
      case 61:
      case 63:
      case 65:
        return 'Hujan';
      case 71:
      case 73:
      case 75:
        return 'Salju';
      case 77:
        return 'Salju Lambat';
      case 80:
      case 81:
      case 82:
        return 'Hujan Lebat';
      case 85:
      case 86:
        return 'Salju Lebat';
      case 95:
      case 96:
      case 99:
        return 'Badai';
      default:
        return 'Tidak Diketahui';
    }
  }

  /// Get weather emoji based on condition
  static String getWeatherEmoji(String condition) {
    switch (condition) {
      case 'Cerah':
        return '☀️';
      case 'Berawan':
        return '⛅';
      case 'Mendung':
        return '☁️';
      case 'Berkabut':
        return '🌫️';
      case 'Gerimis':
        return '🌦️';
      case 'Hujan':
      case 'Hujan Lebat':
        return '🌧️';
      case 'Salju':
      case 'Salju Lambat':
      case 'Salju Lebat':
        return '❄️';
      case 'Badai':
        return '⛈️';
      default:
        return '🌥️';
    }
  }

  /// Get mock weather data for development/testing
  WeatherData _getMockWeather() {
    print('[WEATHER] Using mock weather data for development');
    return WeatherData(
      temperature: 28.5,
      humidity: 60,
      windSpeed: 12.5,
      weatherCondition: 'Berawan',
      locationName: 'Jakarta',
    );
  }
}
