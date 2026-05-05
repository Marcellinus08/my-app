# 🔧 Dokumentasi Teknis - Sistem Navigasi Tuna Netra

**Untuk**: Developer & Technical Team  
**Versi**: 1.0  
**Last Updated**: Mei 2026

---

## 📋 Daftar Isi

1. [Arsitektur Sistem](#arsitektur-sistem)
2. [Komponen Utama](#komponen-utama)
3. [Services](#services)
4. [Data Models](#data-models)
5. [API Integration](#api-integration)
6. [Accessibility Implementation](#accessibility-implementation)
7. [Performance Metrics](#performance-metrics)
8. [Security Considerations](#security-considerations)

---

## 🏗️ Arsitektur Sistem

### Gambaran Umum

```
┌─────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                  │
│  (Flutter UI - Screens, Widgets, Navigation Stack)    │
└────────────────────┬────────────────────────────────────┘
                     │
┌─────────────────────┴────────────────────────────────────┐
│                    BUSINESS LOGIC LAYER                 │
│  (Services, Providers, State Management)               │
└────────────────────┬────────────────────────────────────┘
                     │
┌─────────────────────┴────────────────────────────────────┐
│                    DATA LAYER                           │
│  (Firebase Firestore, Local Storage, APIs)             │
└─────────────────────────────────────────────────────────┘
```

### Technology Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Flutter 3.x, Dart 3.x |
| **State Mgmt** | Provider (planned), Riverpod |
| **Backend** | Firebase (Auth, Firestore, Functions) |
| **Routing API** | OSRM (Open Street Routing Machine) |
| **Maps** | flutter_map, OpenStreetMap |
| **Positioning** | Geolocator, Sensors Plus |
| **Connectivity** | flutter_blue_plus (Bluetooth) |
| **Text-to-Speech** | flutter_tts |

---

## 🎯 Komponen Utama

### 1. Navigation Module

#### File Structure
```
lib/
├── screens/tunanetra/
│   ├── navigation_screen.dart          [Main Navigation UI]
│   ├── tunanetra_home_screen.dart      [Home/Dashboard]
│   ├── bluetooth_screen.dart           [BLE Connection]
│   └── ...
│
├── services/
│   ├── routing_service.dart            [Route Calculation]
│   ├── places_service.dart             [Places/Locations]
│   ├── analytics_service.dart          [Event Tracking]
│   └── ...
│
├── models/
│   ├── navigation_instruction_model.dart
│   ├── place_model.dart
│   └── ...
│
└── utils/
    ├── constants.dart                  [App Constants]
    └── ...
```

#### Key Classes

**NavigationScreen (`navigation_screen.dart`)**
```dart
class NavigationScreen extends StatefulWidget
  - State: _NavigationScreenState

State Variables:
  - MapController _mapController
  - LatLng _userLocation / _animatedUserLocation
  - List<LatLng> _routePoints
  - List<NavigationInstruction> _navigationInstructions
  - int _currentInstructionIndex
  - StreamSubscription<Position> _positionStreamSubscription
  - StreamSubscription<UserAccelerometerEvent> _userAccelerometerSubscription
  - bool _isNavigating
  - DateTime _navigationStartTime
  - Timer _durationUpdateTimer

Key Methods:
  - void initState()
  - Future<void> _selectDestination()
  - Future<void> _startNavigation(PlaceModel place)
  - Future<void> _calculateRoute()
  - Future<void> _getNavigationInstructions()
  - void _startLocationUpdates()
  - void _updateUserLocation(Position position)
  - void _checkOffRoute()
  - void _updateNavigationInstructions()
  - void _speakInstruction()
  - void _handleReroute()
```

---

### 2. Services Layer

#### RoutingService (`services/routing_service.dart`)

**Fungsi**: Menghitung rute menggunakan OSRM API

```dart
class RoutingService {
  static const String _baseUrlCar = 'https://router.project-osrm.org/route/v1/car'
  static const String _baseUrlFoot = 'https://router.project-osrm.org/route/v1/foot'
  
  // Get polyline route points dari origin ke destination
  Future<List<LatLng>> getRoute({
    required LatLng origin,
    required LatLng destination,
  })
  
  // Get route details (distance, duration, dll)
  Future<Map<String, dynamic>> getRouteInfo({
    required LatLng origin,
    required LatLng destination,
    String profile = 'foot',
  })
}
```

**API Endpoint Format**:
```
GET /route/v1/{profile}/{coordinates}?parameters

Profile: 'car' atau 'foot'
Coordinates: lon,lat;lon,lat (OSRM format)

Example:
https://router.project-osrm.org/route/v1/foot/107.6098,-6.9147;107.6200,-6.9250
  ?geometries=geojson
  &overview=full
  &steps=true
```

**Response Structure**:
```json
{
  "code": "Ok",
  "routes": [
    {
      "geometry": {
        "coordinates": [[lon, lat], ...],
        "type": "LineString"
      },
      "distance": 1234,        // meters
      "duration": 890,         // seconds
      "steps": [...]          // Turn-by-turn instructions
    }
  ]
}
```

**Error Handling**:
- Connection timeout: 30 seconds
- Receive timeout: 30 seconds
- Graceful fallback untuk network errors

#### PlacesService (`services/places_service.dart`)

**Fungsi**: Fetch lokasi/tempat dari Firestore

```dart
class PlacesService {
  // Get semua places dari Firestore
  Future<List<PlaceModel>> getAllPlaces()
  
  // Search places by name/category
  Future<List<PlaceModel>> searchPlaces(String query)
  
  // Get nearest places
  Future<List<PlaceModel>> getNearestPlaces({
    required LatLng userLocation,
    required String category,
    int limit = 10,
  })
  
  // Save favorite place
  Future<void> saveFavoritePlace(PlaceModel place)
}
```

#### AnalyticsService (`services/analytics_service.dart`)

**Fungsi**: Track user events untuk analytics

```dart
class AnalyticsService {
  // Navigation events
  void logNavigationStarted(String placeName, double distance)
  void logNavigationCompleted(String placeName, Duration duration)
  void logNavigationCancelled(String reason)
  void logOffRoute(double distanceOffRoute)
  void logRouteRecalculated()
  
  // Device events
  void logBluetoothConnected(String deviceName)
  void logBluetoothDisconnected()
  void logGPSStatusChanged(String status)
}
```

---

### 3. Data Models

#### NavigationInstruction Model

```dart
class NavigationInstruction {
  final int stepNumber;
  final String instruction;        // e.g., "Lurus 50 meter"
  final double distanceMeters;     // Jarak untuk langkah ini
  final double durationSeconds;    // Perkiraan durasi
  final String direction;          // "straight", "left", "right", "uturn"
  final LatLng location;           // Koordinat instruksi
  final double bearing;            // Arah (0-360 derajat)
  
  // Lokasi latitude/longitude
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
}
```

#### PlaceModel

```dart
class PlaceModel {
  final String id;
  final String name;
  final String category;           // "hospital", "mosque", "shop", etc
  final double latitude;
  final double longitude;
  final String address;
  final String phoneNumber;
  final String openingHours;
  final double rating;
  final List<String> tags;
  final DateTime createdAt;
}
```

---

## 📡 API Integration

### OSRM API Details

#### Endpoint: Routing

```
GET /route/v1/{profile}/{coordinates}
```

**Parameters**:
- `profile`: "car" atau "foot"
- `coordinates`: Format: lon,lat;lon,lat
- `geometries`: "geojson" atau "polyline"
- `overview`: "full" (default), "simplified", "false"
- `steps`: true/false (untuk turn-by-turn)
- `continue_straight`: true/false
- `waypoints`: comma-separated indices

**Example Request**:
```bash
curl "https://router.project-osrm.org/route/v1/foot/107.6098,-6.9147;107.6200,-6.9250?geometries=geojson&steps=true&overview=full"
```

**Response**:
```json
{
  "code": "Ok",
  "routes": [
    {
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [107.6098, -6.9147],
          [107.6110, -6.9155],
          ...
          [107.6200, -6.9250]
        ]
      },
      "distance": 1542,         // meters
      "duration": 1100,         // seconds
      "steps": [
        {
          "distance": 45.5,
          "duration": 32.5,
          "geometry": {...},
          "name": "Main Street",
          "ref": "A1",
          "intersections": [...],
          "maneuver": {
            "bearing_before": 0,
            "bearing_after": 90,
            "location": [107.6098, -6.9147],
            "type": "straight"
          }
        }
      ]
    }
  ],
  "waypoints": [...]
}
```

### Rate Limiting

OSRM Public tidak memiliki strict rate limit, namun ada best practices:
- Max 10 requests per second
- Implement exponential backoff untuk retries
- Cache results untuk rute yang sama

### Firebase Firestore Integration

#### Collections Structure

```
firestore/
├── users/
│   └── {userId}/
│       ├── name: string
│       ├── email: string
│       ├── phone: string
│       ├── photoURL: string
│       ├── type: "tunanetra" | "family"
│       ├── createdAt: timestamp
│       └── settings: {
│           ├── navigationMode: "normal" | "minimal"
│           ├── ttsSpeed: 0.8 - 2.0
│           └── ...
│       }
│
├── places/
│   └── {placeId}/
│       ├── name: string
│       ├── category: string
│       ├── location: geopoint
│       ├── address: string
│       ├── rating: number
│       └── ...
│
├── navigationHistory/
│   └── {userId}/
│       └── {historyId}/
│           ├── origin: geopoint
│           ├── destination: geopoint
│           ├── distance: number
│           ├── duration: number
│           ├── timestamp: timestamp
│           └── ...
│
└── emergencyContacts/
    └── {userId}/
        └── {contactId}/
            ├── name: string
            ├── phone: string
            ├── email: string
            └── relationship: string
```

---

## ♿ Accessibility Implementation

### TalkBack Integration

**Flutter Semantics untuk Accessibility**:

```dart
Semantics(
  enabled: true,
  label: 'Tombol Mulai Navigasi',
  button: true,
  enabled: true,
  onTap: () => _startNavigation(),
  child: ElevatedButton(
    onPressed: _startNavigation,
    child: Text('Mulai Navigasi'),
  ),
)
```

### Text-to-Speech Implementation

```dart
import 'package:flutter_tts/flutter_tts.dart';

final FlutterTts tts = FlutterTts();

// Initialize
await tts.setLanguage("id-ID");
await tts.setSpeechRate(1.0);  // 0.5 - 2.0
await tts.setPitch(1.0);       // 0.5 - 2.0
await tts.setVolume(0.8);      // 0.0 - 1.0

// Speak
await tts.speak("Lurus 50 meter, kemudian belok kanan");
```

### High Contrast & Font Scaling

```dart
// Responsive text sizing
double getScaledFontSize(BuildContext context) {
  final textScaleFactor = MediaQuery.of(context).textScaleFactor;
  return 16.0 * textScaleFactor;
}

// High contrast theme
ThemeData highContrastTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.black,
    primaryColor: Colors.white,
    textTheme: TextTheme(
      bodyLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
  );
}
```

---

## 📊 Performance Metrics

### GPS Location Updates

```
Update Frequency:     5 detik (default)
Accuracy Threshold:   5-10 meter
Timeout:             30 detik (stale)
Battery Impact:      ~15-20% per hour (intensive use)
```

### Route Calculation Performance

```
Average Time:        2-5 detik
Max Distance:        50 km
Polyline Points:     100-500 points (tergantung distance)
API Response Time:   < 3 detik (normally)
```

### Memory Usage

```
Map Rendering:       ~50-100 MB
Polyline Points:     ~1-2 MB
Location History:    ~5-10 MB (1000 records)
Total App Memory:    150-300 MB (normal use)
```

### Sensor Processing

```
Accelerometer:       50 Hz (default)
Gyroscope:          50 Hz (default)
Prediction Tick:    250 ms
Max Prediction:     18 meter
Prediction Duration: Until next GPS fix
```

---

## 🔐 Security Considerations

### Firebase Rules

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Users can only read/write their own data
    match /users/{userId} {
      allow read: if request.auth.uid == userId;
      allow write: if request.auth.uid == userId && 
                      request.resource.data.size() < 1MB;
    }
    
    // Places are readable by all, writable by admin
    match /places/{placeId} {
      allow read: if true;
      allow write: if request.auth.token.admin == true;
    }
    
    // Navigation history - readable/writable by owner only
    match /navigationHistory/{userId}/{docId=**} {
      allow read: if request.auth.uid == userId;
      allow write: if request.auth.uid == userId;
    }
    
    // Emergency contacts - readable/writable by owner only
    match /emergencyContacts/{userId}/{docId=**} {
      allow read: if request.auth.uid == userId;
      allow write: if request.auth.uid == userId;
    }
  }
}
```

### Data Privacy

- **Location Data**: Encrypted in transit & at rest
- **Personal Info**: Never logged or exposed
- **API Keys**: Stored in `firebase_options.dart` (never commit)
- **Session Data**: Cleared on logout

### SSL/TLS Certificate Pinning

```dart
// Implement certificate pinning untuk production
final httpClient = HttpClient();
httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
  // Validate certificate here
  return false;
};
```

---

## 🚀 Deployment Checklist

- [ ] API keys konfigurasi & tidak di-commit
- [ ] Firebase rules sudah di-review & di-deploy
- [ ] TTS engine tersedia di target device
- [ ] GPS permissions di-test
- [ ] Bluetooth pairing di-test
- [ ] Accessibility features di-verify
- [ ] Performance testing di-complete
- [ ] Crash analytics di-setup
- [ ] Privacy policy & ToS di-ready
- [ ] Release notes di-prepare

---

## 📚 Developer Resources

### Dokumentasi References
- [Flutter Official Docs](https://flutter.dev/docs)
- [Firebase Docs](https://firebase.google.com/docs)
- [OSRM API](https://project-osrm.org/docs/v5.5.1/api/overview)
- [OpenStreetMap Wiki](https://wiki.openstreetmap.org/)

### Testing

#### Unit Tests
```bash
flutter test test/services/routing_service_test.dart
```

#### Widget Tests
```bash
flutter test test/screens/navigation_screen_test.dart
```

#### Integration Tests
```bash
flutter test --verbose integration_test/navigation_test.dart
```

---

## 🔄 Maintenance & Updates

### Dependencies Update
```bash
flutter pub upgrade
flutter pub outdated
```

### Code Analysis
```bash
flutter analyze
dart fix --dry-run
dart fix --apply
```

### Building & Release
```bash
flutter build apk --release
flutter build appbundle --release
flutter build ios --release
```

---

*Dokumentasi teknis ini diperbarui sesuai development progress. Last updated: Mei 2026*
