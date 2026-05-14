import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Model untuk tempat/destinasi yang bisa dinavigasi
class PlaceModel {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String description;
  final String category;
  final String address;
  final String visibility;

  PlaceModel({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.category,
    required this.address,
    this.visibility = 'public',
  });

  /// Convert Firestore document to PlaceModel
  factory PlaceModel.fromFirestore(Map<String, dynamic> data, String docId) {
    final location = data['location'];
    final latValue = data['lat'];
    final lngValue = data['lng'];

    double latitude;
    double longitude;
    if (location is GeoPoint) {
      latitude = location.latitude;
      longitude = location.longitude;
    } else if (latValue is num && lngValue is num) {
      latitude = latValue.toDouble();
      longitude = lngValue.toDouble();
    } else {
      throw FormatException('Koordinat tempat tidak valid: $docId');
    }

    return PlaceModel(
      id: docId,
      name: data['name'] ?? 'Unknown Place',
      latitude: latitude,
      longitude: longitude,
      description: data['description'] ?? data['address'] ?? '',
      category: data['category'] ?? 'other',
      address: data['address'] ?? '',
      visibility: data['visibility']?.toString() ?? 'public',
    );
  }

  /// Convert PlaceModel to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'location': GeoPoint(latitude, longitude),
      'description': description,
      'category': category,
      'address': address,
      'visibility': visibility,
    };
  }

  bool get isPrivate => visibility == 'private';

  /// Calculate distance from current position (in kilometers)
  double getDistanceFromPosition(double userLat, double userLng) {
    const double earthRadius = 6371; // Radius of the earth in km
    final double dLat = _degreesToRadians(latitude - userLat);
    final double dLng = _degreesToRadians(longitude - userLng);
    final double a =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        (math.cos(_degreesToRadians(userLat)) *
            math.cos(_degreesToRadians(latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2));
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double distance = earthRadius * c;
    return distance;
  }

  /// Helper function to convert degrees to radians
  static double _degreesToRadians(double degrees) {
    return degrees * (3.141592653589793 / 180);
  }

  @override
  String toString() {
    return 'PlaceModel(id: $id, name: $name, lat: $latitude, lng: $longitude, category: $category)';
  }
}

// Helper for Math functions
class Math {
  static double sin(double x) => math.sin(x);
  static double cos(double x) => math.cos(x);
  static double sqrt(double x) => math.sqrt(x);
  static double atan2(double y, double x) => math.atan2(y, x);
}
