# CD-4 — Pembaruan Dokumen

> **Panduan penggunaan dokumen ini:**
> - ✅ **TIDAK ADA PERUBAHAN** — Pertahankan isi Word aslinya, tidak perlu diubah.
> - 🔄 **GANTI** — Hapus bagian ini di Word, ganti dengan konten tepat di bawah keterangan.
> - 🆕 **TAMBAHKAN** — Tidak ada di Word, tambahkan setelah posisi yang disebutkan.

---

## DESKRIPSI UMUM IMPLEMENTASI

### Perubahan 1 — Kalimat Firebase (backend dan database)

> 🔄 **GANTI** kalimat berikut di Word:
>
> *"Selain itu, sistem menggunakan Firebase sebagai layanan backend dan database untuk mengelola data pengguna, data lokasi, riwayat navigasi serta data sinyal darurat."*
>
> Dengan kalimat berikut:

Selain itu, sistem menggunakan Firebase sebagai layanan backend dan database. Cloud Firestore digunakan untuk menyimpan data pengguna, riwayat navigasi, data pairing, serta data sinyal darurat. Firebase Realtime Database digunakan khusus untuk data live tracking lokasi pengguna karena mendukung sinkronisasi data secara instan ke semua perangkat yang terhubung melalui koneksi WebSocket.

---

### Perubahan 2 — Tambahan SmartCane BLE

> 🆕 **TAMBAHKAN** paragraf berikut setelah kalimat yang menyebut Raspberry Pi sebagai pusat pemrosesan data di paragraf perangkat keras:

Selain komunikasi berbasis jaringan, tongkat pintar juga dilengkapi modul Bluetooth Low Energy (BLE) yang memungkinkan aplikasi mobile terhubung langsung ke perangkat. Melalui koneksi BLE ini, aplikasi dapat menerima data sensor ultrasonik, persentase baterai tongkat, event tombol, serta event deteksi jatuh dari tongkat pintar secara real-time. Data baterai tongkat yang diterima melalui BLE kemudian disertakan dalam informasi live tracking sehingga pengguna keluarga dapat memantau kondisi daya tongkat pintar bersama dengan kondisi daya ponsel pengguna tunanetra.

---

## 1.2.1.1 Autentikasi, Role, dan Verifikasi Email

Autentikasi diimplementasikan menggunakan Firebase Authentication untuk email dan password. Data role tidak disimpan di Firebase Auth, tetapi disimpan di Firestore pada dokumen `users/{uid}`. Pemisahan ini membuat Firebase Auth bertugas menangani identitas login, sedangkan Firestore menangani profil aplikasi seperti nama, nomor telepon, dan role pengguna.

**Tabel 1. Komponen Autentikasi**

| Komponen | Peran |
|---|---|
| LoginScreen | Menerima email dan password pengguna lama |
| RegisterScreen | Menerima data akun baru seperti nama, email, password, nomor telepon, dan role |
| RoleSelectionScreen | Menentukan apakah pengguna mendaftar sebagai tunanetra atau keluarga |
| SplashScreen | Mengecek sesi login dan mengarahkan pengguna ke halaman sesuai role |
| AuthService | Menghubungkan UI dengan Firebase Authentication dan Firestore |
| `users/{uid}` | Menyimpan profil aplikasi dan role pengguna |

Alur implementasi autentikasi terdiri dari empat tahap. Tahap pertama, pengguna mengisi form registrasi dan memilih role. Tahap kedua, aplikasi membuat akun pada Firebase Authentication. Tahap ketiga, aplikasi mengirim email verification agar akun tidak langsung dianggap valid tanpa verifikasi. Tahap keempat, setelah verifikasi berhasil, profil pengguna disimpan ke Firestore.

Pada saat login, aplikasi tidak hanya memvalidasi email dan password, tetapi juga membaca dokumen `users/{uid}` untuk menentukan role dan halaman tujuan.

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

Variabel email, password, name, phoneNumber, dan userType berasal dari form registrasi. `email.toLowerCase().trim()` digunakan untuk menormalkan email agar tidak terjadi duplikasi karena perbedaan huruf kapital atau spasi. Fungsi `createUserWithEmailAndPassword()` membuat akun pada Firebase Authentication. Fungsi `sendEmailVerification()` mengirimkan link verifikasi ke email pengguna. Return user dipakai oleh screen registrasi untuk melanjutkan alur setelah akun berhasil dibuat.

---

> 🔄 **GANTI** code block `saveUserDataToFirestore()` di Word beserta paragraf penjelasannya dengan versi berikut. Perubahan: ditambah field `username`, `emailVerified`, `verificationCompletedAt`; field `updatedAt` dihapus.

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
        'username': name,
        'name': name,
        'phoneNumber': phoneNumber,
        'userType': userType.toString(),
        'createdAt': FieldValue.serverTimestamp(),
        'emailVerified': true,
        'verificationCompletedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true))
      .timeout(const Duration(seconds: 15));
}
```

Fungsi `saveUserDataToFirestore()` menyimpan profil pengguna ke Cloud Firestore. Parameter `uid` menjadi ID dokumen agar data profil selalu terhubung dengan akun Firebase Auth. Field `username` dan `name` keduanya menyimpan nama pengguna untuk kompatibilitas dengan berbagai komponen UI. Field `userType` digunakan untuk menentukan apakah pengguna masuk ke halaman tunanetra atau family. Field `emailVerified` dicatat sebagai `true` karena fungsi ini hanya dipanggil setelah proses verifikasi email selesai. Field `verificationCompletedAt` mencatat waktu selesainya verifikasi menggunakan waktu server Firebase.

---

> 🔄 **GANTI** code block `getUserType()` di Word beserta paragraf penjelasannya dengan versi berikut. Perubahan: sekarang menangani dua format nilai `userType` dan memiliki fallback ke koleksi legacy.

```dart
Future<UserType?> getUserType() async {
  final userId = currentUserId;
  if (userId == null) return null;

  final db = FirebaseFirestore.instance;
  final userDoc = await db.collection('users').doc(userId).get();

  if (userDoc.exists) {
    final userType = userDoc.data()?['userType'] as String?;
    if (userType == 'tunanetra' || userType == 'UserType.tunanetra') {
      return UserType.tunanetra;
    } else if (userType == 'family' || userType == 'UserType.family') {
      return UserType.family;
    }
  }

  // Fallback ke koleksi legacy
  final tunaDoc = await db.collection('tunanetra_users').doc(userId).get();
  if (tunaDoc.exists) return UserType.tunanetra;

  final familyDoc = await db.collection('family_users').doc(userId).get();
  if (familyDoc.exists) return UserType.family;

  return null;
}
```

Fungsi `getUserType()` membaca role pengguna dari Firestore. Pengecekan dilakukan terhadap dua format nilai `userType` yaitu format baru (`'tunanetra'`, `'family'`) dan format lama (`'UserType.tunanetra'`, `'UserType.family'`), untuk menjaga kompatibilitas data yang dibuat di versi aplikasi sebelumnya. Jika dokumen pada koleksi utama `users` tidak ditemukan, fungsi melakukan fallback ke koleksi `tunanetra_users` dan `family_users` yang merupakan koleksi dari versi lama aplikasi. Hasil return dipakai oleh splash screen atau login flow untuk menentukan halaman awal pengguna.

---

Data yang dihasilkan modul autentikasi adalah dokumen profil pengguna. Untuk pengguna tunanetra, data ini menjadi dasar pembuatan pairing code, live tracking, dan riwayat navigasi. Untuk pengguna keluarga, data ini menjadi dasar penerimaan pairing request, penyimpanan FCM token, dan akses monitoring. Dengan demikian, modul autentikasi menjadi fondasi bagi hampir seluruh fitur lain.

Penanganan error dilakukan pada beberapa titik. Jika koneksi lambat, operasi Firebase diberi timeout. Jika user belum login, service mengembalikan null agar screen dapat mengarahkan pengguna kembali ke halaman login. Jika dokumen role tidak ditemukan, aplikasi tidak memaksakan navigasi ke halaman utama karena role adalah penentu hak akses tampilan. Jika email sudah terdaftar namun proses registrasi belum selesai (Firestore kosong dan email belum diverifikasi), sistem secara otomatis menghapus akun lama dan membuat ulang akun baru.

---

## 1.2.1.2 Navigasi

> ✅ **TIDAK ADA PERUBAHAN** — Pertahankan seluruh isi seksi ini di Word.

---

## 1.2.1.3 Live Tracking dan Monitoring Keluarga

> 🔄 **GANTI** paragraf pembuka seksi ini di Word dengan paragraf berikut. Perubahan: menyebut Firebase Realtime Database dan dua layer arsitektur.

Live tracking dan monitoring keluarga dijadikan satu modul karena keduanya berada dalam satu alur data yang sama. Live tracking adalah sisi pengirim data dari aplikasi pengguna tunanetra, sedangkan monitoring keluarga adalah sisi penerima dan penampil data pada aplikasi pengguna keluarga.

Saat pengguna tunanetra berada di home, aplikasi melakukan tracking berkala. Saat navigasi dimulai, aplikasi menggunakan mode akurasi tinggi dan memperbarui data lokasi ke Firebase Realtime Database. Data yang sama kemudian dibaca oleh screen keluarga untuk menampilkan status lokasi, baterai ponsel, baterai SmartCane, tujuan aktif, dan kondisi online/offline.

Implementasi live tracking menggunakan dua layer. Layer pertama adalah `LiveTrackingService` yang mengelola logika bisnis seperti mode tracking, throttle update, dan integrasi data baterai. Layer kedua adalah `RealtimeLiveTrackingService` yang menangani komunikasi langsung ke Firebase Realtime Database pada path `live_tracking/{uid}`.

---

> 🔄 **GANTI** Tabel 3 (Mode Tracking) di Word dengan tabel berikut. Perubahan: tambah field `heading`, `speed`, `smartCaneBatteryLevel`.

**Tabel 3. Mode Live Tracking**

| Mode | Kondisi Aktif | Data yang Ditulis |
|---|---|---|
| Home tracking | Pengguna berada di halaman utama atau tidak bernavigasi | latitude, longitude, accuracy, heading, speed, baterai ponsel, baterai SmartCane, status online, waktu update |
| Navigation tracking | Pengguna menekan mulai navigasi | latitude, longitude, tujuan, status navigasi, GPS status, speed, heading, tripId, baterai ponsel, baterai SmartCane |
| Inactive tracking | GPS tidak tersedia, izin ditolak, atau stream gagal | Semua field lokasi null, status online (offline sesungguhnya ditangani onDisconnect RTDB) |

Firebase Realtime Database digunakan sebagai sumber data monitoring keluarga. Data disimpan pada path `live_tracking/{uid}` menggunakan UID pengguna tunanetra sebagai kunci. Dengan cara ini, screen keluarga cukup memasang listener ke UID yang sudah terhubung melalui pairing.

---

Code block `startHomeLocationTracking()` di Word **tidak perlu diganti**, paragraf penjelasannya saja yang diperbarui.

> 🔄 **GANTI** paragraf penjelasan setelah code block `startHomeLocationTracking()` di Word dengan paragraf berikut.

Variabel `_isStartingHomeTracking` mencegah proses tracking dimulai dua kali. `_homeSubscription` menyimpan stream posisi dari Geolocator. `_homeRefreshTimer` menjalankan pembaruan berkala setiap 10 detik. `startToken` digunakan untuk memastikan proses refresh lama tidak menimpa proses baru. Sebelum stream dimulai, `updateInactiveTracking()` dipanggil untuk langsung menandai pengguna aktif di RTDB sekaligus memicu pendaftaran `onDisconnect` handler agar status offline terdeteksi secara otomatis saat koneksi terputus.

---

> 🔄 **GANTI** code block `startNavigationTracking()` di Word beserta paragraf penjelasannya dengan versi berikut. Perubahan: pakai `AndroidSettings` + `ForegroundNotificationConfig` dan parameter `throttle: true`.

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
      locationSettings: _navigationLocationSettings,
    ).listen(
      (position) {
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
      },
      onError: (error) {
        unawaited(updateInactiveTracking());
        onError?.call(error);
      },
    );
  } finally {
    _isStartingNavigationTracking = false;
  }
}
```

Fungsi `startNavigationTracking()` dipanggil ketika navigasi aktif. Fungsi ini menghentikan home tracking agar tidak ada dua stream lokasi yang berjalan bersamaan. Di Android, `_navigationLocationSettings` menggunakan `AndroidSettings` dengan `LocationAccuracy.bestForNavigation`, `distanceFilter: 1`, dan `ForegroundNotificationConfig` agar lokasi tetap diperbarui meskipun aplikasi berjalan di background. Callback `onPosition` mengirim posisi terbaru ke screen navigasi. Parameter `throttle: true` membatasi penulisan ke RTDB maksimal setiap 2 detik untuk mengurangi konsumsi bandwidth dan baterai.

---

> 🆕 **TAMBAHKAN** code block dan paragraf berikut setelah penjelasan `startNavigationTracking()`. Ini adalah fungsi baru yang belum ada di Word.

```dart
Future<void> updateHomeLocationOnly({required Position position}) async {
  final user = _auth.currentUser;
  if (user == null) return;

  try {
    final batteryLevel = await _battery.batteryLevel;
    final smartCaneBatteryLevel =
        SmartCaneBleService.instance.latestBatteryData?.percentage;

    await _realtimeTracking.setOwnTracking({
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'destinationName': null,
      'heading': position.heading,
      'speed': position.speed,
      'isNavigating': false,
      'currentTripId': null,
      'isPredicted': false,
      'gpsStatus': 'gps_live',
      'connectionStatus': 'online',
      'batteryLevel': batteryLevel,
      'smartCaneBatteryLevel': smartCaneBatteryLevel,
    });
  } catch (_) {}
}
```

Fungsi `updateHomeLocationOnly()` digunakan pada mode home tracking. Field `batteryLevel` berisi persentase baterai ponsel yang dibaca dari package `battery_plus`. Field `smartCaneBatteryLevel` berisi persentase baterai tongkat pintar yang dibaca dari `SmartCaneBleService` melalui koneksi BLE. Jika SmartCane tidak terhubung, nilai ini bernilai null dan tidak ditampilkan pada UI keluarga.

---

> 🔄 **GANTI** paragraf penjelasan setelah code block `updateInactiveTracking()` di Word dengan paragraf berikut. Perubahan utama: penjelasan mengapa `connectionStatus` tetap `'online'`.

Fungsi `updateInactiveTracking()` memperbarui data lokasi ke nilai null ketika GPS tidak tersedia atau tracking dihentikan. Field `lat` dan `lng` dibuat null agar keluarga tidak menganggap lokasi lama sebagai posisi aktif. Field `connectionStatus` tetap bernilai `'online'` karena status offline sesungguhnya ditangani oleh mekanisme `onDisconnect` Firebase Realtime Database. Saat `setOwnTracking()` pertama kali dipanggil, RTDB otomatis mendaftarkan handler yang akan mengubah `connectionStatus` menjadi `'offline'` jika koneksi perangkat ke server terputus secara tiba-tiba, misalnya saat jaringan hilang atau aplikasi paksa ditutup. Field `updatedAt` tetap diperbarui agar UI dapat mengetahui kapan status terakhir ditulis.

---

> 🆕 **TAMBAHKAN** sub-bagian berikut setelah penjelasan `updateInactiveTracking()`. Ini menjelaskan layer RTDB yang belum ada di Word.

```dart
// Implementasi setOwnTracking pada RealtimeLiveTrackingService
Future<void> setOwnTracking(Map<String, dynamic> data) async {
  final user = _auth.currentUser;
  if (user == null) return;

  final ref = _trackingRef(user.uid);
  await ref.update({
    'userId': user.uid,
    ...data,
    'updatedAt': ServerValue.timestamp,
    'clientSentAtMs': DateTime.now().millisecondsSinceEpoch,
  });
  _ensureDisconnectHandler(user.uid);
}
```

`RealtimeLiveTrackingService` adalah layer yang menulis langsung ke Firebase Realtime Database pada path `live_tracking/{userId}`. Field `updatedAt` menggunakan `ServerValue.timestamp` agar waktu update konsisten dengan waktu server. Field `clientSentAtMs` menyimpan waktu lokal perangkat saat data dikirim, digunakan untuk menghitung keterlambatan pengiriman data secara opsional. `_ensureDisconnectHandler()` memastikan handler `onDisconnect` terdaftar sehingga status berubah otomatis menjadi offline jika koneksi internet perangkat terputus.

---

> 🔄 **GANTI** code block `_subscribeToLiveTracking()` di Word beserta paragraf penjelasannya dengan versi berikut. Perubahan: listener sekarang membaca dari Realtime Database, bukan Firestore.

```dart
_subscribeToLiveTracking(uid) {
  final subscription = RealtimeLiveTrackingService.instance
      .watch(uid)
      .listen((data) {
    if (data == null) return;
    setState(() {
      _liveTrackingData[uid] = data;
    });
  });
  _liveTrackingSubscriptions[uid] = subscription;
}
```

Method `watch()` pada `RealtimeLiveTrackingService` membuka stream dari Firebase Realtime Database menggunakan listener `onValue` berbasis WebSocket. Ketika data berubah, variabel `_liveTrackingData` diperbarui menggunakan `setState()` sehingga UI ikut berubah secara real-time. Variabel `_liveTrackingSubscriptions` menyimpan subscription agar dapat dihentikan ketika screen ditutup.

---

Luaran modul live tracking dan monitoring keluarga adalah dashboard pemantauan real-time. Dashboard ini bukan hanya menampilkan data, tetapi juga menjadi penghubung ke fitur lain seperti riwayat navigasi dan event perjalanan, detail anggota, daftar anggota, kelola tempat, dan emergency SOS. Dengan demikian, screen family menjadi pusat kendali bagi pengguna keluarga, sedangkan `LiveTrackingService` menjadi sumber data posisi dari sisi tunanetra.

---

## 1.2.1.4 Riwayat Navigasi dan Event Perjalanan

> ✅ **TIDAK ADA PERUBAHAN** — Pertahankan seluruh isi seksi ini di Word.

---

## 1.2.1.5 Pairing Pengguna Tunanetra dan Keluarga

Pairing digunakan agar akun keluarga hanya dapat memantau pengguna tunanetra yang memang terhubung. Pengguna keluarga memasukkan pairing code, lalu aplikasi memverifikasi kode tersebut dan membuat permintaan pairing. Setelah permintaan diterima, relasi disimpan pada beberapa titik di Firestore untuk mendukung lookup dari berbagai arah.

Pairing code disimpan pada dua lokasi. Pertama, field `pairingCode` di dokumen `users/{uid}` milik pengguna tunanetra. Kedua, dokumen pada koleksi `pairing_codes/{code}` yang berisi referensi ke UID pengguna. Pemisahan ini memungkinkan verifikasi kode dilakukan langsung tanpa perlu query seluruh koleksi users.

**Tabel 5. Status Pairing**

| Status Pairing | Arti |
|---|---|
| pending | Permintaan sudah dibuat tetapi belum disetujui |
| accepted | Hubungan keluarga dan tunanetra sudah aktif |
| rejected | Permintaan ditolak |
| expired | Permintaan tidak direspons dalam batas waktu |

---

> 🔄 **GANTI** code block `createPairingRequest()` di Word beserta paragraf penjelasannya dengan versi berikut. Perubahan: field `targetUid` diganti `tunaNetraUid`, ditambah `familyName`, `familyEmail`, `familyPhone`, `tunaNetraName`.

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

  final tunaNetraUid = targetUser['uid'] as String;

  final familyDoc = await _firestore.collection('users').doc(familyUid).get();
  final familyData = familyDoc.data() ?? {};

  final requestRef = await _firestore.collection('pairing_requests').add({
    'familyUid': familyUid,
    'familyName': familyData['name'] ?? '',
    'familyEmail': familyData['email'] ?? '',
    'familyPhone': familyData['phoneNumber'] ?? '',
    'tunaNetraUid': tunaNetraUid,
    'tunaNetraName': targetUser['name'] ?? '',
    'pairingCode': pairingCode.toUpperCase().trim(),
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  return requestRef.id;
}
```

Fungsi `createPairingRequest()` menerima `familyUid` dan `pairingCode`. Fungsi `verifyPairingCode()` memastikan kode pairing valid dan masih aktif dengan mencari di koleksi `pairing_codes` terlebih dahulu, kemudian fallback ke query koleksi `users`. Jika tidak valid, aplikasi melempar `PairingException` agar UI dapat menampilkan pesan kesalahan. Field `tunaNetraUid` menyimpan UID pengguna tunanetra yang menjadi target pairing. Field `familyName`, `familyEmail`, `familyPhone`, dan `tunaNetraName` disimpan agar tampilan konfirmasi pairing dapat menunjukkan informasi kedua pihak tanpa perlu query tambahan.

---

> 🆕 **TAMBAHKAN** paragraf dan code block berikut setelah penjelasan `createPairingRequest()`. Ini menjelaskan proses saat pairing diterima yang belum ada di Word.

Ketika permintaan pairing diterima oleh pengguna tunanetra, sistem membuat relasi pada tiga titik secara berurutan agar lookup dapat dilakukan dari berbagai arah.

```dart
Future<void> respondToPairingRequest({
  required String requestId,
  required bool accepted,
}) async {
  final requestDoc = await _firestore
      .collection('pairing_requests')
      .doc(requestId)
      .get();
  final data = requestDoc.data() ?? {};

  if (!accepted) {
    await _firestore.collection('pairing_requests').doc(requestId).update({
      'status': 'rejected',
      'respondedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return;
  }

  final familyUid = data['familyUid'] as String;
  final tunaNetraUid = data['tunaNetraUid'] as String;
  final pairingCode = data['pairingCode'] as String;

  await linkFamilyToUser(familyUid, tunaNetraUid, pairingCode);
  await addPairedUser(familyUid, tunaNetraUid);
  await _realtimeTracking.grantFamilyAccess(
    userId: tunaNetraUid,
    familyUid: familyUid,
  );

  await _firestore.collection('pairing_requests').doc(requestId).update({
    'status': 'accepted',
    'respondedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
```

Fungsi `respondToPairingRequest()` menangani respons dari pengguna tunanetra. Jika ditolak, status diubah menjadi `rejected`. Jika diterima, tiga operasi dijalankan secara berurutan: `linkFamilyToUser()` menyimpan data keluarga ke subcollection `family_members` di dokumen tunanetra dan ke array `connectedFamilies`, `addPairedUser()` menambahkan UID tunanetra ke array `pairedUserUids` di dokumen keluarga, dan `grantFamilyAccess()` memberikan izin baca live tracking di Realtime Database pada path `live_tracking_access/{tunaNetraUid}/{familyUid}`.

---

Data pairing yang berhasil digunakan oleh modul monitoring keluarga. Setelah hubungan aktif, UID pengguna tunanetra dapat masuk ke daftar pantauan keluarga. Dari UID tersebut, aplikasi keluarga dapat membaca profil, live tracking, riwayat, dan notifikasi SOS yang relevan. Dengan demikian, pairing menjadi mekanisme otorisasi aplikasi pada level fitur.

---

## 1.2.1.6 SOS Darurat dan Notifikasi

SOS darurat melibatkan dua sisi implementasi. Sisi Flutter mengumpulkan data konteks pengguna, menyimpan alert ke Firestore, lalu memanggil backend Worker untuk setiap keluarga yang terhubung. Sisi backend Worker memverifikasi token Firebase, mengecek relasi family dan tunanetra, mengambil FCM token keluarga, lalu mengirim pesan FCM. Pendekatan ini digunakan agar credential sensitif Firebase tidak disimpan pada aplikasi mobile.

**Tabel 6. Komponen SOS**

| Komponen | Peran |
|---|---|
| SosService | Mengumpulkan data SOS, menyimpan alert, dan mengirim request ke Worker untuk setiap keluarga |
| NotificationService | Mengelola token FCM, izin notifikasi, foreground notification, dan full-screen notification |
| EmergencySosScreen | Menampilkan detail SOS darurat kepada keluarga |
| `workers/sos-worker/src/index.ts` | Backend validasi token dan pengiriman FCM |
| `sos_alerts` | Penyimpanan status alert SOS pada database |
| `users/{familyUid}/fcmTokens` | Sumber token perangkat keluarga |

Code block `handleSendSos()` dan penjelasannya di Word **tidak perlu diganti**.

---

> 🆕 **TAMBAHKAN** code block dan paragraf berikut setelah penjelasan `handleSendSos()`. Ini menjelaskan sisi Flutter yang belum ada di Word.

```dart
Future<SosSendResult> sendSosAlert() async {
  final currentUser = _auth.currentUser;
  final idToken = await currentUser.getIdToken();
  final uid = currentUser.uid;

  final profile = await getTunaNetraProfile(uid);
  final userName = profile['name'] ?? 'Pengguna';
  final liveTracking = await getLiveTracking(uid);

  double? lat = liveTracking?['lat'];
  double? lng = liveTracking?['lng'];
  if (lat == null || lng == null) {
    final fallback = await getCurrentLocationFallback();
    lat ??= fallback?.latitude;
    lng ??= fallback?.longitude;
  }

  final batteryLevel = liveTracking?['batteryLevel'];
  final smartCaneBatteryLevel = liveTracking?['smartCaneBatteryLevel'];
  final currentTripId = liveTracking?['currentTripId'] ?? '';
  final familyUids = await getConnectedFamilyUids(uid);

  final sosId = await saveSosAlert(
    userId: uid,
    userName: userName,
    familyUids: familyUids,
    lat: lat,
    lng: lng,
    batteryLevel: batteryLevel,
    smartCaneBatteryLevel: smartCaneBatteryLevel,
    currentTripId: currentTripId,
  );

  // Kirim notifikasi ke semua keluarga secara paralel
  final deliveryResults = await Future.wait(
    familyUids.map((familyUid) => _sendNotificationToFamily(
      idToken: idToken,
      familyUid: familyUid,
      userId: uid,
      userName: userName,
      lat: lat,
      lng: lng,
      batteryLevel: batteryLevel,
      smartCaneBatteryLevel: smartCaneBatteryLevel,
      currentTripId: currentTripId,
      sosId: sosId,
    )),
  );

  var successCount = 0;
  var failedCount = 0;
  for (final result in deliveryResults) {
    successCount += result[0];
    failedCount += result[1];
  }

  return SosSendResult(
    sosId: sosId,
    successCount: successCount,
    failedCount: failedCount,
  );
}
```

Fungsi `sendSosAlert()` menggabungkan seluruh alur pengiriman SOS dari sisi Flutter. `getLiveTracking()` membaca data posisi terakhir dari Realtime Database. Jika koordinat tidak tersedia, `getCurrentLocationFallback()` meminta posisi GPS langsung dari perangkat. `getConnectedFamilyUids()` mencari semua UID keluarga yang terhubung dari empat sumber secara resilient. `Future.wait()` mengirim notifikasi ke semua keluarga secara paralel sehingga waktu pengiriman tidak bertambah meskipun jumlah keluarga bertambah. Return value `SosSendResult` berisi jumlah pengiriman berhasil dan gagal untuk ditampilkan pada UI.

---

> 🔄 **GANTI** code block `createSosFcmPayload()` di Word beserta paragraf penjelasannya dengan versi berikut. Perubahan: tambah field `smartCaneBatteryLevel` di payload.

```typescript
function createSosFcmPayload(data: SosRequestBody): Record<string, unknown> {
  const title = '\u{1F6A8} SOS Darurat';
  const body = `${data.userName} membutuhkan bantuan segera`;

  return {
    data: {
      type: 'sos',
      title,
      body,
      userId: data.userId,
      familyUid: data.familyUid,
      userName: data.userName,
      lat: data.lat?.toString() ?? '',
      lng: data.lng?.toString() ?? '',
      batteryLevel: data.batteryLevel?.toString() ?? '',
      smartCaneBatteryLevel: data.smartCaneBatteryLevel?.toString() ?? '',
      currentTripId: data.currentTripId ?? '',
      sosId: data.sosId ?? '',
    },
    android: {
      priority: 'HIGH',
    },
  };
}
```

Fungsi `createSosFcmPayload()` membentuk payload FCM. Field `type: 'sos'` digunakan aplikasi Flutter untuk mengenali bahwa pesan tersebut adalah notifikasi darurat. Field `smartCaneBatteryLevel` dikirim agar halaman keluarga dapat menampilkan kondisi baterai tongkat pintar saat SOS terjadi. Field `lat`, `lng`, `batteryLevel`, `currentTripId`, dan `sosId` dikirim sebagai data tambahan agar halaman keluarga dapat membuka detail SOS dengan konteks lokasi dan status pengguna.

---

Keamanan SOS diterapkan pada beberapa lapis. Pertama, endpoint hanya menerima method POST. Kedua, request harus membawa Firebase ID token. Ketiga, Worker memverifikasi token menggunakan public certificate Firebase. Keempat, UID token harus sama dengan `userId` pada body request. Kelima, Worker mengecek bahwa pengguna adalah tunanetra dan keluarga tujuan memang terhubung. Dengan cara ini, pengguna tidak dapat mengirim notifikasi palsu menggunakan UID orang lain.

Luaran modul SOS adalah notifikasi prioritas tinggi dan data alert pada aplikasi keluarga. Pada Android, payload dikirim dengan `priority HIGH` agar notifikasi darurat lebih cepat diproses. Aplikasi Flutter kemudian menampilkan notifikasi full-screen atau membuka `EmergencySosScreen` jika pengguna menekan notifikasi.

---

## 1.2.1.7 Text-to-Speech dan Speech-to-Text

Fitur Text-to-Speech (TTS) dan Speech-to-Text (STT) diimplementasikan untuk mendukung aksesibilitas pengguna tunanetra. TTS digunakan agar aplikasi dapat memberikan respons suara, sedangkan STT digunakan agar pengguna dapat memberi perintah melalui suara.

**Tabel 7. Komponen TTS dan STT**

| Komponen | Peran |
|---|---|
| TTSService | Mengubah teks menjadi suara dengan sistem antrian prioritas dan deduplication |
| STTService | Mengubah suara pengguna menjadi teks perintah, terintegrasi dengan TTSService |
| TunaNetraHomeScreen | Mendengarkan perintah seperti membuka navigasi atau bluetooth |
| NavigationScreen | Mendengarkan perintah tujuan, menghentikan navigasi, dan memberi arahan suara |
| `flutter_tts` | Library untuk text-to-speech |
| `speech_to_text` | Library untuk speech-to-text |

---

> 🔄 **GANTI** paragraf pembuka TTS dan seluruh code block `TTSService` di Word beserta paragraf penjelasannya dengan versi berikut. Perubahan: TTSService sekarang menggunakan priority queue, deduplication, dan interlock dengan STT.

Pada sisi TTS, aplikasi menggunakan sistem priority queue untuk memastikan instruksi penting tidak terlewat dan pesan lama tidak menumpuk. Setiap permintaan bicara memiliki level prioritas, kunci deduplication, dan waktu kedaluwarsa.

> 🆕 **TAMBAHKAN** enum dan penjelasan berikut sebelum code block `TTSService`.

```dart
enum TtsPriority { low, normal, navigation, warning, critical }
```

Lima level prioritas digunakan sesuai konteks. `critical` untuk instruksi keselamatan yang harus diucapkan segera. `warning` untuk peringatan obstacle dari sensor. `navigation` untuk instruksi belok. `normal` untuk konfirmasi aksi pengguna. `low` untuk informasi latar yang dapat dilewati jika ada pesan lebih penting.

---

> 🔄 **GANTI** code block class `TTSService` di Word dengan versi berikut.

```dart
class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  final FlutterTts _tts = FlutterTts();
  final List<_TtsRequest> _queue = [];
  final Map<String, DateTime> _recentlyCompleted = {};

  bool _isInit = false;
  bool _isSttActive = false;
  bool _isProcessing = false;

  static void Function(String text)? onSpeechStartHook;
  static void Function(String text)? onSpeechSendHook;

  Future<void> init() async {
    if (_isInit) return;
    await _tts.setLanguage('id-ID');
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    _tts.setStartHandler(() {
      onSpeechStartHook?.call(_currentRequest?.text ?? '');
    });
    _isInit = true;
  }
}
```

`TTSService` menggunakan pola singleton agar semua bagian aplikasi menggunakan satu antrian terpusat. `_queue` menyimpan daftar permintaan yang menunggu diucapkan. `_recentlyCompleted` menyimpan waktu selesai tiap teks untuk mencegah pengulangan dalam rentang waktu tertentu. `onSpeechStartHook` dan `onSpeechSendHook` adalah hook yang dipasang oleh modul pengukuran response time sistem.

---

> 🔄 **GANTI** code block fungsi `speak()` di Word beserta paragraf penjelasannya dengan versi berikut. Perubahan: tambah parameter `priority`, `deduplicationKey`, `replacementKey`, `maxAge`.

```dart
Future<void> speak(
  String text, {
  TtsPriority priority = TtsPriority.normal,
  String? deduplicationKey,
  String? replacementKey,
  Duration? maxAge,
  Duration duplicateWindow = const Duration(seconds: 2),
}) async {
  final normalizedText = text.trim();
  if (normalizedText.isEmpty) return;

  final request = _TtsRequest(
    text: normalizedText,
    priority: priority,
    deduplicationKey: deduplicationKey ?? normalizedText.toLowerCase(),
    replacementKey: replacementKey,
    expiresAt: DateTime.now().add(maxAge ?? _defaultMaxAge(priority)),
    duplicateWindow: duplicateWindow,
  );

  _discardExpiredRequests();
  _removeReplacedRequests(request);
  if (_isDuplicate(request)) return;

  _queue.add(request);
  if (_shouldInterruptCurrent(request)) {
    await _interruptCurrentSpeech();
  }
  _scheduleProcessing();
}
```

Fungsi `speak()` menerima parameter opsional untuk mengontrol perilaku antrian. `deduplicationKey` mencegah teks yang sama diucapkan dua kali dalam rentang `duplicateWindow`. `replacementKey` memungkinkan pesan baru menggantikan pesan lama yang belum diucapkan dengan kunci yang sama, berguna misalnya saat instruksi obstacle terus diperbarui. `maxAge` menentukan berapa lama request tetap valid sebelum kedaluwarsa dan dibuang. Pesan dengan prioritas `critical` atau `warning` dapat menginterupsi pesan yang sedang diucapkan.

---

> 🆕 **TAMBAHKAN** code block dan paragraf berikut setelah penjelasan `speak()`. Ini menjelaskan mekanisme interlock TTS-STT yang belum ada di Word.

```dart
Future<void> beginSttSession() async {
  _isSttActive = true;
  await _interruptCurrentSpeech();
}

void endSttSession() {
  if (!_isSttActive) return;
  _isSttActive = false;
  _scheduleProcessing();
}
```

`beginSttSession()` dipanggil sebelum mikrofon diaktifkan. TTS langsung dihentikan agar suara aplikasi tidak tertangkap sebagai input pengguna. Jika ada pesan dengan prioritas safety yang sedang diucapkan, pesan tersebut dimasukkan kembali ke antrian agar tidak hilang. `endSttSession()` dipanggil setelah mikrofon selesai sehingga TTS dapat kembali memproses antrian yang tertunda.

---

> 🔄 **GANTI** seluruh code block class `STTService` di Word beserta paragraf penjelasannya dengan versi berikut. Perubahan: singleton, terintegrasi TTS, ucapkan `'Silakan bicara'` sebelum mic aktif, pakai `_stt.cancel()` saat stop.

Pada sisi STT, aplikasi menginisialisasi mikrofon dan engine pengenal suara melalui `SpeechToText`. `STTService` diimplementasikan sebagai singleton dan terintegrasi langsung dengan `TTSService` untuk koordinasi saat mikrofon aktif.

```dart
class STTService {
  static final STTService _instance = STTService._internal();
  factory STTService() => _instance;
  STTService._internal();

  final SpeechToText _stt = SpeechToText();
  bool isListening = false;
  bool _isInitialized = false;

  Future<void> startListening(
    Function(String) onResult, {
    VoidCallback? onNoSpeechDetected,
    Duration pauseFor = const Duration(seconds: 30),
    bool finalResultsOnly = false,
  }) async {
    final ttsService = TTSService();
    bool hadResult = false;

    final available = await init(
      onStatus: (status) {
        isListening = status == 'listening';
        if (status == 'done' || status == 'notListening') {
          if (!hadResult) onNoSpeechDetected?.call();
          ttsService.endSttSession();
        }
      },
    );

    if (!available) {
      debugPrint('STT tidak tersedia');
      return;
    }

    await ttsService.speak('Silakan bicara', priority: TtsPriority.critical);
    await ttsService.beginSttSession();
    isListening = true;

    await _stt.listen(
      localeId: 'id_ID',
      listenFor: const Duration(minutes: 5),
      pauseFor: pauseFor,
      onResult: (result) {
        if (finalResultsOnly && !result.finalResult) return;
        hadResult = true;
        onResult(result.recognizedWords);
      },
    );
  }

  Future<void> stopListening() async {
    try {
      if (_isInitialized) {
        await _stt.cancel();
        isListening = false;
      }
    } finally {
      TTSService().endSttSession();
    }
  }
}
```

`STTService` menggunakan pola singleton. Sebelum mikrofon diaktifkan, TTS mengucapkan `'Silakan bicara'` dengan prioritas `critical` lalu memanggil `beginSttSession()` untuk memastikan TTS berhenti sepenuhnya sebelum mic aktif. Parameter `pauseFor` mengontrol berapa lama sistem menunggu jeda suara sebelum menganggap pengguna selesai berbicara. Parameter `finalResultsOnly` menghindari pemrosesan hasil sementara. `onNoSpeechDetected` dipanggil jika tidak ada suara yang terdeteksi. Pada `stopListening()`, digunakan `_stt.cancel()` (bukan `_stt.stop()`) agar pendengar dibatalkan segera, dan `endSttSession()` selalu dipanggil untuk memastikan TTS dapat kembali aktif.

---

> 🔄 **GANTI** code block `speakSafe()` dan `_handleCommand()` di Word dengan versi berikut. Perubahan: `speakSafe()` tidak lagi diperlukan, panggilan TTS langsung tanpa wrapper.

```dart
void _handleCommand(String command) async {
  await _sttService.stopListening();
  if (command.contains('bluetooth')) {
    await TTSService().speak('Membuka pengaturan bluetooth');
    Navigator.pushNamed(context, AppRoutes.tunaNetraBluetooth);
  } else if (command.contains('navigasi')) {
    await TTSService().speak('Membuka navigasi');
    Navigator.pushNamed(context, AppRoutes.tunaNetraNavigation);
  } else {
    await TTSService().speak('Perintah tidak dikenali');
    _startListening();
  }
}
```

Fungsi `_handleCommand()` memeriksa isi teks perintah. Koordinasi antara TTS dan STT tidak lagi membutuhkan variabel `_isSpeaking` di layar karena sudah ditangani secara otomatis oleh mekanisme `beginSttSession`/`endSttSession` di dalam service. Pemanggilan `TTSService().speak()` langsung dilakukan tanpa wrapper `speakSafe()`.

---

Luaran modul TTS dan STT adalah interaksi suara dua arah. Pengguna dapat mengontrol sebagian fitur tanpa harus melihat layar, sedangkan aplikasi memberikan konfirmasi dan instruksi secara verbal dengan jaminan tidak ada pesan yang saling bertumpuk atau terlewat.

---

## 1.2.1.8 Database Firebase

> 🔄 **GANTI** seluruh Tabel 8 di Word dengan dua tabel berikut. Perubahan: dipisah menjadi tabel Firestore dan tabel Realtime Database.

**Tabel 8a. Struktur Cloud Firestore**

| Koleksi / Dokumen | Isi |
|---|---|
| `users/{uid}` | Profil pengguna: uid, email, username, name, phoneNumber, userType, pairingCode, emailVerified, createdAt |
| `users/{uid}/fcmTokens/{tokenId}` | Token FCM perangkat untuk pengiriman notifikasi |
| `users/{uid}/family_members/{familyUid}` | Data keluarga yang terhubung dengan akun tunanetra |
| `pairing_codes/{code}` | Indeks kode pairing aktif: userId, code, status, createdAt |
| `pairing_requests/{requestId}` | Permintaan pairing: familyUid, familyName, tunaNetraUid, tunaNetraName, pairingCode, status |
| `navigation_history/{tripId}` | Riwayat perjalanan: userId, origin, destination, polyline, status, durasi |
| `navigation_history/{tripId}/route_points` | Titik posisi selama perjalanan |
| `navigation_history/{tripId}/events` | Event perjalanan: mulai, keluar rute, SOS, selesai |
| `sos_alerts/{sosId}` | Alert SOS: userId, userName, familyUids (array), lat, lng, batteryLevel, smartCaneBatteryLevel, status |
| `places/{placeId}` | Daftar tempat tujuan navigasi |

**Tabel 8b. Struktur Firebase Realtime Database**

| Path | Isi |
|---|---|
| `live_tracking/{userId}` | Data lokasi real-time: lat, lng, accuracy, heading, speed, isNavigating, gpsStatus, connectionStatus, batteryLevel, smartCaneBatteryLevel, updatedAt, clientSentAtMs |
| `live_tracking_access/{userId}/{familyUid}` | Nilai `true` jika keluarga memiliki izin membaca data live tracking tunanetra |

---

> 🔄 **GANTI** tabel relasi di Word dengan tabel berikut. Perubahan: tambah baris `live_tracking_access` dan `smartCaneBatteryLevel`.

**Tabel 8c. Relasi Antar Data**

| Relasi | Penjelasan |
|---|---|
| Firebase Auth UID → `users/{uid}` | Setiap akun login memiliki satu dokumen profil aplikasi |
| `familyUid` → `tunaNetraUid` pada pairing | Menghubungkan akun keluarga dengan akun tunanetra |
| UID tunanetra → `live_tracking/{uid}` di RTDB | Kunci status lokasi real-time |
| UID keluarga → `users/{uid}/fcmTokens` | Token perangkat keluarga untuk notifikasi SOS |
| `sos_alerts` → `familyUids` (array) | Menghubungkan satu kejadian darurat ke semua keluarga terhubung |
| `live_tracking_access/{userId}/{familyUid}` | Mengontrol izin baca RTDB per pasang tunanetra-keluarga |

---

> 🔄 **GANTI** paragraf penjelasan database di Word dengan paragraf berikut. Perubahan: tambah penjelasan mengapa dua database digunakan.

Sistem menggunakan dua layanan database Firebase secara bersamaan. Cloud Firestore digunakan untuk data persisten seperti profil pengguna, riwayat navigasi, pairing, dan SOS alerts karena mendukung query kompleks dan struktur data bertingkat. Firebase Realtime Database digunakan untuk data live tracking karena menggunakan koneksi WebSocket persisten sehingga perubahan data tersebar ke semua listener dalam milidetik tanpa polling. Pemilihan ini juga memungkinkan mekanisme `onDisconnect` pada RTDB yang secara otomatis mengubah status pengguna menjadi offline ketika koneksi internet terputus.

Pada sisi keamanan, struktur database ini didukung oleh Firestore Security Rules dan Realtime Database Rules. Prinsip yang digunakan adalah pengguna hanya dapat membaca atau menulis data miliknya sendiri. Keluarga hanya dapat membaca data live tracking tunanetra yang sudah terhubung, dikontrol melalui entry di `live_tracking_access`. Untuk pengiriman SOS, akses sensitif tidak dilakukan langsung dari client melainkan melalui Cloudflare Worker.

---

## 1.2.1.9 Koneksi SmartCane BLE

> 🆕 **TAMBAHKAN** seluruh seksi berikut setelah seksi 1.2.1.8 di Word.

`SmartCane BLE` adalah modul yang menghubungkan aplikasi mobile dengan tongkat pintar melalui Bluetooth Low Energy (BLE). Koneksi ini memungkinkan aplikasi menerima data sensor, data baterai, event tombol, dan event jatuh dari tongkat pintar secara real-time.

**Tabel 9. Komponen SmartCane BLE**

| Komponen | Peran |
|---|---|
| SmartCaneBleService | Singleton service untuk koneksi BLE, menerima data sensor, baterai, dan event dari tongkat pintar |
| `flutter_blue_plus` | Library BLE untuk scan, koneksi, dan subscribe karakteristik |
| `SmartCaneSensorData` | Model data sensor: jarak obstacle dari tiga arah |
| `SmartCaneBatteryData` | Model data baterai tongkat: persentase dan tegangan |
| `SmartCaneButtonEvent` | Model event tombol: tekan singkat dan tahan |
| `SmartCaneFallEvent` | Model event jatuh yang dideteksi oleh IMU tongkat pintar |

Identifikasi tongkat pintar dilakukan melalui UUID layanan dan karakteristik BLE yang spesifik.

```dart
static final Guid _smartCaneServiceUuid = Guid(
  '0000a001-0000-1000-8000-00805f9b34fb',
);
static final Guid _sensorCharacteristicUuid = Guid(
  '0000a002-0000-1000-8000-00805f9b34fb',
);
static final Guid _imuCharacteristicUuid = Guid(
  '0000a004-0000-1000-8000-00805f9b34fb',
);
```

`_smartCaneServiceUuid` adalah UUID layanan utama yang digunakan untuk mengidentifikasi tongkat pintar saat scan BLE. `_sensorCharacteristicUuid` adalah karakteristik yang mengirimkan data sensor ultrasonik dan baterai secara periodik. `_imuCharacteristicUuid` adalah karakteristik yang mengirimkan data IMU termasuk event jatuh dan event tombol.

Data dari `SmartCaneBleService` digunakan oleh beberapa modul lain. `LiveTrackingService` membaca `latestBatteryData?.percentage` untuk menyertakan status baterai tongkat pada data live tracking yang dikirim ke keluarga. `FallDetectionService` subscribe ke `fallEventStream` untuk mendeteksi event jatuh dari tongkat. Modul obstacle detection membaca `latestSensorData` untuk menghasilkan peringatan suara melalui TTS kepada pengguna tunanetra.

Informasi terakhir yang diterima dari tongkat tersedia melalui dua getter: `latestSensorData` untuk data obstacle terbaru dan `latestBatteryData` untuk data baterai terbaru. Data ini bersifat opsional dan bernilai null jika tongkat tidak terhubung, sehingga semua modul yang menggunakannya menangani kondisi null dengan aman tanpa mengganggu fungsi utama aplikasi.
