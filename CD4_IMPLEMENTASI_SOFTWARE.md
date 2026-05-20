# CD-4 Implementasi Software Aplikasi Teman Arah

Dokumen ini menjelaskan implementasi software aplikasi Teman Arah berdasarkan rancangan solusi pada CD-3. Pembahasan dibatasi pada bagian software aplikasi, yaitu aplikasi Flutter, integrasi Firebase, layanan navigasi, live tracking, pairing keluarga, SOS darurat, dan Worker backend untuk pengiriman notifikasi.

## 1.1 Diskripsi Umum Implementasi

Implementasi solusi Teman Arah diwujudkan dalam bentuk software mobile berbasis Flutter. Software ini memiliki dua jenis pengguna utama, yaitu pengguna tunanetra dan pengguna keluarga. Pengguna tunanetra menggunakan aplikasi untuk navigasi, pemantauan smart cane, koneksi Bluetooth, pengaturan akun, serta pengiriman SOS. Pengguna keluarga menggunakan aplikasi untuk memantau lokasi pengguna tunanetra, melihat riwayat navigasi, mengelola tempat, menghubungkan akun melalui pairing, dan menerima notifikasi darurat.

Wujud akhir software terdiri dari beberapa komponen:

1. Aplikasi mobile Flutter sebagai antarmuka utama pengguna.
2. Firebase Authentication untuk login, registrasi, dan verifikasi email.
3. Cloud Firestore untuk menyimpan profil pengguna, data pairing, tempat tujuan, riwayat navigasi, live tracking, FCM token, dan SOS alert.
4. Firebase Realtime Database untuk data lokasi real-time pada modul tertentu.
5. Firebase Cloud Messaging dan Flutter Local Notifications untuk notifikasi SOS.
6. Cloudflare Worker berbasis TypeScript sebagai backend server-side pengirim notifikasi SOS ke FCM.
7. OSRM public routing service untuk perhitungan rute pejalan kaki.
8. Package lokasi, sensor, speech-to-text, text-to-speech, dan Bluetooth untuk mendukung fitur aksesibilitas dan navigasi.

Prosedur implementasi dilakukan dengan cara memecah aplikasi ke dalam lapisan screen, service, model, utility, dan worker. Lapisan screen menangani tampilan dan interaksi pengguna. Lapisan service menangani komunikasi ke Firebase, OSRM, sensor perangkat, lokasi GPS, Bluetooth, dan notifikasi. Lapisan model digunakan untuk menormalkan struktur data agar mudah dikirim ke atau dibaca dari database. Lapisan worker digunakan untuk pekerjaan backend yang tidak boleh dilakukan langsung dari aplikasi Flutter, terutama pengiriman notifikasi FCM menggunakan credential server.

### Alat dan Bahan Implementasi

Alat dan bahan yang digunakan dalam implementasi software adalah sebagai berikut.

| Komponen | Kegunaan |
| --- | --- |
| Flutter SDK dan Dart | Framework dan bahasa utama aplikasi mobile. |
| Firebase Core | Inisialisasi koneksi Firebase di aplikasi Flutter. |
| Firebase Authentication | Autentikasi email dan password serta verifikasi email. |
| Cloud Firestore | Database utama untuk profil, pairing, lokasi, tempat, riwayat, SOS, dan token FCM. |
| Firebase Realtime Database | Listener data real-time untuk lokasi. |
| Firebase Messaging | Menerima pesan FCM dari backend. |
| Flutter Local Notifications | Menampilkan notifikasi lokal dan full-screen SOS. |
| Cloudflare Worker | Backend server-side untuk endpoint SOS dan test FCM. |
| OSRM | Layanan perhitungan rute dan instruksi turn-by-turn. |
| Geolocator dan Geocoding | Membaca lokasi perangkat dan mengubah koordinat/alamat. |
| Flutter Map dan LatLong2 | Menampilkan peta OpenStreetMap dan koordinat. |
| Sensors Plus | Membaca sensor gerak untuk prediksi posisi saat navigasi. |
| Speech To Text dan Flutter TTS | Input dan output suara untuk aksesibilitas. |
| Flutter Blue Plus | Komunikasi Bluetooth dengan perangkat smart cane. |
| Provider | State management ringan pada aplikasi. |
| Shared Preferences | Penyimpanan data lokal sederhana. |

### Struktur Source Code Utama

Source code aplikasi ditempatkan pada folder `lib`, sedangkan backend Worker ditempatkan pada folder `workers/sos-worker`.

| Folder/File | Fungsi |
| --- | --- |
| `lib/main.dart` | Entry point aplikasi, inisialisasi Firebase, notifikasi, theme, dan routing halaman. |
| `lib/firebase_options.dart` | Konfigurasi Firebase tiap platform. |
| `lib/screens/auth` | Tampilan splash, login, registrasi, dan pemilihan role. |
| `lib/screens/tunanetra` | Tampilan fitur pengguna tunanetra seperti home, navigasi, Bluetooth, e-book, monitoring smart cane, dan pengaturan. |
| `lib/screens/family` | Tampilan keluarga seperti home monitoring, riwayat, daftar anggota, detail anggota, SOS, dan kelola tempat. |
| `lib/services` | Lapisan service untuk Firebase, routing, lokasi, pairing, notifikasi, SOS, dan user. |
| `lib/models` | Struktur data seperti user, place, lokasi, dan instruksi navigasi. |
| `lib/utils/constants.dart` | Konstanta route, warna, style, dan konfigurasi umum. |
| `workers/sos-worker/src/index.ts` | Endpoint backend untuk config check, test FCM, dan send SOS. |

### Alur Umum Pengoperasian Software

Alur penggunaan aplikasi dimulai dari inisialisasi Firebase pada saat aplikasi dibuka. Setelah itu aplikasi menampilkan splash screen dan mengecek status login pengguna. Jika belum login, pengguna diarahkan ke halaman login atau registrasi. Pada registrasi, pengguna memilih role tunanetra atau family, memasukkan data akun, lalu melakukan verifikasi email.

Setelah login berhasil, aplikasi membaca role dari Firestore. Pengguna dengan role tunanetra diarahkan ke halaman utama tunanetra. Pengguna dengan role family diarahkan ke halaman utama keluarga. Pengguna tunanetra dapat memilih tujuan navigasi, memulai rute, mengaktifkan live tracking, dan mengirim SOS. Pengguna keluarga dapat melihat status live tracking, lokasi, baterai, riwayat perjalanan, daftar anggota yang terhubung, serta menerima notifikasi SOS.

### Source Code Inisialisasi Aplikasi

**Sumber:** `lib/main.dart`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw Exception('Firebase initialization timeout');
      },
    );
  } catch (e) {
    print('CRITICAL: Firebase initialization error: $e');
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await NotificationService.instance.initialize(
    navigatorKey: appNavigatorKey,
    requestPermission: false,
  );

  final initialSosPayload = NotificationService.instance
      .takeInitialSosPayload();

  runApp(MyApp(initialSosPayload: initialSosPayload));
}
```

Kode tersebut merupakan entry point aplikasi. `WidgetsFlutterBinding.ensureInitialized()` memastikan binding Flutter siap sebelum plugin native dipanggil. `Firebase.initializeApp()` membaca konfigurasi Firebase dari `firebase_options.dart`. Timeout 30 detik digunakan agar aplikasi tidak menggantung jika koneksi bermasalah. `FirebaseMessaging.onBackgroundMessage()` memasang handler pesan FCM ketika aplikasi berada di background. `NotificationService.instance.initialize()` menyiapkan notifikasi lokal dan navigator global untuk membuka halaman SOS dari notifikasi. Variabel `initialSosPayload` digunakan untuk mengecek apakah aplikasi dibuka dari notifikasi SOS.

### Source Code Routing Role dan Halaman

**Sumber:** `lib/main.dart`

```dart
return MaterialApp(
  navigatorKey: appNavigatorKey,
  navigatorObservers: [routeObserver],
  title: AppConstants.appName,
  debugShowCheckedModeBanner: false,
  initialRoute: initialSosPayload != null
      ? AppRoutes.sosFullScreen
      : AppRoutes.splash,
  routes: {
    AppRoutes.splash: (context) => const SplashScreen(),
    AppRoutes.login: (context) => const LoginScreen(),
    AppRoutes.register: (context) => const RegisterScreen(),
    AppRoutes.tunaNetraHome: (context) => const TunaNetraHomeScreen(),
    AppRoutes.tunaNetraNavigation: (context) => const NavigationScreen(),
    AppRoutes.familyHome: (context) {
      final args = ModalRoute.of(context)?.settings.arguments
          as Map<String, dynamic>?;
      return FamilyHomeScreen(
        targetUid: args?['targetUid'] as String? ?? '',
        familyId: args?['familyId'] as String? ?? '',
        initialSosData: _extractSosRouteData(args),
      );
    },
  },
);
```

Kode tersebut mendefinisikan peta navigasi aplikasi. `navigatorKey` memungkinkan service notifikasi membuka halaman tertentu tanpa bergantung pada `BuildContext` screen aktif. `initialRoute` memilih halaman pertama berdasarkan kondisi payload SOS. Jika aplikasi dibuka dari notifikasi SOS, pengguna langsung diarahkan ke halaman SOS full-screen. Jika tidak, aplikasi membuka splash screen. Objek `routes` memetakan nama route ke widget screen yang sesuai.

### Tampilan Software yang Perlu Dicantumkan pada Dokumen CD-4

Karena software menghasilkan tampilan mobile, dokumentasi CD-4 perlu melampirkan screenshot tampilan berikut.

| Tampilan | Penjelasan |
| --- | --- |
| Splash screen | Tampilan awal saat aplikasi mengecek status login. |
| Login screen | Tampilan autentikasi pengguna lama. |
| Register screen | Tampilan pendaftaran akun dan pemilihan data pengguna. |
| Role selection screen | Tampilan pemilihan role tunanetra atau keluarga. |
| Home tunanetra | Dashboard fitur untuk pengguna tunanetra. |
| Navigation screen | Tampilan peta, tujuan, rute, instruksi, dan status navigasi. |
| Bluetooth screen | Tampilan koneksi smart cane melalui Bluetooth. |
| Smartcane monitoring screen | Tampilan data monitoring smart cane. |
| Settings tunanetra | Tampilan pengaturan akun pengguna tunanetra. |
| Home family | Dashboard pemantauan keluarga. |
| Family history screen | Tampilan riwayat perjalanan dan monitoring anggota. |
| Family members list screen | Tampilan daftar pengguna tunanetra yang terhubung. |
| Family member detail screen | Tampilan detail anggota keluarga. |
| Emergency SOS screen | Tampilan alert darurat dari notifikasi SOS. |
| Manage places screen | Tampilan pengelolaan tempat tujuan. |

### Tampilan Database yang Perlu Dicantumkan pada Dokumen CD-4

Karena software menggunakan Firebase, dokumentasi CD-4 perlu melampirkan screenshot Firebase Console untuk struktur berikut.

| Database/Koleksi | Isi Data |
| --- | --- |
| Firebase Authentication | Akun pengguna, email, UID, dan status email verification. |
| `users` | Profil pengguna, role, pairing code, nomor telepon, dan token FCM. |
| `users/{uid}/fcmTokens` | Token perangkat untuk menerima notifikasi. |
| `live_tracking` | Lokasi aktif, status online/offline, baterai, tujuan, dan status navigasi. |
| `places` | Daftar tempat tujuan, kategori, latitude, longitude, dan metadata. |
| `pairing_requests` | Permintaan hubungan family dan tunanetra. |
| `navigation_history` atau data riwayat terkait | Titik perjalanan, event rute, dan informasi trip. |
| `sos_alerts` | Data SOS aktif, koordinat, UID pengguna, dan status alert. |
| Realtime Database path lokasi | Data lokasi real-time yang diterima melalui listener. |

## 1.2 Detail Implementasi

Bagian ini menjelaskan proses dan luaran implementasi software secara lebih rinci. Implementasi dibagi berdasarkan modul utama agar sesuai dengan struktur source code aplikasi.

Secara teknis, implementasi aplikasi dilakukan dengan pola pemisahan tanggung jawab sebagai berikut.

| Lapisan | Isi Implementasi | Tujuan |
| --- | --- | --- |
| Screen/UI | File pada `lib/screens` | Menampilkan halaman, menerima input pengguna, dan mengatur interaksi visual. |
| Service | File pada `lib/services` | Menjalankan proses bisnis, akses Firebase, akses GPS, routing, Bluetooth, notifikasi, dan komunikasi API. |
| Model | File pada `lib/models` | Menentukan bentuk data yang digunakan aplikasi agar pembacaan Firestore/API tidak tersebar dalam bentuk map mentah. |
| Utility | File pada `lib/utils` | Menyimpan konstanta route, warna, text style, dan nilai konfigurasi umum. |
| Worker Backend | File pada `workers/sos-worker` | Menangani proses server-side yang membutuhkan credential aman, khususnya pengiriman FCM SOS. |

Alur implementasi dimulai dari pembuatan struktur halaman, kemudian dilanjutkan dengan pembuatan service untuk menghubungkan halaman dengan Firebase dan API eksternal. Setelah itu dibuat model data untuk menormalkan data dari database. Pada tahap akhir, fitur notifikasi SOS dipindahkan ke Worker agar credential Firebase Admin tidak berada di aplikasi mobile.

### 1.2.1 Implementasi Autentikasi, Role, dan Verifikasi Email

Autentikasi diimplementasikan menggunakan Firebase Authentication untuk email dan password. Data role tidak disimpan di Firebase Auth, tetapi disimpan di Firestore pada dokumen `users/{uid}`. Pemisahan ini membuat Firebase Auth bertugas menangani identitas login, sedangkan Firestore menangani profil aplikasi seperti nama, nomor telepon, dan role pengguna.

Komponen yang terlibat dalam modul autentikasi adalah sebagai berikut.

| Komponen | Peran |
| --- | --- |
| `LoginScreen` | Menerima email dan password pengguna lama. |
| `RegisterScreen` | Menerima data akun baru seperti nama, email, password, nomor telepon, dan role. |
| `RoleSelectionScreen` | Menentukan apakah pengguna mendaftar sebagai tunanetra atau keluarga. |
| `SplashScreen` | Mengecek sesi login dan mengarahkan pengguna ke halaman sesuai role. |
| `AuthService` | Menghubungkan UI dengan Firebase Authentication dan Firestore. |
| `users/{uid}` | Menyimpan profil aplikasi dan role pengguna. |

Alur implementasi autentikasi terdiri dari empat tahap. Tahap pertama, pengguna mengisi form registrasi dan memilih role. Tahap kedua, aplikasi membuat akun pada Firebase Authentication. Tahap ketiga, aplikasi mengirim email verification agar akun tidak langsung dianggap valid tanpa verifikasi. Tahap keempat, setelah verifikasi berhasil, profil pengguna disimpan ke Firestore. Pada saat login, aplikasi tidak hanya memvalidasi email dan password, tetapi juga membaca dokumen `users/{uid}` untuk menentukan role dan halaman tujuan.

**Sumber:** `lib/services/auth_service.dart`

```dart
Future<User?> registerWithEmailPasswordAndVerification({
  required String email,
  required String password,
  required String name,
  required String phoneNumber,
  required UserType userType,
}) async {
  email = email.toLowerCase().trim();

  final userCredential = await _auth
      .createUserWithEmailAndPassword(email: email, password: password)
      .timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Account creation timeout'),
      );

  final user = userCredential.user;
  if (user == null) {
    throw Exception('Failed to create user account');
  }

  await user.sendEmailVerification().timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw Exception('Email verification send timeout'),
  );

  return user;
}
```

Variabel `email`, `password`, `name`, `phoneNumber`, dan `userType` berasal dari form registrasi. `email.toLowerCase().trim()` digunakan untuk menormalkan email agar tidak terjadi duplikasi karena perbedaan huruf kapital atau spasi. Fungsi `createUserWithEmailAndPassword()` membuat akun pada Firebase Authentication. Fungsi `sendEmailVerification()` mengirimkan link verifikasi ke email pengguna. Return `user` dipakai oleh screen registrasi untuk melanjutkan alur setelah akun berhasil dibuat.

**Sumber:** `lib/services/auth_service.dart`

```dart
Future<void> saveUserDataToFirestore({
  required String uid,
  required String email,
  required String name,
  required String phoneNumber,
  required UserType userType,
}) async {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .set({
        'uid': uid,
        'email': email,
        'name': name,
        'phoneNumber': phoneNumber,
        'userType': userType.toString(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}
```

Fungsi `saveUserDataToFirestore()` menyimpan profil pengguna ke Cloud Firestore. Parameter `uid` menjadi ID dokumen agar data profil selalu terhubung dengan akun Firebase Auth. Field `userType` digunakan untuk menentukan apakah pengguna masuk ke halaman tunanetra atau family. `FieldValue.serverTimestamp()` digunakan agar waktu pembuatan dan pembaruan data mengikuti waktu server Firebase.

**Sumber:** `lib/services/auth_service.dart`

```dart
Future<UserType?> getUserType() async {
  final userId = currentUserId;
  if (userId == null) {
    return null;
  }

  final userDoc = await db.collection('users').doc(userId).get();

  if (userDoc.exists) {
    final userType = userDoc.data()?['userType'] as String?;
    if (userType == UserType.tunanetra.toString()) {
      return UserType.tunanetra;
    }
    if (userType == UserType.family.toString()) {
      return UserType.family;
    }
  }

  return null;
}
```

Fungsi `getUserType()` membaca role pengguna dari Firestore. Variabel `currentUserId` berasal dari sesi Firebase Auth yang aktif. Jika dokumen ditemukan, field `userType` dibandingkan dengan enum `UserType.tunanetra` dan `UserType.family`. Hasil return dipakai oleh splash screen atau login flow untuk menentukan halaman awal pengguna.

Data yang dihasilkan modul autentikasi adalah dokumen profil pengguna. Untuk pengguna tunanetra, data ini menjadi dasar pembuatan pairing code, live tracking, dan riwayat navigasi. Untuk pengguna keluarga, data ini menjadi dasar penerimaan pairing request, penyimpanan FCM token, dan akses monitoring. Dengan demikian, modul autentikasi menjadi fondasi bagi hampir seluruh fitur lain.

Penanganan error dilakukan pada beberapa titik. Jika koneksi lambat, operasi Firebase diberi `timeout`. Jika user belum login, service mengembalikan `null` agar screen dapat mengarahkan pengguna kembali ke halaman login. Jika dokumen role tidak ditemukan, aplikasi tidak memaksakan navigasi ke halaman utama karena role adalah penentu hak akses tampilan.

### 1.2.2 Implementasi Navigasi dan Perhitungan Rute

Modul navigasi digunakan oleh pengguna tunanetra untuk memilih tempat tujuan, menghitung rute pejalan kaki, menampilkan polyline pada peta, dan memberi instruksi turn-by-turn. Perhitungan rute dilakukan melalui service OSRM. Koordinat menggunakan format `LatLng` dari package `latlong2`, sedangkan tampilan peta menggunakan `flutter_map`.

Komponen implementasi navigasi adalah sebagai berikut.

| Komponen | Peran |
| --- | --- |
| `NavigationScreen` | Halaman utama navigasi, peta, daftar tujuan, status rute, dan instruksi. |
| `PlacesService` | Membaca daftar tempat tujuan dari Firestore. |
| `RoutingService` | Mengambil rute dan instruksi dari OSRM. |
| `LiveTrackingService` | Mengirim posisi pengguna selama navigasi ke Firestore. |
| `NavigationHistoryService` | Menyimpan titik perjalanan dan event navigasi. |
| `PlaceModel` | Struktur data tempat tujuan. |
| `NavigationInstruction` | Struktur instruksi navigasi turn-by-turn. |

Alur implementasi navigasi dimulai ketika `NavigationScreen` dijalankan. Screen meminta izin lokasi melalui Geolocator. Jika izin diberikan, posisi GPS pertama digunakan sebagai `origin`. Setelah itu aplikasi membaca daftar tempat dari Firestore melalui `PlacesService`. Ketika pengguna memilih tujuan, aplikasi mengirim `origin` dan `destination` ke `RoutingService`. Hasil dari OSRM berupa polyline, jarak, durasi, dan instruksi belok. Data tersebut disimpan ke state screen dan ditampilkan pada peta.

Ketika navigasi dimulai, aplikasi mengaktifkan streaming GPS presisi tinggi. Setiap perubahan posisi dipakai untuk memperbarui marker pengguna, mengecek progres pada rute, menyimpan riwayat titik perjalanan, dan mengirim live tracking ke keluarga. Jika posisi pengguna keluar dari rute melebihi batas tertentu, aplikasi melakukan deteksi off-route dan memuat ulang rute dari posisi terbaru.

**Sumber:** `lib/services/routing_service.dart`

```dart
Future<List<LatLng>> getRoute({
  required LatLng origin,
  required LatLng destination,
}) async {
  final baseUrl = _baseUrlFoot;
  final coordinates =
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}';
  final url =
      '$baseUrl/$coordinates?geometries=geojson&overview=full&steps=true';

  final response = await http.get(Uri.parse(url));
  final data = json.decode(response.body);
  final routes = data['routes'] as List;
  final geometry = routes.first['geometry']['coordinates'] as List;

  return geometry
      .map((point) => LatLng(point[1].toDouble(), point[0].toDouble()))
      .toList();
}
```

Parameter `origin` adalah lokasi awal pengguna, sedangkan `destination` adalah lokasi tujuan. OSRM membutuhkan format koordinat `longitude,latitude`, sehingga kode menyusun variabel `coordinates` dengan urutan longitude lebih dahulu. Parameter `geometries=geojson` membuat response berisi koordinat polyline. Data `geometry['coordinates']` dikonversi kembali ke `LatLng(latitude, longitude)` agar dapat ditampilkan oleh Flutter Map.

**Sumber:** `lib/services/routing_service.dart`

```dart
Future<List<NavigationInstruction>> getNavigationInstructions({
  required LatLng origin,
  required LatLng destination,
  String profile = 'foot',
}) async {
  final baseUrl = _getBaseUrl(profile);
  final coordinates =
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}';
  final url =
      '$baseUrl/$coordinates?overview=full&geometries=geojson'
      '&steps=true&annotations=distance,duration';

  final response = await http.get(Uri.parse(url));
  final data = json.decode(response.body);
  final routes = data['routes'] as List;
  final legs = routes.first['legs'] as List;

  return _parseInstructionsFromLegs(legs);
}
```

Fungsi `getNavigationInstructions()` meminta detail langkah navigasi dari OSRM. Parameter `steps=true` digunakan agar OSRM mengembalikan instruksi belok. Parameter `annotations=distance,duration` menambahkan jarak dan durasi tiap segmen. Fungsi `_parseInstructionsFromLegs()` mengubah response OSRM menjadi list `NavigationInstruction` yang lebih mudah ditampilkan pada UI.

Output utama modul navigasi adalah polyline rute, instruksi navigasi, status navigasi aktif, dan riwayat perjalanan. Polyline digunakan untuk menggambar jalur pada peta. Instruksi navigasi digunakan untuk memberi arahan kepada pengguna. Status navigasi aktif dikirim ke `live_tracking/{uid}` agar keluarga mengetahui bahwa pengguna sedang menuju suatu tempat. Riwayat perjalanan disimpan agar keluarga dapat melihat perjalanan setelah navigasi selesai.

Parameter penting pada modul ini adalah `origin`, `destination`, `profile`, `routePoints`, dan `navigationInstructions`. `origin` selalu diperbarui berdasarkan lokasi pengguna. `destination` berasal dari tempat yang dipilih. `profile` default menggunakan `foot` karena aplikasi ditujukan untuk pejalan kaki. `routePoints` berisi titik polyline, sedangkan `navigationInstructions` berisi daftar langkah belok.

### 1.2.3 Implementasi Live Tracking

Live tracking digunakan agar keluarga dapat melihat status lokasi pengguna tunanetra secara real-time. Saat pengguna berada di home, aplikasi melakukan tracking berkala. Saat navigasi dimulai, aplikasi menggunakan mode akurasi tinggi dan memperbarui dokumen `live_tracking/{uid}`.

Implementasi live tracking dibagi menjadi dua mode, yaitu home tracking dan navigation tracking. Home tracking berjalan saat pengguna tidak sedang bernavigasi. Mode ini cukup memperbarui lokasi secara berkala agar keluarga tetap mengetahui posisi terakhir. Navigation tracking berjalan saat pengguna sedang mengikuti rute. Mode ini menggunakan akurasi lebih tinggi, update lebih sering, dan menyertakan informasi tujuan.

| Mode | Kondisi Aktif | Data yang Ditulis |
| --- | --- | --- |
| Home tracking | Pengguna berada di halaman utama atau tidak bernavigasi | Latitude, longitude, baterai, status online, waktu update. |
| Navigation tracking | Pengguna menekan mulai navigasi | Latitude, longitude, tujuan, status navigasi, GPS status, speed, heading, trip ID. |
| Inactive tracking | GPS tidak tersedia, izin ditolak, atau stream gagal | Status offline, koordinat null, tujuan null. |

Firestore digunakan sebagai sumber data monitoring keluarga. Dokumen `live_tracking/{uid}` selalu memakai UID pengguna tunanetra sebagai ID dokumen. Dengan cara ini, screen keluarga cukup memasang listener ke UID yang sudah terhubung melalui pairing.

**Sumber:** `lib/services/live_tracking_service.dart`

```dart
Future<void> startHomeLocationTracking() async {
  if (_isStartingHomeTracking ||
      _homeSubscription != null ||
      _homeRefreshTimer != null) {
    return;
  }

  _isStartingHomeTracking = true;
  final startToken = ++_homeStartToken;

  _homeRefreshTimer = Timer.periodic(_homeRefreshInterval, (_) {
    unawaited(_refreshHomeTracking(startStreamIfNeeded: true));
  });

  try {
    await _refreshHomeTracking(
      startStreamIfNeeded: true,
      startToken: startToken,
    );
  } catch (_) {
    await updateInactiveTracking();
  } finally {
    _isStartingHomeTracking = false;
  }
}
```

Variabel `_isStartingHomeTracking` mencegah proses tracking dimulai dua kali. `_homeSubscription` menyimpan stream posisi dari Geolocator. `_homeRefreshTimer` menjalankan pembaruan berkala berdasarkan `_homeRefreshInterval`. `startToken` digunakan untuk memastikan proses refresh lama tidak menimpa proses baru. Jika proses tracking gagal, fungsi `updateInactiveTracking()` dipanggil untuk menandai pengguna offline.

**Sumber:** `lib/services/live_tracking_service.dart`

```dart
Future<void> startNavigationTracking({
  required String? destinationName,
  required void Function(Position position) onPosition,
  void Function(Object error)? onError,
}) async {
  if (_isStartingNavigationTracking || _navigationSubscription != null) {
    return;
  }

  _isStartingNavigationTracking = true;
  await stopHomeLocationTracking();

  try {
    final canTrack = await _ensureLocationReady();
    if (!canTrack) {
      await updateInactiveTracking();
      return;
    }

    _navigationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((position) {
      _lastNavigationPosition = position;
      onPosition(position);
      unawaited(updateLiveTracking(
        position: position,
        isNavigating: true,
        isPredicted: false,
        gpsStatus: 'gps_live',
        connectionStatus: 'online',
        destinationName: destinationName,
        speed: position.speed.isFinite ? position.speed : null,
        throttle: true,
      ));
    }, onError: (error) {
      unawaited(updateInactiveTracking());
      onError?.call(error);
    });
  } finally {
    _isStartingNavigationTracking = false;
  }
}
```

Fungsi `startNavigationTracking()` dipanggil ketika navigasi aktif. Fungsi ini menghentikan home tracking agar tidak ada dua stream lokasi yang berjalan bersamaan. `LocationAccuracy.bestForNavigation` dan `distanceFilter: 1` digunakan untuk memperoleh update posisi yang lebih akurat saat pengguna bergerak. Callback `onPosition` mengirim posisi terbaru ke screen navigasi. Fungsi `updateLiveTracking()` menulis data lokasi ke Firestore dengan status `online`, `gps_live`, dan `isNavigating: true`.

**Sumber:** `lib/services/live_tracking_service.dart`

```dart
Future<void> updateInactiveTracking() async {
  final user = _auth.currentUser;
  if (user == null) return;

  await _firestore.collection('live_tracking').doc(user.uid).set({
    'userId': user.uid,
    'batteryLevel': null,
    'lat': null,
    'lng': null,
    'accuracy': null,
    'destinationName': null,
    'isNavigating': false,
    'connectionStatus': 'offline',
    'gpsStatus': 'inactive',
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
```

Fungsi `updateInactiveTracking()` mengubah status pengguna menjadi offline ketika lokasi tidak tersedia, izin lokasi ditolak, stream error, atau tracking dihentikan. Field `lat` dan `lng` dibuat null agar keluarga tidak menganggap lokasi lama sebagai lokasi aktif. Field `updatedAt` tetap diperbarui agar UI dapat mengetahui kapan status offline terakhir ditulis.

Output dari live tracking adalah dokumen Firestore yang terus diperbarui. Field `connectionStatus` digunakan untuk menentukan online atau offline. Field `gpsStatus` membedakan lokasi live, prediksi, atau inactive. Field `isNavigating` memberi tanda apakah pengguna sedang melakukan perjalanan. Field `updatedAt` dipakai oleh aplikasi keluarga untuk menentukan apakah data masih segar. Pada dokumentasi teknis aplikasi, data dianggap segar jika waktu pembaruan masih dalam batas toleransi, misalnya sekitar 30 detik.

Implementasi ini juga mempertimbangkan efisiensi baterai. Home tracking tidak dibuat seagresif navigation tracking karena pengguna belum tentu sedang bergerak menuju tujuan. Saat navigasi aktif, akurasi dinaikkan karena kebutuhan arah dan pemantauan lebih penting. Saat navigasi berhenti, aplikasi kembali ke home tracking agar pemantauan tetap berjalan tanpa konsumsi GPS berlebihan.

### 1.2.4 Implementasi Monitoring Keluarga

Monitoring keluarga berada pada screen family. Screen membaca daftar pengguna tunanetra yang terhubung dengan akun keluarga, lalu memasang listener pada data profil, lokasi, dan live tracking. Data yang diterima ditampilkan dalam bentuk kartu status online/offline, koordinat, baterai, tujuan, dan waktu pembaruan terakhir.

Proses implementasi monitoring keluarga dilakukan dengan pendekatan listener. Setelah keluarga login, aplikasi mencari daftar UID pengguna tunanetra yang terhubung. Untuk setiap UID, aplikasi memasang listener ke beberapa sumber data: profil pengguna pada `users/{uid}`, status lokasi pada `live_tracking/{uid}`, dan data SOS aktif pada `sos_alerts`. Dengan mekanisme listener, tampilan keluarga dapat berubah otomatis saat data di database berubah.

Data yang ditampilkan pada halaman keluarga meliputi nama pengguna, status online/offline, koordinat terakhir, baterai, tujuan aktif, waktu pembaruan terakhir, dan status SOS. Jika data `updatedAt` sudah terlalu lama, UI menganggap data tidak segar dan menampilkan status offline agar keluarga tidak salah membaca lokasi lama sebagai posisi aktif.

**Sumber:** `live_tracking.md` dan `lib/screens/family/family_home_screen.dart`

```dart
_subscribeToLiveTracking(uid) {
  final subscription = FirebaseFirestore.instance
      .collection('live_tracking')
      .doc(uid)
      .snapshots()
      .listen((snapshot) {
        if (!snapshot.exists) return;
        setState(() {
          _liveTrackingData[uid] = snapshot.data() ?? {};
        });
      });

  _liveTrackingSubscriptions[uid] = subscription;
}
```


Kode tersebut menggambarkan cara screen keluarga menerima perubahan data live tracking. Method `snapshots()` membuat listener real-time ke dokumen Firestore. Ketika dokumen berubah, variabel `_liveTrackingData` diperbarui menggunakan `setState()` sehingga UI ikut berubah. Variabel `_liveTrackingSubscriptions` menyimpan subscription agar dapat dihentikan ketika screen ditutup.

Luaran modul monitoring keluarga adalah dashboard pemantauan. Dashboard ini bukan hanya menampilkan data, tetapi juga menjadi penghubung ke fitur lain seperti riwayat perjalanan, detail anggota, daftar anggota, kelola tempat, dan emergency SOS. Dengan demikian, screen family menjadi pusat kendali bagi pengguna keluarga.

### 1.2.5 Implementasi Pairing Pengguna Tunanetra dan Keluarga

Pairing digunakan agar akun keluarga hanya dapat memantau pengguna tunanetra yang memang terhubung. Pengguna keluarga memasukkan pairing code, lalu aplikasi memverifikasi kode tersebut dan membuat permintaan pairing. Setelah permintaan diterima, relasi disimpan pada data pengguna.

Pairing diperlukan untuk membatasi akses monitoring. Tanpa pairing, akun keluarga tidak boleh membaca lokasi pengguna tunanetra. Implementasi ini menggunakan pairing code sebagai jembatan awal. Pengguna tunanetra memiliki kode pairing, sedangkan pengguna keluarga memasukkan kode tersebut untuk membuat permintaan. Status permintaan disimpan sebagai `pending`, kemudian dapat diterima atau ditolak oleh pihak terkait sesuai alur aplikasi.

| Status Pairing | Arti |
| --- | --- |
| `pending` | Permintaan sudah dibuat tetapi belum disetujui. |
| `accepted` | Hubungan keluarga dan tunanetra sudah aktif. |
| `rejected` | Permintaan ditolak. |
| `cancelled` atau status sejenis | Permintaan tidak dilanjutkan. |

**Sumber:** `lib/services/pairing_service.dart`

```dart
Future<String> createPairingRequest({
  required String familyUid,
  required String pairingCode,
}) async {
  final targetUser = await verifyPairingCode(pairingCode);
  if (targetUser == null) {
    throw const PairingException(
      'Kode pairing tidak ditemukan. Pastikan kode sudah benar dan masih aktif.',
      code: 'code-not-found',
    );
  }

  final requestRef = await _firestore.collection('pairing_requests').add({
    'familyUid': familyUid,
    'targetUid': targetUser.uid,
    'pairingCode': pairingCode,
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  return requestRef.id;
}
```

Fungsi `createPairingRequest()` menerima `familyUid` dan `pairingCode`. Fungsi `verifyPairingCode()` memastikan kode pairing valid dan masih aktif. Jika tidak valid, aplikasi melempar `PairingException` agar UI dapat menampilkan pesan kesalahan. Jika valid, data permintaan pairing disimpan pada koleksi `pairing_requests` dengan status `pending`.

Data pairing yang berhasil digunakan oleh modul monitoring keluarga. Setelah hubungan aktif, UID pengguna tunanetra dapat masuk ke daftar pantauan keluarga. Dari UID tersebut, aplikasi keluarga dapat membaca profil, live tracking, riwayat, dan notifikasi SOS yang relevan. Dengan demikian, pairing menjadi mekanisme otorisasi aplikasi pada level fitur.

### 1.2.6 Implementasi SOS Darurat dan Notifikasi

SOS darurat melibatkan dua sisi implementasi. Sisi Flutter membuat alert dan memanggil backend. Sisi backend Worker memverifikasi token Firebase, mengecek relasi family dan tunanetra, mengambil FCM token keluarga, lalu mengirim pesan FCM. Pendekatan ini digunakan agar credential sensitif Firebase tidak disimpan pada aplikasi mobile.

Alur SOS dimulai dari pengguna tunanetra. Ketika tombol SOS digunakan, aplikasi mengumpulkan informasi penting seperti UID pengguna, UID keluarga tujuan, nama pengguna, koordinat terakhir, level baterai, dan trip ID jika sedang bernavigasi. Data tersebut dikirim ke endpoint Worker `/send-sos` bersama Firebase ID token pada header Authorization. Worker kemudian melakukan validasi token, memastikan UID request sama dengan UID yang login, memastikan pengguna adalah tunanetra, memastikan keluarga memang terhubung, mengambil FCM token keluarga, lalu mengirim pesan FCM.

Komponen SOS terdiri dari:

| Komponen | Peran |
| --- | --- |
| `SosService` | Menyiapkan data SOS dari aplikasi Flutter dan mengirim request ke Worker. |
| `NotificationService` | Mengelola token FCM, izin notifikasi, foreground notification, dan full-screen notification. |
| `EmergencySosScreen` | Menampilkan detail SOS darurat kepada keluarga. |
| `workers/sos-worker/src/index.ts` | Backend validasi dan pengiriman FCM. |
| `sos_alerts` | Penyimpanan status alert SOS pada database. |
| `users/{familyUid}/fcmTokens` | Sumber token perangkat keluarga. |

**Sumber:** `workers/sos-worker/src/index.ts`

```ts
async function handleSendSos(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonResponse({
      success: false,
      message: 'Method not allowed. Use POST /send-sos',
    }, 405, { Allow: 'POST, OPTIONS' });
  }

  const bearerToken = getBearerToken(request);
  if (bearerToken.status === 'missing') {
    return jsonResponse({
      success: false,
      message: 'Missing authorization token',
    }, 401);
  }

  const idToken = (bearerToken as { status: 'ok'; token: string }).token;
  const body = await parseJsonBody<SosRequestBody>(request);
  if (!body.ok) {
    return jsonResponse({
      success: false,
      message: 'Invalid JSON body',
    }, 400);
  }

  const decodedToken = await verifyFirebaseIdToken(idToken, env);
  const authUid = getAuthUid(decodedToken);
  const requestUserId = getRequiredString(body.value.userId);
  if (authUid !== requestUserId) {
    return jsonResponse({
      success: false,
      message: 'User ID does not match authenticated user',
    }, 403);
  }

  const result = await sendSosNotification(env, body.value);
  return jsonResponse({
    success: true,
    message: 'SOS notification sent',
    sentCount: result.sentCount,
    failedCount: result.failedCount,
  });
}
```

Fungsi `handleSendSos()` adalah endpoint utama `/send-sos`. Method selain POST ditolak. Header `Authorization` wajib berisi Firebase ID token. Body request dibaca sebagai `SosRequestBody`. Fungsi `verifyFirebaseIdToken()` memastikan request berasal dari pengguna yang login. Variabel `authUid` dibandingkan dengan `requestUserId` agar pengguna tidak dapat mengirim SOS atas nama UID lain. Setelah validasi berhasil, fungsi `sendSosNotification()` mengirim notifikasi ke perangkat keluarga.

**Sumber:** `workers/sos-worker/src/index.ts`

```ts
function createSosFcmPayload(data: SosRequestBody): Record<string, unknown> {
  const userId = getRequiredString(data.userId);
  const familyUid = getRequiredString(data.familyUid);
  const userName = getRequiredString(data.userName);
  const title = '\u{1F6A8} SOS Darurat';
  const body = `${userName} membutuhkan bantuan segera`;

  return {
    data: {
      type: 'sos',
      title,
      body,
      userId,
      familyUid,
      userName,
      lat: optionalStringValue(data.lat),
      lng: optionalStringValue(data.lng),
      batteryLevel: optionalStringValue(data.batteryLevel),
      currentTripId: getOptionalString(data.currentTripId) ?? '',
      sosId: getOptionalString(data.sosId) ?? '',
    },
    android: {
      priority: 'HIGH',
    },
  };
}
```

Fungsi `createSosFcmPayload()` membentuk payload FCM. Field `type: 'sos'` digunakan aplikasi Flutter untuk mengenali bahwa pesan tersebut adalah notifikasi darurat. Field `lat`, `lng`, `batteryLevel`, `currentTripId`, dan `sosId` dikirim sebagai data tambahan agar halaman keluarga dapat membuka detail SOS dengan konteks lokasi dan status pengguna.

Keamanan SOS diterapkan pada beberapa lapis. Pertama, endpoint hanya menerima method POST. Kedua, request harus membawa Firebase ID token. Ketiga, Worker memverifikasi token menggunakan public certificate Firebase. Keempat, UID token harus sama dengan `userId` pada body request. Kelima, Worker mengecek bahwa pengguna adalah tunanetra dan keluarga tujuan memang terhubung. Dengan cara ini, pengguna tidak dapat mengirim notifikasi palsu menggunakan UID orang lain.

Luaran modul SOS adalah notifikasi prioritas tinggi dan data alert pada aplikasi keluarga. Pada Android, payload dikirim dengan priority `HIGH` agar notifikasi darurat lebih cepat diproses. Aplikasi Flutter kemudian menampilkan notifikasi full-screen atau membuka `EmergencySosScreen` jika pengguna menekan notifikasi.

### 1.2.7 Implementasi Notifikasi Background di Flutter

Ketika pesan FCM diterima pada background, Flutter menjalankan handler khusus. Handler ini harus berada di level top-level function agar dapat dipanggil oleh Firebase Messaging.

**Sumber:** `lib/main.dart`

```dart
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (message.data['type'] == 'sos') {
    await NotificationService.showBackgroundSosFullScreenNotification(message);
  }
}
```

Annotation `@pragma('vm:entry-point')` menjaga agar fungsi tidak dihapus oleh proses tree shaking ketika build release. Firebase diinisialisasi ulang karena handler background berjalan pada isolate berbeda. Kondisi `message.data['type'] == 'sos'` memastikan hanya pesan SOS yang memunculkan notifikasi full-screen.

Selain background handler, aplikasi juga menginisialisasi notifikasi lokal saat `main()` dijalankan. Inisialisasi ini penting karena pesan FCM belum tentu langsung ditampilkan oleh sistem sesuai kebutuhan aplikasi. Dengan `NotificationService`, payload FCM dapat diubah menjadi notifikasi lokal yang memiliki behavior khusus, misalnya full-screen untuk SOS. Payload awal juga disimpan sementara agar ketika aplikasi dibuka dari notifikasi, route awal dapat langsung diarahkan ke halaman SOS.

### 1.2.8 Implementasi Model Data

Model data digunakan agar data dari Firestore dan API eksternal tidak langsung dipakai dalam bentuk map mentah. Salah satu model penting adalah `PlaceModel`, yang merepresentasikan tempat tujuan navigasi.

Implementasi model data dibuat untuk menjaga konsistensi tipe data. Firestore mengembalikan data dalam bentuk `Map<String, dynamic>`, sedangkan aplikasi membutuhkan tipe yang lebih jelas seperti `String`, `double`, `DateTime`, `LatLng`, atau enum. Model membantu proses konversi tersebut, sehingga validasi data tidak tersebar pada setiap screen.

Model yang digunakan pada aplikasi adalah sebagai berikut.

| Model | Sumber File | Fungsi |
| --- | --- | --- |
| `UserModel` dan model user terkait | `lib/models/user_model.dart`, `lib/models/user_models.dart` | Merepresentasikan profil pengguna, role, dan data akun. |
| `RegisterModel` | `lib/models/register_model.dart` | Menampung data form registrasi sebelum dikirim ke service. |
| `PlaceModel` | `lib/models/place_model.dart` | Merepresentasikan tempat tujuan navigasi. |
| `LocationModel` | `lib/models/location_model.dart` | Merepresentasikan koordinat lokasi umum. |
| `FamilyLocationModel` | `lib/models/family_location_model.dart` | Merepresentasikan data lokasi yang dibaca keluarga. |
| `NavigationInstruction` | `lib/models/navigation_instruction_model.dart` | Merepresentasikan instruksi belok dari OSRM. |

**Sumber:** `lib/models/place_model.dart`

```dart
class PlaceModel {
  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final String? description;

  PlaceModel({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.description,
  });
}
```

Field `id` berisi ID dokumen tempat. Field `name` dan `category` digunakan untuk menampilkan daftar tempat. Field `latitude` dan `longitude` digunakan untuk menghitung rute dari lokasi pengguna ke tujuan. Field `description` bersifat opsional karena tidak semua tempat harus memiliki keterangan tambahan.

Secara implementasi, model biasanya dilengkapi method pembantu seperti `fromMap`, `fromFirestore`, `toMap`, atau method sejenis. Method pembaca digunakan ketika data dari Firestore akan ditampilkan pada aplikasi. Method penulis digunakan ketika aplikasi akan menyimpan data kembali ke Firestore. Dengan pola ini, screen tidak perlu mengetahui detail nama field database secara langsung.

Contoh alur penggunaan model adalah pada tempat tujuan. `PlacesService` membaca dokumen dari koleksi `places`, lalu mengubahnya menjadi `PlaceModel`. `NavigationScreen` hanya menerima list `PlaceModel`, sehingga UI cukup memakai `place.name`, `place.category`, `place.latitude`, dan `place.longitude`. Jika struktur database berubah, perubahan dapat difokuskan pada model atau service tanpa mengubah seluruh UI.

Model instruksi navigasi juga penting karena response OSRM memiliki struktur yang kompleks. Data dari OSRM perlu disederhanakan menjadi instruksi yang mudah dipakai UI, misalnya teks instruksi, nama jalan, jarak segmen, durasi segmen, dan tipe manuver. Dengan demikian, screen navigasi tidak perlu membaca JSON OSRM secara langsung.

### 1.2.9 Implementasi Database Firebase

Struktur database utama yang digunakan software adalah sebagai berikut.

```text
users/{uid}
  uid
  email
  name
  phoneNumber
  userType
  createdAt
  updatedAt
  pairingCode
  connectedFamilyUids

users/{uid}/fcmTokens/{tokenId}
  token
  platform
  createdAt
  updatedAt

live_tracking/{uid}
  userId
  lat
  lng
  batteryLevel
  accuracy
  connectionStatus
  gpsStatus
  isNavigating
  isPredicted
  destinationName
  currentTripId
  updatedAt

places/{placeId}
  name
  category
  latitude
  longitude
  description
  createdAt
  updatedAt

pairing_requests/{requestId}
  familyUid
  targetUid
  pairingCode
  status
  createdAt
  updatedAt

sos_alerts/{sosId}
  userId
  familyUids
  lat
  lng
  batteryLevel
  status
  createdAt
  resolvedAt
```

Struktur tersebut menunjukkan bahwa UID pengguna menjadi kunci utama pada sebagian besar data. Pendekatan ini memudahkan validasi akses karena data dapat selalu dikaitkan dengan pengguna Firebase Authentication yang sedang login. Field waktu seperti `createdAt`, `updatedAt`, dan `resolvedAt` digunakan untuk audit, pengurutan data, dan menentukan apakah data masih aktif.

Implementasi database tidak hanya menyimpan data statis, tetapi juga mendukung data real-time. Koleksi `live_tracking` dirancang untuk sering berubah, sehingga field di dalamnya dibuat ringkas dan langsung dapat dipakai oleh UI keluarga. Koleksi `users` menyimpan data profil yang lebih stabil. Subkoleksi `fcmTokens` dipakai karena satu pengguna dapat login dari lebih dari satu perangkat. Koleksi `pairing_requests` dipakai untuk menjaga riwayat permintaan koneksi, sedangkan `sos_alerts` dipakai untuk menandai kejadian darurat yang sedang aktif atau sudah selesai.

Relasi data utama dapat dijelaskan sebagai berikut.

| Relasi | Penjelasan |
| --- | --- |
| Firebase Auth UID ke `users/{uid}` | Setiap akun login memiliki satu dokumen profil aplikasi. |
| `familyUid` ke `targetUid` pada pairing | Menghubungkan akun keluarga dengan akun tunanetra. |
| UID tunanetra ke `live_tracking/{uid}` | Menjadikan UID sebagai kunci status lokasi real-time. |
| UID keluarga ke `users/{uid}/fcmTokens` | Menyimpan token perangkat keluarga untuk notifikasi SOS. |
| `sos_alerts` ke pengguna dan keluarga | Menyimpan konteks kejadian darurat agar dapat ditampilkan pada screen keluarga. |

Pada sisi keamanan, struktur database ini perlu didukung oleh Firestore Rules. Prinsip yang digunakan adalah pengguna hanya dapat membaca atau menulis data miliknya sendiri, sedangkan keluarga hanya dapat membaca data tunanetra yang sudah terhubung melalui pairing. Untuk pengiriman SOS, akses sensitif tidak dilakukan langsung dari client, melainkan melalui Worker.

### 1.2.10 Deklarasi Penggunaan Source Code dan Library

Source code utama aplikasi Teman Arah dibuat oleh tim capstone dalam folder `lib` dan `workers/sos-worker`. Software juga menggunakan library open-source dan layanan pihak ketiga sebagai dependensi, antara lain Flutter, Dart, Firebase SDK, Flutter Map, Geolocator, OSRM, Flutter Blue Plus, Speech To Text, Flutter TTS, dan Cloudflare Worker. Library tersebut tidak diklaim sebagai source code buatan tim, melainkan digunakan sebagai alat bantu implementasi. Daftar library dapat dilihat pada `pubspec.yaml` dan `workers/sos-worker/package.json`, sedangkan sumber pustaka perlu dicantumkan pada daftar pustaka dokumen CD-4.

### 1.2.11 Luaran Implementasi Software

Luaran implementasi software adalah prototype aplikasi mobile Teman Arah yang dapat menjalankan fitur berikut.

1. Registrasi dan login pengguna berbasis email dan password.
2. Verifikasi email sebelum data profil digunakan.
3. Pembagian role pengguna tunanetra dan keluarga.
4. Navigasi pengguna tunanetra berbasis peta, GPS, OSRM, dan instruksi rute.
5. Live tracking lokasi pengguna tunanetra untuk keluarga.
6. Pairing akun keluarga dengan akun tunanetra.
7. Pengelolaan tempat tujuan.
8. Riwayat navigasi dan monitoring.
9. Koneksi Bluetooth untuk smart cane.
10. Pengiriman dan penerimaan notifikasi SOS darurat melalui Worker dan FCM.

Dengan implementasi tersebut, rancangan pada CD-3 telah diwujudkan menjadi software yang memiliki antarmuka pengguna, database, autentikasi, integrasi lokasi, integrasi notifikasi, dan backend pendukung.
