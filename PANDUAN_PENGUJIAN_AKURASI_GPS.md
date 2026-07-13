# Panduan Pengujian Akurasi GPS (Indoor vs Outdoor)

Dokumen ini adalah panduan pengumpulan dan analisis data akurasi GPS untuk aplikasi Teman Arah, tanpa perlu mengubah kode aplikasi utama yang sudah berjalan benar.

## Prinsip dasar

Tool pengujian ditaruh terpisah di `lib/testing/` sebagai entry point Dart mandiri (`main()` sendiri). Tool ini **tidak diimpor oleh `lib/main.dart`** dan tidak mengubah file aplikasi yang sudah ada — hanya memakai dependency yang sudah ada di `pubspec.yaml` (`firebase_core`, `firebase_auth`, `firebase_database`). Dijalankan terpisah lewat:

```
flutter run -t lib/testing/gps_accuracy_test_screen.dart
```

Tool ini **read-only** — tidak menulis data apa pun ke database. Ia hanya mendengarkan (subscribe) data yang sudah ditulis aplikasi utama ke path `live_tracking/{userId}` di Firebase Realtime Database (path yang sama dipakai layar live tracking keluarga, lihat `lib/services/realtime_live_tracking_service.dart`). Supaya ada data untuk dibaca, **aplikasi Teman Arah utama harus aktif** (navigasi atau home tracking berjalan) di HP dengan akun yang sama saat sesi uji berlangsung.

## Cara menjalankan tool

### Kebutuhan
- Akun Teman Arah yang sudah terdaftar (email + password) untuk login di tool uji.
- Dua aplikasi berjalan bersamaan saat sesi uji: **Teman Arah** (app utama, sumber data GPS) dan **GPS Accuracy Test** (tool ini, pembaca & pembanding data).
- **Wajib 2 device/instance berbeda — tidak bisa 1 HP untuk keduanya.** Tool uji dan aplikasi utama berbagi `applicationId` Android yang sama (`com.example.my_app`, lihat `android/app/build.gradle.kts`), karena keduanya cuma entry point Dart berbeda dalam satu project yang sama. Kalau tool uji di-`flutter run` di HP yang sama dengan app utama, Android akan **menimpa (overwrite)** instalasi app utama, bukan menambah app baru — jadi keduanya tidak bisa berjalan bersamaan di satu HP.

  Opsi kombinasi device yang valid:
  - **HP + HP kedua** — paling ideal, terutama kalau titik ground truth ada di dalam gedung dan sinyal HP kedua juga perlu dites.
  - **HP + Android Emulator** di laptop (lewat Android Studio/AVD) — emulator dianggap Flutter sebagai device Android biasa, semua plugin Firebase jalan normal di situ.
  - **HP + Chrome/browser di laptop** — jalankan tool lewat `flutter run -d chrome -t lib/testing/gps_accuracy_test_screen.dart`. Ini opsi paling ringan karena tidak butuh device Android kedua sama sekali.
  - ⚠️ **Windows desktop (`flutter run -d windows`) TIDAK BISA** dipakai untuk tool ini — plugin `firebase_database` (dipakai untuk baca `live_tracking/{userId}`) tidak punya implementasi native Windows (cek `pubspec.yaml` plugin `firebase_database`, hanya terdaftar untuk android/ios/macos/web). `firebase_core` dan `firebase_auth` sebenarnya support Windows, tapi `firebase_database` tidak, jadi build akan gagal.

  Device kedua (emulator/browser) ini **cuma jadi "layar pembaca/pembanding"** — dia tidak perlu GPS akurat sendiri, tidak perlu ikut dibawa ke lokasi uji, karena dia cuma mendengarkan data yang dikirim HP pertama lewat Firebase lalu menghitung selisihnya terhadap ground truth. Yang penting device kedua login dengan **akun (UID) yang sama** dengan HP pertama.

### Langkah menjalankan
1. **HP (device sumber GPS)**: pastikan app Teman Arah utama (build APK biasa) ter-install dan bisa login seperti biasa. Kalau mau develop/run lewat kabel USB, kabel cuma dipakai untuk install & attach debugger — setelah aplikasi jalan, **kabel boleh dicabut** karena aplikasi berjalan mandiri di device dan berkomunikasi dengan Firebase lewat internet, bukan lewat kabel. Yang penting HP tetap online (WiFi/data seluler) selama sesi uji.
2. **Device kedua (tool uji)**: dari root project, jalankan salah satu:
   ```
   flutter run -t lib/testing/gps_accuracy_test_screen.dart          # HP/emulator Android kedua
   flutter run -d chrome -t lib/testing/gps_accuracy_test_screen.dart # Chrome di laptop
   ```
3. Di layar login tool, masukkan email + password akun yang **sama persis** dengan yang dipakai login di app Teman Arah utama (HP).
4. Di HP (app Teman Arah utama), login dengan akun yang sama, lalu buka layar yang mengaktifkan tracking (navigasi ke suatu tujuan, atau cukup biarkan home tracking aktif di layar utama tunanetra) — ini yang bikin `live_tracking/{userId}` terus terupdate. Tool uji **tidak melakukan pengecekan otomatis** apakah langkah ini sudah dilakukan — makanya ada indikator status di layar tool (lihat bagian berikutnya) untuk memastikan data memang masuk.

## Prosedur pengambilan data di lab

**Prinsip inti: 1 sesi logging = 1 titik fisik yang tetap (statis), bukan sambil berjalan.** HP (device sumber GPS) harus **diam** di titik ground truth selama sesi berlangsung — dipegang diam atau ditaruh di meja/lantai di titik itu, jangan dipindah-pindah. Kalau HP ikut bergerak, `errorMeters` yang tercatat akan bercampur antara error GPS asli dan jarak perpindahan fisik, sehingga tidak murni mengukur akurasi GPS lagi. (Pengujian akurasi *saat bergerak/navigasi* butuh metodologi lain — belum didukung tool ini, lihat catatan di bagian Roadmap.)

1. **Tentukan ground truth** tiap lokasi uji — pin koordinat presisi di Google Maps (mode satelit, zoom maksimal) atau ukur manual dari denah, sebelum sesi dimulai.
2. Pastikan app Teman Arah utama sedang aktif tracking (lihat langkah 4 di bagian sebelumnya) dan HP diam di titik ground truth tersebut.
3. Di tool uji, isi:
   - **Tempat** — lokasi umum/gedung (contoh: `TULT Lantai 1`, `Mall XYZ Lt 2`)
   - **Spesifik lokasi** — titik detailnya (contoh: `dekat jendela`, `tengah ruangan`, `dekat lift`). Tempat dan spesifik lokasi diisi terpisah (bukan digabung jadi satu string) supaya gampang di-filter/di-grup saat rekap.
   - Kondisi: Indoor / Outdoor
   - Koordinat ground truth (lat, lng)
4. Tekan **Start Logging** di tool uji. Perhatikan **indikator status** yang muncul di bawah tombol:
   - Abu-abu "Menunggu data pertama..." — normal di detik-detik awal.
   - Hijau "Update terakhir: X detik lalu" — data masuk lancar, app utama di HP terkonfirmasi aktif tracking.
   - **Merah ⚠** "Belum ada data masuk" / "Tidak ada data baru" (muncul setelah >15 detik tanpa update) — berarti app utama di HP belum aktif tracking, akunnya beda, atau HP offline. Cek HP sebelum lanjut, jangan biarkan sesi jalan tanpa data masuk.
5. Biarkan logging jalan **3–5 menit** di titik yang sama supaya cukup sample untuk hitung rata-rata, standar deviasi, dan drift. Tiap sample bukan dari tempat berbeda — semuanya pembacaan GPS berulang dari **satu titik fisik yang sama**, karena chip GPS secara alami menghasilkan angka sedikit berbeda tiap pembacaan meski device diam total (noise sinyal, multipath, geometri satelit yang berubah). Variasi antar-sample inilah yang mencerminkan stabilitas GPS di titik itu. Tool menerima update setiap kali `live_tracking/{userId}` berubah (± setiap 1-2 detik saat navigasi aktif, ± setiap 10 detik saat home tracking).
6. Tekan **Stop Logging**, lalu simpan hasilnya lewat salah satu:
   - **Download CSV ke file** — menyimpan file `.csv` ke folder dokumen aplikasi di device tool (nama file otomatis dari tempat + spesifik lokasi + timestamp), atau
   - **Copy hasil sebagai CSV ke clipboard** — tempel langsung ke Excel/Google Sheets (buat 1 baris header di spreadsheet lalu tempel data setiap sesi di bawahnya).
7. Untuk titik uji berikutnya (termasuk yang masih di gedung/lantai sama tapi beda spot, misal pindah dari "dekat jendela" ke "tengah ruangan"): pindah ke titik baru, ubah **Spesifik lokasi** dan **koordinat ground truth** sesuai titik baru itu, ulangi dari langkah 2. Tidak perlu restart tool — cukup isi form baru setelah menekan Stop.

## Kondisi yang sebaiknya diuji

**Outdoor** (dari kondisi terbaik ke terburuk untuk GPS):
- Lapangan/taman terbuka (baseline, langit bersih 360°)
- Trotoar dekat gedung tinggi (urban canyon — efek multipath/pantulan sinyal)
- Di bawah pohon rindang (efek kanopi daun)
- Dekat tembok/gedung tapi masih di luar (semi-terbuka)
- Kondisi diam vs berjalan (drift saat statis vs noise saat bergerak)

**Indoor** (dari termudah ke tersulit):
- Dekat jendela kaca (indoor terbaik, masih sering dapat sinyal)
- Tengah ruangan, jauh dari jendela
- Ruangan berlapis di gedung beton, lantai 2 ke atas
- Basement/parkir bawah tanah (kasus terburuk — `accuracy` bisa sangat besar atau fix hilang)
- Dekat struktur logam (lift, tangga besi — uji interferensi)

## Data yang dicatat per sample

Kolom CSV (baik dari Copy to clipboard maupun Download CSV ke file):

- `tempat` — lokasi umum yang diisi manual (contoh: `TULT Lantai 1`)
- `spesifikLokasi` — titik detail yang diisi manual (contoh: `dekat jendela`)
- `condition` — `indoor` atau `outdoor`
- `timestamp`
- `lat`, `lng`
- `accuracy` — estimasi error dari sensor GPS (dilaporkan Android/iOS)
- `errorMeters` — jarak aktual ke ground truth, dihitung dari formula Haversine antara `(lat, lng)` sample dan koordinat ground truth yang diisi di awal sesi

## Analisis

Tool sudah menghitung `mean`, `std dev`, `min`, `max` error secara langsung di layar selama sesi berjalan. Untuk analisis lebih lanjut:
- Kumpulkan CSV dari tiap sesi (lewat Download ke file atau Copy ke clipboard) ke satu spreadsheet (kolom: `tempat, spesifikLokasi, condition, timestamp, lat, lng, accuracy, errorMeters`).
- Hitung tambahan: persentase sample dengan error di bawah threshold tertentu (misal < 5m, < 10m).
- Bandingkan metrik ini antar kondisi indoor vs outdoor, dan antar sub-kondisi dalam `spesifikLokasi` (dekat jendela vs tengah ruangan, dst) — karena `tempat` dan `spesifikLokasi` terpisah, gampang di-pivot/di-group by salah satunya di spreadsheet.

## Roadmap (belum diimplementasikan)

- **Uji akurasi saat bergerak/navigasi**: prosedur di atas hanya berlaku untuk titik statis. Untuk menguji akurasi GPS saat pengguna berjalan mengikuti rute, dibutuhkan pendekatan berbeda — misalnya membandingkan tiap sample ke titik terdekat di rute yang direncanakan (bukan ke satu ground truth tetap), atau mencatat beberapa waypoint ground truth di sepanjang rute. Belum dibangun di tool ini.
