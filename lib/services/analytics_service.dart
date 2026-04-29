import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();

  factory AnalyticsService() {
    return _instance;
  }

  AnalyticsService._internal();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> logStartNavigation({
    required String destinationName,
    required String destinationCategory,
    required double initialDistanceKm,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'start_navigation',
        parameters: {
          'destination_name': destinationName,
          'destination_category': destinationCategory,
          'initial_distance_km': initialDistanceKm,
        },
      );
    } catch (e) {
      print('[ANALYTICS] Failed to log start_navigation: $e');
    }
  }

  Future<void> logEndNavigation({
    required String destinationName,
    required String endReason,
    required int durationSeconds,
    required double remainingDistanceKm,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'end_navigation',
        parameters: {
          'destination_name': destinationName,
          'end_reason': endReason,
          'duration_seconds': durationSeconds,
          'remaining_distance_km': remainingDistanceKm,
        },
      );
    } catch (e) {
      print('[ANALYTICS] Failed to log end_navigation: $e');
    }
  }

  Future<void> logOffRouteDetected({
    required String destinationName,
    required double distanceToRouteMeters,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'off_route_detected',
        parameters: {
          'destination_name': destinationName,
          'distance_to_route_m': distanceToRouteMeters,
        },
      );
    } catch (e) {
      print('[ANALYTICS] Failed to log off_route_detected: $e');
    }
  }

  Future<void> logArrivedDestination({
    required String destinationName,
    required int durationSeconds,
    required double routeDistanceKm,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'arrived_destination',
        parameters: {
          'destination_name': destinationName,
          'duration_seconds': durationSeconds,
          'route_distance_km': routeDistanceKm,
        },
      );
    } catch (e) {
      print('[ANALYTICS] Failed to log arrived_destination: $e');
    }
  }

  Future<void> logScreenView({required String screenName}) async {
    try {
      await _analytics.logEvent(name: 'screen_view', parameters: {'screen_name': screenName});
    } catch (e) {
      print('[ANALYTICS] Failed to log screen_view: $e');
    }
  }

  Future<void> logFamilyAlert({required String familyId, required String uid, required String message}) async {
    try {
      await _analytics.logEvent(name: 'family_alert', parameters: {
        'family_id': familyId,
        'uid': uid,
        'message': message,
      });
    } catch (e) {
      print('[ANALYTICS] Failed to log family_alert: $e');
    }
  }
}
