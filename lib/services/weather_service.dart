import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      temperature: (json['temperature'] as num).toDouble(),
      humidity: json['humidity'] as int,
      windSpeed: (json['windSpeed'] as num).toDouble(),
      weatherCondition: json['weatherCondition'] as String,
      locationName: json['locationName'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'temperature': temperature,
      'humidity': humidity,
      'windSpeed': windSpeed,
      'weatherCondition': weatherCondition,
      'locationName': locationName,
    };
  }
}

class WeatherService {
  static const String _openMeteoUrl = 'https://api.open-meteo.com/v1/forecast';
  static const String _reverseGeoUrl =
      'https://nominatim.openstreetmap.org/reverse';
  static const String _cachedWeatherKey = 'cached_weather_data';

  String? _cachedLocationName;

  /// Get cached weather if available
  Future<WeatherData?> getCachedWeather() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_cachedWeatherKey);
      if (jsonString == null) return null;
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      return WeatherData.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  Future<void> _cacheWeather(WeatherData weatherData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedWeatherKey, jsonEncode(weatherData.toJson()));
    } catch (e) {
      // ignore cache write error
    }
  }

  /// Get current weather based on user's GPS location
  Future<WeatherData?> getWeatherByLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return await getCachedWeather() ?? _getMockWeather();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return await getCachedWeather() ?? _getMockWeather();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 30),
      );

      // Start reverse geocoding in the background so weather can render first.
      unawaited(
        _getLocationName(position.latitude, position.longitude)
            .then((locationName) {
          _cachedLocationName = locationName;
        }).catchError((Object error) {
          // ignore background geocoding error
        }),
      );

      // Fetch weather data immediately from coordinates without waiting
      // for reverse geocoding, so the header can show faster.
      final weatherData = await _fetchWeather(
        position.latitude,
        position.longitude,
        _cachedLocationName ?? 'Lokasi Saat Ini',
      );

      if (weatherData != null) {
        unawaited(_cacheWeather(weatherData));
        return weatherData;
      }

      return await getCachedWeather() ?? _getMockWeather();
    } catch (e) {
      final cached = await getCachedWeather();
      return cached ?? _getMockWeather();
    }
  }

  /// Fetch weather data from Open-Meteo API
  Future<WeatherData?> _fetchWeather(
    double latitude,
    double longitude,
    String locationName,
  ) async {
    try {
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

        return weatherData;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Get location name from coordinates using Nominatim (OpenStreetMap)
  Future<String> _getLocationName(double latitude, double longitude) async {
    try {
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

        return city;
      } else {
        return 'Lokasi Saat Ini';
      }
    } catch (e) {
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
    return WeatherData(
      temperature: 28.5,
      humidity: 60,
      windSpeed: 12.5,
      weatherCondition: 'Berawan',
      locationName: 'Jakarta',
    );
  }
}
