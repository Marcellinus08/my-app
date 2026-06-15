import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/place_model.dart';

/// Service untuk mengelola data tempat/destinasi dari Firestore
class PlacesService {
  static final PlacesService _instance = PlacesService._internal();

  factory PlacesService() {
    return _instance;
  }

  PlacesService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final String _collectionName = 'places';

  /// Get public admin places and private places owned by current tuna netra user.
  Future<List<PlaceModel>> getAllPlaces() async {
    try {
      final currentUid = _auth.currentUser?.uid;
      final places = <PlaceModel>[];
      final seenIds = <String>{};
      final publicSnapshot = await _db
          .collection(_collectionName)
          .where('visibility', isEqualTo: 'public')
          .get();

      _addPlacesFromSnapshot(publicSnapshot, places, seenIds);

      try {
        final legacyPublicSnapshot = await _db
            .collection(_collectionName)
            .where('visibility', isNull: true)
            .get();
        _addPlacesFromSnapshot(legacyPublicSnapshot, places, seenIds);
      } catch (_) {}

      if (places.isEmpty) {
        try {
          final allSnapshot = await _db.collection(_collectionName).get();
          _addPlacesFromSnapshot(
            allSnapshot,
            places,
            seenIds,
            currentUid: currentUid,
          );
        } catch (_) {}
      }

      if (currentUid != null) {
        final privateSnapshot = await _db
            .collection(_collectionName)
            .where('visibility', isEqualTo: 'private')
            .where('ownerUid', isEqualTo: currentUid)
            .get();

        _addPlacesFromSnapshot(privateSnapshot, places, seenIds);
      }

      places.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      return places;
    } catch (e) {
      rethrow;
    }
  }

  void _addPlacesFromSnapshot(
    QuerySnapshot snapshot,
    List<PlaceModel> places,
    Set<String> seenIds, {
    String? currentUid,
  }) {
    for (final doc in snapshot.docs) {
      if (!seenIds.add(doc.id)) continue;

      final data = doc.data() as Map<String, dynamic>;
      if (currentUid != null) {
        final visibility = data['visibility']?.toString();
        final ownerUid = data['ownerUid']?.toString();
        final isPublicPlace = visibility == null || visibility == 'public';
        final isMyPrivatePlace =
            visibility == 'private' && ownerUid == currentUid;

        if (!isPublicPlace && !isMyPrivatePlace) continue;
      }

      try {
        places.add(PlaceModel.fromFirestore(data, doc.id));
      } catch (_) {}
    }
  }

  /// Get places by category
  Future<List<PlaceModel>> getPlacesByCategory(String category) async {
    try {
      final QuerySnapshot snapshot = await _db
          .collection(_collectionName)
          .where('category', isEqualTo: category)
          .get();

      return snapshot.docs
          .map(
            (doc) => PlaceModel.fromFirestore(
              doc.data() as Map<String, dynamic>,
              doc.id,
            ),
          )
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Get place by ID
  Future<PlaceModel?> getPlaceById(String placeId) async {
    try {
      final DocumentSnapshot doc = await _db
          .collection(_collectionName)
          .doc(placeId)
          .get();

      if (!doc.exists) {
        return null;
      }

      return PlaceModel.fromFirestore(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Search places by name
  Future<List<PlaceModel>> searchPlacesByName(String query) async {
    try {
      final QuerySnapshot snapshot = await _db
          .collection(_collectionName)
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThan: query + 'z')
          .get();

      return snapshot.docs
          .map(
            (doc) => PlaceModel.fromFirestore(
              doc.data() as Map<String, dynamic>,
              doc.id,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get top rated places
  Future<List<PlaceModel>> getTopRatedPlaces({int limit = 10}) async {
    try {
      final QuerySnapshot snapshot = await _db
          .collection(_collectionName)
          .orderBy('rating', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map(
            (doc) => PlaceModel.fromFirestore(
              doc.data() as Map<String, dynamic>,
              doc.id,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Add new place (for admin/development)
  Future<String> addPlace(PlaceModel place) async {
    try {
      final docRef = await _db
          .collection(_collectionName)
          .add(place.toFirestore());

      return docRef.id;
    } catch (e) {
      rethrow;
    }
  }

  /// Update place
  Future<void> updatePlace(String placeId, Map<String, dynamic> updates) async {
    try {
      await _db.collection(_collectionName).doc(placeId).update(updates);
    } catch (e) {
      rethrow;
    }
  }

  /// Delete place
  Future<void> deletePlace(String placeId) async {
    try {
      await _db.collection(_collectionName).doc(placeId).delete();
    } catch (e) {
      rethrow;
    }
  }

  /// Get categories available
  Future<List<String>> getAvailableCategories() async {
    try {
      final QuerySnapshot snapshot = await _db
          .collection(_collectionName)
          .get();

      final categories = <String>{};
      for (var doc in snapshot.docs) {
        final category = doc['category'] as String?;
        if (category != null) {
          categories.add(category);
        }
      }

      return categories.toList();
    } catch (_) {
      return [];
    }
  }
}
