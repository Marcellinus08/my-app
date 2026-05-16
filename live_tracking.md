# Fitur Live Tracking - Sisi Keluarga

## Ringkasan
Dokumentasi ini menjelaskan alur teknis fitur live tracking untuk anggota keluarga yang memantau pengguna TunaNetra.

## Lokasi Implementasi Utama
- `lib/screens/family/family_home_screen.dart`
- `lib/screens/family/live_tracking_screen.dart`
- `lib/services/live_tracking_service.dart`
- `lib/services/user_service.dart`
- `lib/services/auth_service.dart`
- `lib/services/notification_service.dart`
- `lib/utils/constants.dart`

## Tujuan Fitur
Fitur live tracking keluarga bertujuan untuk:
- memantau status online/offline TunaNetra user
- menampilkan lokasi GPS terakhir dan baterai
- memperlihatkan waktu pembaruan terakhir
- menunjukan status jika data sudah stale
- menerima notifikasi SOS darurat

## Alur Data & Subscribe
1. `FamilyHomeScreen.initState()`
   - memanggil `NotificationService.instance.initializeForFamilyUser()`
   - memanggil `_loadMonitoredUsers()`
   - memulai timer `_liveTrackingFreshnessTimer`
   - memanggil `_subscribeToFamilyConnectionChanges()` dan `_subscribeToPairingRequestUpdates()`
   - menyiapkan listener aktif SOS dengan `_subscribeToActiveSos()`
2. `_loadMonitoredUsers()`
   - mengambil daftar TunaNetra user yang terkait dengan `familyId`
   - memanggil `UserService().getTunaNetraUsersByFamilyId(resolvedFamilyId)`
   - untuk setiap UID, memulai:
     - `_subscribeToUserLocation(uid)`
     - `_subscribeToUserProfile(uid)`
     - `_subscribeToLiveTracking(uid)`
3. `_subscribeToLiveTracking(uid)`
   - menambahkan listener pada dokumen Firestore: `collection('live_tracking').doc(uid)`
   - setiap perubahan dokumen membarui `_liveTrackingData[uid]`

## Struktur Dokumen Firestore `live_tracking`
Field yang dipantau oleh fitur keluarga:
- `lat` / `lng` : koordinat GPS
- `connectionStatus` : `online` atau `offline`
- `gpsStatus` : mis. `gps_live`
- `batteryLevel` : persentase baterai
- `updatedAt` : `Timestamp` server
- `destinationName` : nama tujuan jika sedang navigasi
- `isNavigating` : true/false
- `currentTripId` : ID rute jika sedang bernavigasi
- `isPredicted` : apakah posisi dihasilkan oleh prediksi
- `userId` : UID pengguna

## Logika Status Online
Metode `_isUserOnline(String uid)` menentukan apakah status pengguna aktif:
- `connectionStatus == 'online'`
- `lat != null && lng != null`
- `updatedAt` valid dan cukup segar
- panggil `_isLiveTrackingFresh(updatedAt)`

### Ketentuan Freshness
- `_isLiveTrackingFresh(Timestamp? updatedAt)` menganggap data segar jika:
  - `updatedAt` tidak null
  - `DateTime.now().difference(updatedAt.toDate()).inSeconds <= 30`
- Jika lebih lama dari 30 detik, data dianggap stale dan pengguna ditampilkan sebagai offline.

## Tampilan UI
- Kartu user menampilkan:
  - nama user TunaNetra
  - status online/offline
  - koordinat `lat,lng` dengan 6 desimal jika aktif
  - level baterai jika online
  - waktu pembaruan terakhir
- Timer `_liveTrackingFreshnessTimer` berjalan setiap detik untuk membuat UI memperbarui label status ketika `updatedAt` melewati batas freshness.

## Otomatisasi Subscription
- `_subscribeToUserLocation(uid)` memantau service `FamilyLocationService.listenToRealtime(uid, storeHistory: true)` untuk lokasi terakhir tetap diperbarui.
- `_subscribeToUserProfile(uid)` memantau `users/{uid}` untuk memperbarui nama, email, dan nomor telepon secara real-time.
- `_subscribeToLiveTracking(uid)` mendengarkan dokumen `live_tracking/{uid}`.

## Notifikasi SOS
- `_subscribeToActiveSos()` memantau koleksi `sos_alerts` untuk dokumen status `active` yang berisi `familyUids`.
- Ketika ada alert baru, `_notifyActiveSos(...)`:
  - memanggil `NotificationService.instance.showSosFullScreenNotification(data)`
  - menampilkan snackbar lokal

## Detail Layanan Live Tracking
`LiveTrackingService` menangani penulisan data live tracking dari sisi TunaNetra user:
- `startHomeLocationTracking()` — update posisi lat/lng secara periodik dan menyimpan ke Firestore
- `startNavigationTracking(...)` — aktifkan streaming GPS berpresisi tinggi saat navigasi
- `stopNavigationTracking()` — menghentikan mode navigasi dan kembali ke home tracking
- `updateLiveTracking(...)` — menuliskan status posisi ke dokumen `live_tracking/{user.uid}`
- `updateHomeLocationOnly(...)` — update posisi saat tidak bernavigasi
- `updateInactiveTracking()` — set `connectionStatus = offline` ketika tracking tidak tersedia

## Kriteria Online vs Offline
- Online ketika data `live_tracking`:
  - masih segar (<= 30 detik)
  - berstatus `connectionStatus == 'online'`
  - memiliki `lat` dan `lng`
- Offline jika:
  - `connectionStatus == 'offline'`
  - `lat` atau `lng` null
  - `updatedAt` lebih dari 30 detik lalu

## Komponen Teknikal Utama
- `FamilyHomeScreen` — halaman utama pemantauan keluarga
- `LiveTrackingService` — writer dan controller state live tracking untuk TunaNetra user
- `UserService` — pencarian user TunaNetra berdasarkan familyId
- `NotificationService` — notifikasi SOS dan alert untuk anggota keluarga
- Firestore `live_tracking` — sumber kebenaran real-time untuk status lokasi

## Catatan Operasional
- Batas waktu `30 detik` adalah parameter penting untuk menentukan kapan data dianggap kadaluarsa.
- Pendekatan ini memprioritaskan:
  - keakuratan status real-time
  - mencegah informasi lokasi tua dianggap valid
- Bila keluarga melihat status offline tetapi pengguna berdekatan, periksa koneksi jaringan dan update dokumentasi `live_tracking`.
