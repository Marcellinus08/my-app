# Dokumentasi Sistem Aplikasi Teman Arah

## 1. Ringkasan Sistem

Teman Arah adalah aplikasi Flutter untuk membantu pengguna tunanetra melakukan navigasi, memantau koneksi perangkat pendukung, dan meminta bantuan darurat kepada keluarga. Aplikasi juga menyediakan sisi keluarga untuk memantau lokasi, riwayat perjalanan, status darurat, dan daftar tempat tujuan.

Sistem terdiri dari:

- Aplikasi Flutter multi-platform di folder `lib/`.
- Firebase Authentication, Cloud Firestore, Realtime Database, Firebase Messaging, dan Firebase Analytics.
- Firebase Cloud Functions untuk pengiriman email OTP pada flow lama/alternatif.
- Cloudflare Worker untuk pengiriman notifikasi SOS melalui FCM HTTP v1.
- Integrasi API eksternal untuk peta, rute, geocoding, dan cuaca.

Nama aplikasi: `Teman Arah`  
Versi aplikasi: `1.0.0`  
Package Flutter: `teman_arah`

## 2. Tujuan Aplikasi

Tujuan utama aplikasi adalah:

- Membantu pengguna tunanetra memilih tujuan dan mengikuti rute jalan kaki.
- Memberikan panduan navigasi berbasis peta, GPS, instruksi belok, TTS, dan sensor perangkat.
- Mengirim data lokasi secara real-time agar keluarga dapat memantau kondisi pengguna.
- Menyediakan tombol SOS untuk kondisi darurat.
- Menghubungkan akun tunanetra dengan akun keluarga melalui kode atau permintaan pairing.
- Menyimpan riwayat navigasi dan event penting untuk evaluasi keluarga.

## 3. Peran Pengguna

### 3.1 Pengguna Tunanetra

Fitur utama:

- Registrasi menggunakan email, password, dan link verifikasi sekali pakai dari Firebase.
- Login menggunakan email dan password, dengan pengecekan status verifikasi email.
- Halaman beranda dengan informasi cuaca dan menu utama.
- Navigasi ke tempat tujuan.
- Live tracking lokasi untuk keluarga.
- Pairing dan manajemen akun keluarga terhubung.
- Bluetooth/smartcane monitoring.
- Ebook.
- Pengaturan akun.
- SOS darurat.

Layar terkait:

- `lib/screens/tunanetra/tunanetra_home_screen.dart`
- `lib/screens/tunanetra/navigation_screen.dart`
- `lib/screens/tunanetra/bluetooth_screen.dart`
- `lib/screens/tunanetra/smartcane_monitoring_screen.dart`
- `lib/screens/tunanetra/connected_family_accounts_screen.dart`
- `lib/screens/tunanetra/settings_screen.dart`
- `lib/screens/tunanetra/password_settings_screen.dart`
- `lib/screens/tunanetra/ebook_screen.dart`
- `lib/screens/tunanetra/tunanetra_profile_screen.dart`

### 3.2 Pengguna Keluarga

Fitur utama:

- Registrasi menggunakan email, password, dan link verifikasi sekali pakai dari Firebase.
- Login menggunakan email dan password, dengan pengecekan status verifikasi email.
- Menghubungkan akun dengan pengguna tunanetra.
- Memantau lokasi pengguna tunanetra secara real-time.
- Melihat status online/offline, baterai, tujuan, dan perjalanan aktif.
- Menerima notifikasi SOS full-screen.
- Melihat riwayat navigasi dan event perjalanan.
- Mengelola tempat tujuan keluarga.
- Melihat daftar anggota tunanetra yang terhubung.
- Pengaturan dan profil keluarga.

Layar terkait:

- `lib/screens/family/family_home_screen.dart`
- `lib/screens/family/live_tracking_screen.dart`
- `lib/screens/family/family_history_screen.dart`
- `lib/screens/family/emergency_sos_screen.dart`
- `lib/screens/family/family_manage_places_screen.dart`
- `lib/screens/family/family_members_list_screen.dart`
- `lib/screens/family/family_member_detail_screen.dart`
- `lib/screens/family/family_connected_tunanetra_screen.dart`
- `lib/screens/family/family_profile_screen.dart`
- `lib/screens/family/family_settings_screen.dart`

## 4. Arsitektur Aplikasi

### 4.1 Struktur Direktori Utama

```text
lib/
  main.dart
  firebase_options.dart
  models/
  screens/
    auth/
    tunanetra/
    family/
  services/
  utils/
  widgets/

functions/
  index.js
  package.json

workers/
  sos-worker/
    src/index.ts
    wrangler.toml
    package.json

assets/
  images/
  icons/
  sounds/

test/
```

### 4.2 Layer Aplikasi

- `screens/`: lapisan UI dan state lokal per halaman.
- `services/`: akses Firebase, API eksternal, sensor, lokasi, notifikasi, pairing, dan SOS.
- `models/`: struktur data aplikasi seperti user, lokasi, tempat, instruksi navigasi, dan lokasi keluarga.
- `utils/`: konstanta warna, teks, route, dan enum role.
- `widgets/`: komponen UI reusable.

### 4.3 Entry Point

Entry point aplikasi berada di `lib/main.dart`.

Proses awal:

1. `WidgetsFlutterBinding.ensureInitialized()`
2. Inisialisasi Firebase menggunakan `DefaultFirebaseOptions.currentPlatform`.
3. Registrasi handler background Firebase Messaging.
4. Inisialisasi `NotificationService`.
5. Membaca payload awal jika aplikasi dibuka dari notifikasi SOS.
6. Menjalankan `MyApp`.

Route awal dapat berubah:

- Jika ada payload SOS, aplikasi langsung membuka `EmergencySosScreen`.
- Jika ada payload monitoring SOS, aplikasi membuka `FamilyHistoryScreen`.
- Jika tidak ada payload khusus, aplikasi membuka `SplashScreen`.

## 5. Navigasi Route

Route didefinisikan di `lib/utils/constants.dart` dan dipasang di `MaterialApp`.

Route utama:

- `/`: splash screen.
- `/login`: login.
- `/register`: registrasi.
- `/tunanetra/home`: beranda tunanetra.
- `/tunanetra/navigation`: navigasi tunanetra.
- `/tunanetra/bluetooth`: Bluetooth.
- `/tunanetra/ebook`: ebook.
- `/tunanetra/smartcane`: monitoring smartcane.
- `/tunanetra/settings`: pengaturan tunanetra.
- `/family/home`: beranda keluarga.
- `/family/monitoring`: monitoring dan riwayat keluarga.
- `/family/manage-places`: kelola tempat.
- `/sos-fullscreen`: layar darurat SOS.

## 6. Autentikasi dan Verifikasi Email

Komponen utama:

- `lib/services/auth_service.dart`
- `lib/services/user_service.dart`
- `lib/screens/auth/login_screen.dart`
- `lib/screens/auth/register_screen.dart`

Alur registrasi:

1. Pengguna memilih role dan mengisi email, password, nama, nomor telepon, serta data role terkait.
2. Aplikasi membuat akun Firebase Authentication melalui `registerWithEmailPasswordAndVerification(...)`.
3. Firebase mengirim email verifikasi berisi link sekali pakai melalui `user.sendEmailVerification()`.
4. Aplikasi menampilkan dialog instruksi agar pengguna membuka email dan klik link verifikasi.
5. Aplikasi menunggu status verifikasi dengan `waitForEmailVerificationWithLongPolling()`.
6. Setelah email terverifikasi, aplikasi menyimpan profil ke Firestore `users/{uid}`.
7. Untuk role tunanetra, aplikasi juga membuat data pengguna tunanetra dan kode pairing.
8. Untuk role keluarga, aplikasi memvalidasi kode pairing lalu menyimpan relasi keluarga.

Alur login:

1. Pengguna memasukkan email dan password.
2. Aplikasi login melalui `loginWithEmailPasswordNew(...)`.
3. Aplikasi mengecek status email dengan `isEmailVerified()`.
4. Jika email belum terverifikasi, aplikasi menampilkan peringatan dan menyediakan aksi kirim ulang email verifikasi.
5. Jika user valid, aplikasi membaca data role dari Firestore lalu mengarahkan ke halaman sesuai role.

Catatan tentang OTP:

- Service OTP Flutter sudah dihapus karena tidak digunakan oleh flow aktif.
- Codebase masih menyisakan koleksi `otp_codes`, aturan Firestore terkait OTP, dan Cloud Function `sendOtpEmail` pada backend legacy.
- Berdasarkan layar aktif `login_screen.dart` dan `register_screen.dart`, flow utama saat ini bukan OTP, melainkan email/password dengan link verifikasi email Firebase.
- Bagian OTP backend dapat dianggap legacy/alternatif sampai benar-benar dihapus atau diaktifkan kembali.

Cloud Function `sendOtpEmail` legacy:

- Lokasi: `functions/index.js`
- Trigger: HTTPS request.
- Provider email: Gmail atau SendGrid melalui environment variable.
- Log email disimpan di `email_logs`.

## 7. Data Pengguna dan Pairing

Komponen utama:

- `lib/services/user_service.dart`
- `lib/services/pairing_service.dart`
- `lib/services/connected_family_service.dart`
- `lib/screens/tunanetra/connected_family_accounts_screen.dart`
- `lib/screens/family/family_home_screen.dart`

Koleksi terkait:

- `users`
- `users/{tunaNetraUid}/family_members`
- `users/{uid}/connected_family_devices`
- `pairing_codes`
- `pairing_requests`

Alur pairing umum:

1. Pengguna tunanetra membuat atau memiliki kode pairing.
2. Keluarga memasukkan kode pairing.
3. Sistem membuat dokumen `pairing_requests`.
4. Pengguna tunanetra menyetujui atau menolak permintaan.
5. Jika disetujui, data relasi diperbarui pada dokumen user dan subkoleksi family member.

Data hubungan dapat disimpan sebagai:

- `pairedUserUid`
- `pairedUserUids`
- `connectedFamilies`
- Subkoleksi `family_members`

## 8. Navigasi Tunanetra

Komponen utama:

- `lib/screens/tunanetra/navigation_screen.dart`
- `lib/services/routing_service.dart`
- `lib/services/places_service.dart`
- `lib/services/live_tracking_service.dart`
- `lib/services/navigation_history_service.dart`
- `lib/models/place_model.dart`
- `lib/models/navigation_instruction_model.dart`

Fitur navigasi:

- Mengambil lokasi pengguna menggunakan `geolocator`.
- Menampilkan peta dengan `flutter_map` dan tile OpenStreetMap.
- Memuat daftar tujuan dari Firestore.
- Menghitung rute dengan OSRM public endpoint.
- Mendukung rute jalan kaki.
- Menampilkan polyline rute.
- Membuat instruksi turn-by-turn.
- Melakukan snap posisi ke rute.
- Mendeteksi pengguna keluar jalur.
- Melakukan reroute dengan cooldown.
- Menyimpan riwayat titik perjalanan dan event.

API rute:

- `https://router.project-osrm.org/route/v1/foot`
- `https://router.project-osrm.org/route/v1/car`

Parameter navigasi penting:

- Ambang sampai tujuan: 5 meter.
- Snap ke rute: 20 meter.
- Keluar jalur: 35 meter.
- Konfirmasi keluar jalur: 2 detik.
- Cooldown reroute: 20 detik.
- Interval prediksi sensor: 250 ms.
- Batas prediksi: 15 meter.

Dokumentasi teknis tambahan tersedia di `navigation.md`.

## 9. Live Tracking

Komponen utama:

- `lib/services/live_tracking_service.dart`
- `lib/services/family_location_service.dart`
- `lib/screens/family/family_home_screen.dart`
- `lib/screens/family/live_tracking_screen.dart`
- `lib/screens/family/family_history_screen.dart`

Fungsi:

- Menulis status lokasi pengguna tunanetra ke Firestore.
- Membaca status real-time dari sisi keluarga.
- Menyimpan data lokasi keluarga ke Realtime Database dan histori Firestore.
- Menampilkan status online/offline berdasarkan freshness data.

Koleksi utama:

- `live_tracking`
- `location_history`
- `navigation_history`

Struktur dokumen `live_tracking/{uid}`:

- `userId`
- `lat`
- `lng`
- `connectionStatus`
- `gpsStatus`
- `batteryLevel`
- `updatedAt`
- `destinationName`
- `isNavigating`
- `currentTripId`
- `isPredicted`

Aturan status online:

- `connectionStatus == online`
- `lat` dan `lng` tersedia.
- `updatedAt` masih segar.
- Pada dokumentasi live tracking, batas freshness adalah 30 detik.

Mode tracking:

- Home tracking: update berkala saat pengguna berada di beranda.
- Navigation tracking: update GPS presisi tinggi saat navigasi aktif.
- Inactive tracking: menandai pengguna offline ketika tracking berhenti.

Dokumentasi teknis tambahan tersedia di `live_tracking.md`.

## 10. SOS Darurat dan Notifikasi

Komponen utama:

- `lib/services/sos_service.dart`
- `lib/services/notification_service.dart`
- `lib/screens/family/emergency_sos_screen.dart`
- `workers/sos-worker/src/index.ts`

Alur SOS:

1. Pengguna tunanetra menekan SOS.
2. Aplikasi mengambil lokasi, baterai, data user, dan relasi keluarga.
3. Aplikasi membuat dokumen `sos_alerts`.
4. Jika sedang navigasi, event SOS juga dicatat ke `navigation_history/{tripId}/events`.
5. Aplikasi memanggil Cloudflare Worker `/send-sos`.
6. Worker memverifikasi Firebase ID token.
7. Worker memastikan pengirim adalah user tunanetra.
8. Worker memastikan keluarga target memang terhubung.
9. Worker mengambil token FCM keluarga dari `users/{familyUid}/fcmTokens`.
10. Worker mengirim FCM data message prioritas tinggi.
11. Aplikasi keluarga membuka notifikasi full-screen atau halaman monitoring darurat.

Endpoint Worker:

- Production send SOS: `https://teman-arah-sos-worker.teman-arah.workers.dev/send-sos`
- Config check: `/config-check`
- Test FCM: `/test-fcm`

Environment Worker:

- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

Koleksi terkait:

- `sos_alerts`
- `users/{familyUid}/fcmTokens`
- `navigation_history/{tripId}/events`

Channel notifikasi lokal:

- SOS full-screen emergency.
- SOS emergency.
- SOS silent.

## 11. Tempat Tujuan

Komponen utama:

- `lib/services/places_service.dart`
- `lib/services/family_place_service.dart`
- `lib/screens/family/family_manage_places_screen.dart`
- `lib/models/place_model.dart`

Koleksi utama:

- `places`

Fungsi:

- Keluarga dapat menambahkan, mengedit, dan menghapus tempat.
- Tunanetra dapat memilih tempat sebagai tujuan navigasi.
- Data tempat berisi nama, kategori, latitude, longitude, alamat, dan metadata lain sesuai model.

## 12. Cuaca

Komponen utama:

- `lib/services/weather_service.dart`
- `lib/screens/tunanetra/tunanetra_home_screen.dart`

Fungsi:

- Mengambil lokasi pengguna.
- Mengambil cuaca real-time dari Open-Meteo.
- Reverse geocoding lokasi melalui Nominatim.
- Menyimpan cache cuaca di `SharedPreferences`.

API eksternal:

- `https://api.open-meteo.com/v1/forecast`
- `https://nominatim.openstreetmap.org/reverse`

Data cuaca:

- Suhu.
- Kelembapan.
- Kecepatan angin.
- Kondisi cuaca.
- Nama lokasi.

## 13. Bluetooth dan Smartcane

Komponen utama:

- `lib/services/bluetooth_service.dart`
- `lib/screens/tunanetra/bluetooth_screen.dart`
- `lib/screens/tunanetra/smartcane_monitoring_screen.dart`

Fungsi:

- Memindai perangkat Bluetooth menggunakan `flutter_blue_plus`.
- Mengelola status koneksi.
- Menampilkan data atau status smartcane pada halaman monitoring.

## 14. Text-to-Speech dan Speech-to-Text

Komponen utama:

- `lib/services/tts_service.dart`
- `lib/services/stt_service.dart`

Library:

- `flutter_tts`
- `speech_to_text`

Fungsi:

- TTS digunakan untuk membacakan informasi penting, terutama pada sisi tunanetra.
- STT menyediakan kemampuan input suara jika dibutuhkan oleh fitur UI.

## 15. Firebase dan Database

### 15.1 Firebase Services

Firebase yang digunakan:

- Firebase Core.
- Firebase Authentication.
- Cloud Firestore.
- Firebase Realtime Database.
- Firebase Messaging.
- Firebase Analytics.

Konfigurasi platform berada di:

- `lib/firebase_options.dart`

### 15.2 Koleksi Firestore

Koleksi yang digunakan oleh aplikasi:

- `users`
- `users/{uid}/family_members`
- `users/{uid}/connected_family_devices`
- `users/{uid}/fcmTokens`
- `otp_codes`
- `email_logs`
- `pairing_codes`
- `pairing_requests`
- `places`
- `live_tracking`
- `location_history`
- `alerts`
- `sos_alerts`
- `navigation_history`
- `navigation_history/{tripId}/route_points`
- `navigation_history/{tripId}/events`
- `_test`

### 15.3 Realtime Database

Path yang digunakan:

- `family_locations/{uid}`

Realtime Database digunakan oleh `FamilyLocationService` untuk menyimpan posisi keluarga secara realtime.

### 15.4 Firestore Rules

Rules berada di:

- `firestore.rules`

Ringkasan rules saat ini:

- `otp_codes`: create, read, dan update diizinkan dengan validasi dasar; delete ditolak.
- `users`: create dengan field minimal; read dan update untuk user terautentikasi; delete ditolak.
- `family_members`: read/write untuk user terautentikasi.
- `pairing_codes`: create dan read diizinkan; update terbatas; delete ditolak.
- `pairing_requests`: read/create/update untuk pihak terkait; delete ditolak.
- Default: read/write ditolak.

Catatan keamanan:

- Beberapa aturan masih luas, terutama `users` update dan read authenticated.
- Untuk produksi, aturan sebaiknya diperketat berdasarkan UID, role, dan hubungan pairing.

## 16. API dan Integrasi Eksternal

| Integrasi | Fungsi | Lokasi Kode |
| --- | --- | --- |
| Firebase Auth | Autentikasi user | `auth_service.dart` |
| Cloud Firestore | Database utama | berbagai service |
| Firebase Realtime Database | Lokasi keluarga realtime | `family_location_service.dart` |
| Firebase Messaging | Push notification | `notification_service.dart`, worker |
| Firebase Cloud Functions | Kirim email OTP legacy/alternatif | `functions/index.js` |
| Cloudflare Workers | Kirim SOS via FCM HTTP v1 | `workers/sos-worker/src/index.ts` |
| OSRM | Routing dan instruksi rute | `routing_service.dart` |
| OpenStreetMap tiles | Tampilan peta | screen peta |
| Open-Meteo | Cuaca | `weather_service.dart` |
| Nominatim | Reverse geocoding | `weather_service.dart` |
| Flutter Blue Plus | Bluetooth | `bluetooth_service.dart` |

## 17. Dependensi Utama

Dependensi Flutter penting dari `pubspec.yaml`:

- `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_database`, `firebase_messaging`, `firebase_analytics`.
- `flutter_local_notifications`: notifikasi lokal dan full-screen.
- `flutter_map`, `latlong2`: peta dan koordinat.
- `geolocator`, `geocoding`, `sensors_plus`: lokasi dan sensor.
- `flutter_blue_plus`: Bluetooth.
- `speech_to_text`, `flutter_tts`: suara.
- `http`, `dio`: HTTP client.
- `shared_preferences`: cache lokal.
- `battery_plus`: informasi baterai.
- `intl`: format data.

## 18. Cara Menjalankan Aplikasi

### 18.1 Persiapan

Pastikan sudah tersedia:

- Flutter SDK sesuai constraint `sdk: ^3.10.3`.
- Firebase project yang sesuai dengan `firebase_options.dart`.
- Android/iOS/Web configuration Firebase.
- Firestore, Authentication, Messaging, dan Realtime Database sudah aktif.

### 18.2 Install Dependency

```bash
flutter pub get
```

### 18.3 Jalankan Aplikasi

```bash
flutter run
```

Untuk web:

```bash
flutter run -d chrome
```

### 18.4 Build Web

```bash
flutter build web
```

Hasil build web berada di:

```text
build/web
```

Firebase Hosting dikonfigurasi untuk membaca folder `build/web`.

## 19. Deploy Backend

### 19.1 Firebase Functions

Masuk ke folder `functions` lalu install dependency:

```bash
npm install
```

Deploy functions:

```bash
firebase deploy --only functions
```

### 19.2 Firebase Hosting

Build web terlebih dahulu:

```bash
flutter build web
```

Deploy hosting:

```bash
firebase deploy --only hosting
```

Konfigurasi hosting:

- Site: `teman-arah`
- Public directory: `build/web`
- Rewrite SPA ke `/index.html`

### 19.3 Cloudflare Worker SOS

Masuk ke folder:

```bash
cd workers/sos-worker
```

Install dependency:

```bash
npm install
```

Deploy:

```bash
npx wrangler deploy
```

Nama worker:

```text
teman-arah-sos-worker
```

## 20. Pengujian dan Validasi

Pengujian dasar:

```bash
flutter analyze
flutter test
```

Validasi backend:

```bash
firebase deploy --only firestore:rules
npx wrangler --version
npx wrangler deploy --dry-run
```

Skenario manual yang perlu diuji:

- Registrasi tunanetra dengan email/password dan link verifikasi email.
- Registrasi keluarga dengan email/password, link verifikasi email, dan kode pairing.
- Login kedua role menggunakan email/password.
- Pairing keluarga dan tunanetra.
- Tunanetra memilih tujuan dan memulai navigasi.
- Keluarga melihat live tracking.
- Tunanetra mengirim SOS.
- Keluarga menerima notifikasi SOS.
- Keluarga membuka layar emergency dari notifikasi.
- Riwayat navigasi tersimpan.
- Tempat tujuan dapat ditambah, diedit, dan dihapus.
- Bluetooth scan berjalan pada perangkat fisik.

## 21. Catatan Operasional

- Fitur lokasi membutuhkan permission lokasi dan perangkat dengan GPS aktif.
- Fitur notifikasi membutuhkan permission notification dan FCM token yang tersimpan.
- Full-screen notification paling relevan diuji di Android fisik.
- OSRM public endpoint tidak membutuhkan API key, tetapi memiliki batas penggunaan publik.
- Nominatim juga memiliki kebijakan penggunaan publik, sehingga penggunaan produksi besar sebaiknya memakai endpoint terkelola sendiri atau provider resmi.
- Cloudflare Worker memerlukan service account Firebase yang valid.
- Email OTP legacy membutuhkan konfigurasi kredensial email jika flow OTP diaktifkan lagi.

## 22. Risiko dan Rekomendasi Pengembangan

Risiko teknis:

- Rules Firestore masih perlu diperketat untuk produksi.
- OSRM public endpoint dapat rate limited.
- Ketergantungan lokasi real-time dapat terganggu oleh battery optimization perangkat.
- Koneksi FCM dan full-screen notification perlu pengujian lintas versi Android.
- Beberapa file screen besar, terutama navigasi dan histori, akan lebih mudah dirawat jika dipecah menjadi controller, widget kecil, dan service domain.

Rekomendasi:

- Tambahkan unit test untuk service penting: verifikasi email, pairing, SOS, routing parser, dan navigation history.
- Tambahkan integration test untuk alur login, pairing, navigasi, dan SOS.
- Pisahkan konfigurasi endpoint ke file environment/flavor.
- Perketat Firestore rules berdasarkan role dan relasi pairing.
- Tambahkan monitoring error untuk Cloud Functions dan Worker.
- Dokumentasikan skema Firestore secara formal jika struktur data mulai stabil.

## 23. Referensi Dokumentasi Internal

- `navigation.md`: dokumentasi detail fitur navigasi tunanetra.
- `live_tracking.md`: dokumentasi detail fitur live tracking keluarga.
- `firestore.rules`: aturan akses database.
- `firebase.json`: konfigurasi Firebase Functions dan Hosting.
- `workers/sos-worker/wrangler.toml`: konfigurasi Cloudflare Worker.
