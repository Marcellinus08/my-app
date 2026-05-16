# Fitur Navigasi - Sisi Pengguna

## Ringkasan
Dokumentasi ini menggambarkan alur teknis fitur navigasi untuk pengguna TunaNetra di aplikasi.

## Lokasi Implementasi Utama
- `lib/screens/tunanetra/navigation_screen.dart`
- `lib/services/places_service.dart`
- `lib/services/routing_service.dart`
- `lib/services/live_tracking_service.dart`
- `lib/services/navigation_history_service.dart`
- `lib/models/place_model.dart`
- `lib/models/navigation_instruction_model.dart`

## Tujuan Fitur
Fitur navigasi menyediakan:
- daftar tempat tujuan dari Firestore
- pemilihan lokasi tujuan oleh pengguna
- perhitungan rute jalan kaki
- panduan turn-by-turn
- pelacakan posisi GPS real-time
- deteksi keluar jalur dan perhitungan ulang rute
- pencatatan rute ke riwayat navigasi

## Alur Eksekusi
1. `NavigationScreen` dibuat dan `initState()` dijalankan.
2. Widget memanggil:
   - `_getUserLocation()` untuk memperoleh lokasi awal dari `Geolocator`
   - `_loadPlaces()` untuk memuat daftar tempat dari `PlacesService.getAllPlaces()`
3. Jika lokasi diizinkan dan layanan lokasi aktif, aplikasi menggunakan posisi GPS pertama sebagai `origin`.
4. Daftar tempat ditampilkan ke pengguna, termasuk nama, kategori, dan koordinat.
5. Pengguna memilih tempat tujuan (`_selectedPlace`) dan memulai navigasi.

## Permission & Lokasi
- `_getUserLocation()` memeriksa:
  - apakah layanan lokasi aktif: `Geolocator.isLocationServiceEnabled()`
  - status izin: `Geolocator.checkPermission()` / `Geolocator.requestPermission()`
- Jika izin `deniedForever`, pengguna mendapatkan pesan snackbar dan sistem tetap menggunakan lokasi default.
- Lokasi default diset ke Bandung: `LatLng(-6.9147, 107.6098)`.

## Penghitungan Rute
- `_loadRoute()` dipanggil setelah pengguna memilih tujuan.
- Rute menggunakan `RoutingService`:
  - `getRoute(origin: destination:)` mengkonsumsi OSRM public endpoint `router.project-osrm.org/route/v1/foot`
  - `getRouteInfo(...)` menghitung jarak dan durasi
  - `getNavigationInstructions(...)` memanggil OSRM dengan `steps=true` untuk mendekode instruksi turn-by-turn
- Hasil route berupa polyline `List<LatLng>` yang disimpan ke `_routePoints`.
- Informasi rute yang ditampilkan meliputi:
  - `_routeDistanceKm`
  - `_routeDurationMinutes`
  - `_navigationInstructions`

## Streaming Posisi & Sensor Fusion
- Setelah navigasi dimulai, metode `_startLocationStreaming()` dipanggil.
- Ini menyalakan:
  - `LiveTrackingService.startNavigationTracking(...)`
  - sensor fusion melalui akselerometer dan giroskop
- Posisi GPS masuk lewat callback `onPosition(position)`.
- Setiap update GPS memanggil `_onGpsPositionUpdate(position)`.

### Posisi dan Prediksi
- Posisi GPS ditransformasikan ke `LatLng updatedLocation`.
- Jika update GPS tertunda, sistem menerapkan prediksi gerak dengan `_applyPredictedMotionStep()`:
  - menggunakan heading sensor giroskop dan percepatan
  - prediksi maksimal 15 meter dalam interval 250ms
- Tampilan marker bergerak mulus melalui animasi Tween di `_animateUserLocation()`.

## Snap ke Rute dan Progres
- `_snapPositionToRoute(currentPosition)` mencari proyeksi posisi ke segmen rute terdekat.
- Threshold snap: 20 meter.
- Jika posisi melebar dari rute lebih dari 35 meter, fitur off-route aktif.
- `_updateRouteProgress(...)` memperbarui segmen rute yang sudah dilewati dan menyinkronkan polyline tersisa.

## Deteksi Keluar Jalur
- `_handleOffRouteDetection(...)` memantau jarak ke rute.
- Jika posisi tidak tersnap dan > 35 meter dari rute:
  - mengaktifkan waktu konfirmasi selama 2 detik
  - mencegah reroute berulang dalam cooldown 20 detik
- Setelah konfirmasi, sistem:
  - mencatat event `off_route`
  - menampilkan snackbar
  - memanggil `_loadRoute()` ulang

## Riwayat Navigasi
- `NavigationHistoryService` digunakan untuk:
  - `addRoutePoint(...)`
  - `updateRemainingRoutePolyline(...)`
  - `addTripEvent(...)`
- Titik rute disimpan secara berkala ketika jarak ke titik terakhir >= 5 meter atau waktu >= 5 detik.
- Saat navigasi berakhir, `_saveFinalRoutePointIfAvailable()` menyimpan titik terakhir.

## Status Navigasi di UI
- State utama:
  - `_isNavigating`
  - `_isLoadingRoute`
  - `_isOffRouteWarningVisible`
  - `_routeLoadError`
- Instruksi belok ditampilkan dari `_navigationInstructions` dan dicek melalui index `_currentInstructionIndex`.
- Mode posisi menunjukkan:
  - `GPS Live` jika posisi langsung
  - `Mode Prediksi` ketika GPS stale tetapi sensor fusion aktif

## Komponen Teknikal Utama
- `NavigationScreen` — halaman utama navigasi
- `RoutingService` — mengambil rute dan instruksi dari OSRM
- `PlacesService` — memuat tempat tujuan dari Firestore
- `LiveTrackingService` — streaming GPS real-time dan update status `live_tracking`
- `NavigationHistoryService` — menyimpan jalur navigasi ke backend
- `PlaceModel` — normalisasi data tempat
- `NavigationInstruction` — struktur instruksi turn-by-turn

## Error Handling
- Jika `PlacesService` gagal, layar berisi daftar kosong dengan fallback.
- Jika `RoutingService` gagal karena jaringan atau OSRM, error ditangani dan tampilkan pesan.
- Jika tidak ada akses lokasi, aplikasi tetap menampilkan peta default dan informasi yang relevan.

## Catatan Operasional
- Fitur menitikberatkan penggunaan OSRM public tanpa API key.
- Perhitungan jarak pejalan kaki menggunakan profile `foot`.
- Fitur ini mengoptimalkan penggunaan GPS untuk mengurangi konsumsi baterai dengan:
  - mode streaming hanya aktif saat navigasi
  - sensor fusion untuk prediksi saat GPS jarang tersentuh
