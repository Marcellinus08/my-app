import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

class FamilyPlaceService {
  FamilyPlaceService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<String?> getPairedUserUid() async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('[FamilyPlaceService] user belum login');
      return null;
    }

    final doc = await _firestore.collection('users').doc(user.uid).get();
    final data = doc.data();
    final userType = data?['userType']?.toString();
    if (userType != 'family' && userType != 'UserType.family') {
      debugPrint('[FamilyPlaceService] current user bukan family: $userType');
      return null;
    }

    final pairedUserUid = data?['pairedUserUid']?.toString().trim();
    if (pairedUserUid == null || pairedUserUid.isEmpty) {
      debugPrint('[FamilyPlaceService] pairedUserUid belum ada');
      return null;
    }

    debugPrint('[FamilyPlaceService] pairedUserUid ditemukan: $pairedUserUid');
    return pairedUserUid;
  }

  LatLng? parseLatLngFromGoogleMapsLink(String link) {
    final text = Uri.decodeFull(link.trim());
    if (text.isEmpty) return null;

    final patterns = <RegExp>[
      RegExp(
        r'(?:[?&](?:q|query)=)(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)',
        caseSensitive: false,
      ),
      RegExp(
        r'@(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)',
        caseSensitive: false,
      ),
      RegExp(r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final lat = double.tryParse(match.group(1) ?? '');
      final lng = double.tryParse(match.group(2) ?? '');
      if (lat == null || lng == null) continue;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;

      debugPrint('[FamilyPlaceService] koordinat berhasil diparse: $lat,$lng');
      return LatLng(lat, lng);
    }

    return null;
  }

  Future<void> addPrivatePlace({
    required String name,
    required String address,
    required String gmapLink,
    required String category,
    required String ownerUid,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User belum login');
    }

    final coordinates = parseLatLngFromGoogleMapsLink(gmapLink);
    if (coordinates == null) {
      throw Exception(
        'Koordinat tidak ditemukan dari link Google Maps. Pastikan link berisi koordinat lokasi.',
      );
    }

    try {
      await _firestore.collection('places').add({
        'name': name.trim(),
        'address': address.trim(),
        'gmapLink': gmapLink.trim(),
        'lat': coordinates.latitude,
        'lng': coordinates.longitude,
        'category': category.trim().isEmpty ? 'Lainnya' : category.trim(),
        'visibility': 'private',
        'ownerUid': ownerUid,
        'createdBy': user.uid,
        'createdByRole': 'family',
        'source': 'google_maps_link',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[FamilyPlaceService] tempat berhasil disimpan');
    } catch (e) {
      debugPrint('[FamilyPlaceService] tempat gagal disimpan: $e');
      rethrow;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getMyCreatedPlacesStream(
    String ownerUid,
  ) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }

    return _firestore
        .collection('places')
        .where('visibility', isEqualTo: 'private')
        .where('ownerUid', isEqualTo: ownerUid)
        .where('createdBy', isEqualTo: user.uid)
        .snapshots();
  }

  Future<void> deletePlace(String placeId) async {
    await _firestore.collection('places').doc(placeId).delete();
    debugPrint('[FamilyPlaceService] tempat berhasil dihapus');
  }
}
