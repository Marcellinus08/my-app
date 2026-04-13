import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/place_model.dart';

/// Service untuk mengelola data tempat/destinasi dari Firestore
class PlacesService {
  static final PlacesService _instance = PlacesService._internal();

  factory PlacesService() {
    return _instance;
  }

  PlacesService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _collectionName = 'places';

  /// Get all places
  Future<List<PlaceModel>> getAllPlaces() async {
    try {
      print('[PLACES] Fetching all places...');
      final QuerySnapshot snapshot = await _db.collection(_collectionName).get();

      if (snapshot.docs.isEmpty) {
        print('[PLACES] No places found in database');
        return [];
      }

      final places = snapshot.docs
          .map((doc) => PlaceModel.fromFirestore(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();

      print('[PLACES] ✅ Fetched ${places.length} places');
      return places;
    } catch (e) {
      print('[PLACES] ❌ Error fetching all places: $e');
      rethrow;
    }
  }

  /// Get places by category
  Future<List<PlaceModel>> getPlacesByCategory(String category) async {
    try {
      print('[PLACES] Fetching places in category: $category');
      final QuerySnapshot snapshot = await _db
          .collection(_collectionName)
          .where('category', isEqualTo: category)
          .get();

      final places = snapshot.docs
          .map((doc) => PlaceModel.fromFirestore(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();

      print('[PLACES] ✅ Found ${places.length} places in category: $category');
      return places;
    } catch (e) {
      print('[PLACES] ❌ Error fetching places by category: $e');
      rethrow;
    }
  }

  /// Get place by ID
  Future<PlaceModel?> getPlaceById(String placeId) async {
    try {
      print('[PLACES] Fetching place by ID: $placeId');
      final DocumentSnapshot doc =
          await _db.collection(_collectionName).doc(placeId).get();

      if (!doc.exists) {
        print('[PLACES] ⚠️ Place not found: $placeId');
        return null;
      }

      final place = PlaceModel.fromFirestore(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );

      print('[PLACES] ✅ Found place: ${place.name}');
      return place;
    } catch (e) {
      print('[PLACES] ❌ Error fetching place by ID: $e');
      rethrow;
    }
  }

  /// Search places by name
  Future<List<PlaceModel>> searchPlacesByName(String query) async {
    try {
      print('[PLACES] Searching places with query: $query');
      final QuerySnapshot snapshot = await _db
          .collection(_collectionName)
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThan: query + 'z')
          .get();

      final places = snapshot.docs
          .map((doc) => PlaceModel.fromFirestore(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();

      print('[PLACES] ✅ Found ${places.length} results for: $query');
      return places;
    } catch (e) {
      print('[PLACES] ❌ Error searching places: $e');
      return [];
    }
  }

  /// Get top rated places
  Future<List<PlaceModel>> getTopRatedPlaces({int limit = 10}) async {
    try {
      print('[PLACES] Fetching top rated places (limit: $limit)...');
      final QuerySnapshot snapshot = await _db
          .collection(_collectionName)
          .orderBy('rating', descending: true)
          .limit(limit)
          .get();

      final places = snapshot.docs
          .map((doc) => PlaceModel.fromFirestore(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();

      print('[PLACES] ✅ Found ${places.length} top rated places');
      return places;
    } catch (e) {
      print('[PLACES] ❌ Error fetching top rated places: $e');
      return [];
    }
  }

  /// Add new place (for admin/development)
  Future<String> addPlace(PlaceModel place) async {
    try {
      print('[PLACES] Adding new place: ${place.name}');
      final docRef = await _db
          .collection(_collectionName)
          .add(place.toFirestore());

      print('[PLACES] ✅ Place added with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('[PLACES] ❌ Error adding place: $e');
      rethrow;
    }
  }

  /// Update place
  Future<void> updatePlace(String placeId, Map<String, dynamic> updates) async {
    try {
      print('[PLACES] Updating place: $placeId');
      await _db.collection(_collectionName).doc(placeId).update(updates);

      print('[PLACES] ✅ Place updated: $placeId');
    } catch (e) {
      print('[PLACES] ❌ Error updating place: $e');
      rethrow;
    }
  }

  /// Delete place
  Future<void> deletePlace(String placeId) async {
    try {
      print('[PLACES] Deleting place: $placeId');
      await _db.collection(_collectionName).doc(placeId).delete();

      print('[PLACES] ✅ Place deleted: $placeId');
    } catch (e) {
      print('[PLACES] ❌ Error deleting place: $e');
      rethrow;
    }
  }

  /// Get categories available
  Future<List<String>> getAvailableCategories() async {
    try {
      print('[PLACES] Fetching available categories...');
      final QuerySnapshot snapshot =
          await _db.collection(_collectionName).get();

      final categories = <String>{};
      for (var doc in snapshot.docs) {
        final category = doc['category'] as String?;
        if (category != null) {
          categories.add(category);
        }
      }

      print('[PLACES] ✅ Found ${categories.length} categories');
      return categories.toList();
    } catch (e) {
      print('[PLACES] ❌ Error fetching categories: $e');
      return [];
    }
  }
}
