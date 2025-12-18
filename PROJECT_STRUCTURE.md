# Struktur Project Smart Cane Assistant

## 📁 Struktur Folder

```
lib/
├── main.dart                 # Entry point aplikasi
├── utils/
│   └── constants.dart        # Constants, colors, routes, text styles
├── models/
│   ├── user_model.dart       # Model data user (tunanetra & keluarga)
│   └── location_model.dart   # Model data lokasi
├── services/
│   ├── tts_service.dart      # Text-to-Speech (voice feedback)
│   ├── stt_service.dart      # Speech-to-Text (voice commands)
│   └── bluetooth_service.dart # Bluetooth untuk koneksi tongkat pintar
├── screens/
│   ├── auth/
│   │   ├── splash_screen.dart         # Splash screen awal
│   │   ├── role_selection_screen.dart # Pilih role (Tunanetra/Keluarga)
│   │   ├── login_screen.dart          # Login screen
│   │   └── register_screen.dart       # Register screen (TODO)
│   ├── tunanetra/
│   │   ├── tunanetra_home.dart        # Home screen tunanetra (TODO)
│   │   ├── navigation_screen.dart     # OSM Maps navigation (TODO)
│   │   ├── bluetooth_screen.dart      # Koneksi tongkat (TODO)
│   │   └── settings_screen.dart       # Settings tunanetra (TODO)
│   └── family/
│       ├── family_home.dart           # Home screen keluarga (TODO)
│       ├── monitoring_screen.dart     # Monitor lokasi tunanetra (TODO)
│       └── settings_screen.dart       # Settings keluarga (TODO)
├── providers/                          # State management (TODO)
└── widgets/                            # Custom reusable widgets (TODO)

assets/
├── images/    # Gambar & logo
├── icons/     # Icon custom
└── sounds/    # Sound effects
```

## ✅ Yang Sudah Dibuat

### 1. **Setup Dependencies** (`pubspec.yaml`)
   - ✅ Bluetooth: `flutter_blue_plus`
   - ✅ Maps: `flutter_map` (OpenStreetMap)
   - ✅ Location: `geolocator`, `geocoding`
   - ✅ Voice: `speech_to_text`, `flutter_tts`
   - ✅ State Management: `provider`
   - ✅ Firebase: `firebase_core`, `firebase_auth`, `cloud_firestore`
   - ✅ HTTP: `dio`, `http`
   - ✅ Storage: `shared_preferences`

### 2. **Utils & Constants**
   - ✅ `constants.dart` - App colors, text styles, routes, enums

### 3. **Models**
   - ✅ `user_model.dart` - Model untuk user (tunanetra & keluarga)
   - ✅ `location_model.dart` - Model untuk data lokasi

### 4. **Services**
   - ✅ `tts_service.dart` - Text-to-Speech untuk feedback audio
   - ✅ `stt_service.dart` - Speech-to-Text untuk voice commands
   - ✅ `bluetooth_service.dart` - Bluetooth connection management

### 5. **Screens - Auth**
   - ✅ `splash_screen.dart` - Splash screen dengan animasi
   - ✅ `role_selection_screen.dart` - Pilih role (Tunanetra/Keluarga)
   - ✅ `login_screen.dart` - Login dengan TTS support

### 6. **Main App**
   - ✅ Routing setup
   - ✅ Theme dengan aksesibilitas tinggi (font besar, high contrast)
   - ✅ Provider setup

## 📝 TODO - Screens yang Perlu Dibuat

### Tunanetra Screens:
- [ ] `tunanetra_home.dart` - Dashboard dengan:
  - Status koneksi Bluetooth
  - Tombol navigasi
  - Voice assistant button
  - Emergency button
  
- [ ] `navigation_screen.dart` - OSM Maps dengan:
  - Current location
  - Route planning
  - Voice navigation
  - Obstacle detection dari tongkat
  
- [ ] `bluetooth_screen.dart` - Bluetooth management:
  - Scan devices
  - Connect/disconnect tongkat
  - Device status
  
- [ ] `settings_screen.dart` - Settings:
  - Voice speed
  - Language
  - Notifications
  - Emergency contacts

### Family Screens:
- [ ] `family_home.dart` - Dashboard keluarga:
  - List tunanetra yang dimonitor
  - Real-time status
  - Last location
  
- [ ] `monitoring_screen.dart` - Real-time monitoring:
  - Live location on map
  - Movement history
  - Safety alerts
  
- [ ] `settings_screen.dart` - Settings keluarga

### Auth:
- [ ] `register_screen.dart` - Registrasi user baru

## 🔧 Services yang Perlu Ditambahkan

- [ ] `location_service.dart` - GPS tracking & geocoding
- [ ] `firebase_service.dart` - Firebase auth & Firestore operations
- [ ] `navigation_service.dart` - Route planning dengan OSM
- [ ] `ai_assistant_service.dart` - Voice command processing
- [ ] `notification_service.dart` - Push notifications

## 🎨 Fitur Aksesibilitas

✅ **Sudah Diimplementasi:**
- High contrast colors (hitam-putih)
- Text size besar (20-32px)
- TTS feedback untuk semua actions
- Semantic labels untuk screen readers
- Touch targets besar (70x70px minimum)

## 🚀 Cara Running

1. Install dependencies:
   ```bash
   flutter pub get
   ```

2. Run aplikasi:
   ```bash
   flutter run
   ```

3. Pilih device (Chrome untuk testing)

## 📱 Platform Support

- ✅ Android (primary target)
- ✅ iOS
- ✅ Web (untuk testing)
- ⚠️ Windows/Linux (limited bluetooth support)

## 🎯 Next Steps

1. Implementasi register screen
2. Setup Firebase (Auth & Firestore)
3. Buat tunanetra home screen
4. Implementasi OSM maps
5. Test bluetooth connection
6. Buat family monitoring screen
7. Implementasi AI voice assistant

## 🔐 Permissions Required

### Android (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

## 📚 Resources

- Flutter Map: https://docs.fleaflet.dev/
- Flutter Blue Plus: https://pub.dev/packages/flutter_blue_plus
- OSM Nominatim: https://nominatim.openstreetmap.org/
- Firebase Setup: https://firebase.google.com/docs/flutter/setup
