# Panduan Setup Database Tempat (Places)

## Deskripsi
Dokumentasi ini menjelaskan cara setup dan menggunakan database untuk menyimpan tempat-tempat yang dapat dinavigasi oleh user.

## Struktur Firestore Collection

### Collection: `places`
Menyimpan data semua tempat yang dapat dinavigasi.

### Document Structure:
```json
{
  "name": "String (required)",
  "latitude": "Number (required)",
  "longitude": "Number (required)",
  "description": "String (required)",
  "category": "String (required) - mall, mosque, hospital, restaurant, etc.",
  "address": "String (required)"
}
```

## Langkah Setup di Firebase Console

### 1. Buat Collection
1. Buka [Firebase Console](https://console.firebase.google.com/)
2. Pilih project Anda
3. Go to Firestore Database
4. Click "+ Start Collection"
5. Collection ID: `places`
6. Click "Next"

### 2. Tambahkan Sample Data
Klik "Add document" dan gunakan salah satu contoh di bawah:

#### Sample Place 1: Mall Kelapa Gading
```
Collection: places
Document ID: (auto)

Field Data:
- name (String): "Mall Kelapa Gading"
- latitude (Number): -6.1628
- longitude (Number): 106.8905
- description (String): "Shopping mall terbesar di Jakarta"
- category (String): "mall"
- address (String): "Jl. Kelapa Gading Blok A No. 1, Jakarta Utara"
```

#### Sample Place 2: Masjid Istiqlal
```
Collection: places
Document ID: (auto)

Field Data:
- name (String): "Masjid Istiqlal"
- latitude (Number): -6.1751
- longitude (Number): 106.8274
- description (String): "Masjid terbesar di Indonesia"
- category (String): "mosque"
- address (String): "Jl. Taman Wijaya Kusuma No. 1, Jakarta"
```

#### Sample Place 3: RS Cipto Mangunkusumo
```
Collection: places
Document ID: (auto)

Field Data:
- name (String): "RS Cipto Mangunkusumo"
- latitude (Number): -6.1853
- longitude (Number): 106.8273
- description (String): "Rumah sakit umum terbaik di Jakarta"
- category (String): "hospital"
- address (String): "Jl. Diponegoro No. 71, Jakarta Pusat"
```

#### Sample Place 4: Restoran Ayam Bakar Pak Karim
```
Collection: places
Document ID: (auto)

Field Data:
- name (String): "Restoran Ayam Bakar Pak Karim"
- latitude (Number): -6.1956
- longitude (Number): 106.8294
- description (String): "Restoran ayam bakar favorit di Jakarta"
- category (String): "restaurant"
- address (String): "Jl. Menteng No. 12, Jakarta Pusat"
```

#### Sample Place 5: Toko Buku Gramedia Thamrin City
```
Collection: places
Document ID: (auto)

Field Data:
- name (String): "Gramedia Thamrin City"
- latitude (Number): -6.1871
- longitude (Number): 106.8212
- description (String): "Toko buku terlengkap di Jakarta"
- category (String): "bookstore"
- address (String): "Thamrin City, Jl. M.H. Thamrin, Jakarta Pusat"
```

## Firestore Security Rules

Tambahkan rules ini di Firestore Security Rules untuk allow read dari public:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read places collection untuk semua user
    match /places/{document=**} {
      allow read;
      allow write: if request.auth != null; // Only authenticated users can write
    }
    
    // Other existing rules...
  }
}
```

## File yang Dibuat

### 1. `lib/models/place_model.dart`
Model untuk Place dengan fungsi:
- Convert dari/ke Firestore format
- Calculate distance dari current position
- Helper functions

### 2. `lib/services/places_service.dart`
Service untuk interact dengan Firestore:
- `getAllPlaces()` - Get semua places
- `getPlacesByCategory(category)` - Get places by category
- `getPlaceById(id)` - Get specific place
- `searchPlacesByName(query)` - Search places
- `getTopRatedPlaces(limit)` - Get top rated places
- `addPlace(place)` - Add new place
- `updatePlace(id, updates)` - Update place
- `deletePlace(id)` - Delete place
- `getAvailableCategories()` - Get list of categories

## Menggunakan di Navigation Screen

Setelah setup, integrate ke navigation_screen.dart:

```dart
import '../../models/place_model.dart';
import '../../services/places_service.dart';

class _NavigationScreenState extends State<NavigationScreen> {
  final PlacesService _placesService = PlacesService();
  List<PlaceModel> _places = [];
  bool _isLoadingPlaces = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _userLocation = defaultLocation;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getUserLocation();
      _loadPlaces(); // Add this
    });
  }

  Future<void> _loadPlaces() async {
    try {
      final places = await _placesService.getAllPlaces();
      setState(() {
        _places = places;
        _isLoadingPlaces = false;
      });
    } catch (e) {
      print('Error loading places: $e');
      setState(() => _isLoadingPlaces = false);
    }
  }

  // Update MarkerLayer untuk gunakan _places daripada _locations
  MarkerLayer(
    markers: [
      // User location marker
      Marker(
        point: _userLocation,
        // ... existing marker code
      ),
      // Places markers dari Firestore
      ..._places
          .map((place) => Marker(
            point: LatLng(place.latitude, place.longitude),
            width: 80,
            height: 80,
            child: GestureDetector(
              onTap: () {
                _goToLocation(LatLng(place.latitude, place.longitude));
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      place.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(height: 2),
                  Icon(
                    Icons.location_on_rounded,
                    color: Colors.blue,
                    size: 30,
                  ),
                ],
              ),
            ),
          ))
          .toList(),
    ],
  )
}
```

## Categories yang Disarankan

Gunakan salah satu dari categories berikut untuk consistency:
- `mall` - Shopping mall
- `mosque` - Masjid
- `hospital` - Rumah sakit/Klinik
- `restaurant` - Restoran/Cafe
- `bookstore` - Toko buku
- `school` - Sekolah/Universitas
- `park` - Taman/Tempat umum
- `bank` - Bank/ATM
- `pharmacy` - Apotek
- `police` - Kantor polisi
- `market` - Pasar
- `gas_station` - SPBU

## Testing

Setelah setup:
1. Buka app dan navigation screen
2. Lihat apakah semua places dari Firestore muncul di map
3. Tap pada marker place untuk test navigation
4. Verify distance calculation bekerja dengan benar

## Langkah Berikutnya

Setelah setup berhasil, kita bisa buat fitur:
1. Search places
2. Filter by category
3. Show place details
4. Calculate route ke tempat tujuan
5. Turn-by-turn navigation
