# Flow Halaman Sisi Pengguna TunaNetra

Dokumen ini menjelaskan alur halaman pada sisi pengguna TunaNetra di aplikasi Teman Arah. Fokus flow ini adalah halaman yang digunakan oleh pengguna TunaNetra, mulai dari masuk aplikasi, halaman utama, navigasi, buku panduan, pengaturan, koneksi SmartCane, pairing keluarga, dan SOS.

## Ringkasan Route Pengguna

Route utama sisi pengguna TunaNetra:

- `/tunanetra/home` -> `TunaNetraHomeScreen`
- `/tunanetra/navigation` -> `NavigationScreen`
- `/tunanetra/ebook` -> `EbookScreen`
- `/tunanetra/settings` -> `TunaNetraSettingsScreen`

Subhalaman pengaturan pengguna dibuka menggunakan `MaterialPageRoute`:

- `TunaNetraProfileScreen`
- `PasswordSettingsScreen`
- `ConnectedFamilyAccountsScreen`

## Flow Awal Aplikasi

Flow awal sebelum pengguna masuk ke halaman utama:

```text
Splash Screen
  -> cek status login Firebase
  -> cek tipe akun pengguna
  -> jika akun adalah TunaNetra
       -> Halaman Utama TunaNetra
  -> jika belum login
       -> Login Screen
```

Jika pengguna login sebagai TunaNetra:

```text
Login Screen
  -> validasi email dan password
  -> cek tipe user
  -> Halaman Utama TunaNetra
```

Jika pengguna registrasi sebagai TunaNetra:

```text
Register Screen
  -> pilih tipe akun TunaNetra
  -> isi data akun
  -> simpan data pengguna
  -> kembali ke Login Screen
  -> Login Screen
  -> Halaman Utama TunaNetra
```

## Flow Halaman Utama Pengguna

Halaman utama pengguna berada di `TunaNetraHomeScreen`.

Flow saat halaman utama dibuka:

```text
Halaman Utama TunaNetra
  -> meminta permission inti
       -> lokasi
       -> mikrofon
       -> notifikasi
  -> mulai tracking lokasi pengguna
  -> memuat data cuaca
  -> mengecek status Bluetooth
  -> memuat status SmartCane
  -> mendengarkan request pairing keluarga
  -> TTS membacakan sapaan dan cuaca
```

Elemen utama pada halaman home:

- Status SmartCane
- Status koneksi Bluetooth
- Status baterai SmartCane
- Status lokasi/GPS
- Tombol `Mulai Navigasi`
- Tombol `Kirim SOS`
- Menu `Buku Panduan`
- Menu `Pengaturan`

Flow aksi dari halaman utama:

```text
Halaman Utama
  -> Mulai Navigasi
       -> Halaman Pilih Tempat
       -> Halaman Navigasi Aktif

Halaman Utama
  -> Koneksi / Bluetooth
       -> Scan perangkat SmartCane
       -> Dialog pairing SmartCane
       -> SmartCane terhubung

Halaman Utama
  -> Kirim SOS
       -> kirim alert ke keluarga
       -> tampilkan status pengiriman
       -> TTS membacakan status SOS

Halaman Utama
  -> Buku Panduan
       -> Halaman Buku Panduan

Halaman Utama
  -> Pengaturan
       -> Halaman Pengaturan
```

## Flow Koneksi SmartCane dari Home

Koneksi perangkat SmartCane dimulai dari card/status koneksi pada halaman utama.

```text
Halaman Utama
  -> tap status Koneksi
  -> cek Bluetooth aktif
  -> cek izin Bluetooth dan lokasi
  -> jika Bluetooth mati
       -> coba menyalakan Bluetooth
  -> mulai scan BLE
  -> tampilkan daftar perangkat
  -> pengguna memilih perangkat
  -> tampilkan dialog kode/PIN pairing
  -> hubungkan ke SmartCane
  -> simpan perangkat untuk auto reconnect
  -> status SmartCane menjadi terhubung
```

Jika SmartCane sudah terhubung:

```text
Halaman Utama
  -> tap status Koneksi
  -> disconnect SmartCane
  -> status kembali menjadi belum terhubung
```

## Flow Pairing Keluarga pada Pengguna

Saat akun keluarga mengirim permintaan koneksi, pengguna TunaNetra menerima dialog dari halaman utama.

```text
Halaman Utama
  -> aplikasi mendengarkan pending pairing request
  -> request keluarga masuk
  -> tampil dialog permintaan koneksi
  -> pengguna memilih Terima atau Tolak
```

Jika diterima:

```text
Dialog Pairing
  -> Terima
  -> simpan relasi keluarga
  -> akun keluarga masuk daftar keluarga terhubung
```

Jika ditolak:

```text
Dialog Pairing
  -> Tolak
  -> request ditandai ditolak
  -> tidak ada relasi keluarga baru
```

## Flow Navigasi Pengguna

Halaman navigasi berada di `NavigationScreen`. Di kode saat ini, flow `pilih tempat` dan `navigasi aktif` berada dalam satu screen yang sama.

Flow umum:

```text
Halaman Utama
  -> Mulai Navigasi
  -> NavigationScreen
  -> Halaman Pilih Tempat
  -> pilih tujuan
  -> memulai streaming lokasi
  -> memuat rute
  -> Halaman Navigasi Aktif
  -> pengguna mengikuti instruksi
  -> tiba di tujuan / keluar navigasi
```

### Flow Halaman Pilih Tempat

Saat `NavigationScreen` dibuka dan belum ada `_selectedPlace`, aplikasi menampilkan daftar tempat.

```text
NavigationScreen
  -> load lokasi pengguna
  -> load daftar tempat dari PlacesService
  -> tampilkan Halaman Pilih Tempat
  -> pengguna memilih salah satu tempat
```

Kondisi pada halaman pilih tempat:

```text
Jika tempat sedang dimuat
  -> tampil loading tempat

Jika daftar tempat kosong
  -> tampil empty state

Jika daftar tempat tersedia
  -> tampil list tempat
  -> setiap item berisi nama, kategori, alamat, dan jarak
```

Setelah tempat dipilih:

```text
Pilih Tempat
  -> set selectedPlace
  -> TTS: Memulai navigasi ke [nama tempat]
  -> mulai streaming lokasi
  -> muat rute menuju tempat
  -> tampil map navigasi aktif
```

### Flow Halaman Navigasi Aktif

Saat `_selectedPlace` sudah ada, `NavigationScreen` menampilkan map dan panel navigasi aktif.

```text
Halaman Navigasi Aktif
  -> tampil peta
  -> tampil posisi pengguna
  -> tampil marker tujuan
  -> tampil polyline rute
  -> tampil informasi jarak dan estimasi durasi
  -> tampil instruksi belokan berikutnya
```

Saat navigasi berlangsung:

```text
GPS update
  -> update posisi pengguna
  -> snap posisi ke rute jika memungkinkan
  -> update progress rute
  -> update jarak ke instruksi berikutnya
  -> simpan titik perjalanan ke riwayat
```

Instruksi suara navigasi:

```text
Mendekati instruksi
  -> TTS: Dalam 30 meter, [instruksi]
  -> TTS: Dalam 10 meter, [instruksi]
  -> TTS: Sekarang [instruksi]
```

Jika pengguna keluar jalur:

```text
Posisi keluar jalur
  -> tampil peringatan keluar jalur
  -> TTS: Anda keluar jalur. Menghitung ulang rute
  -> aplikasi mencoba menghitung ulang rute
```

Jika pengguna tiba di tujuan:

```text
Jarak ke tujuan <= threshold
  -> TTS: Anda telah tiba di [nama tempat]
  -> akhiri sesi navigasi
  -> simpan status perjalanan selesai
  -> tutup halaman navigasi aktif
  -> kembali ke Halaman Utama
```

Jika pengguna menekan tombol kembali pada navigasi aktif:

```text
Halaman Navigasi Aktif
  -> tekan tombol kembali
  -> akhiri sesi navigasi
  -> kembali ke halaman sebelumnya
```

## Flow STT pada Navigasi

STT navigasi aktif saat pengguna menekan/menahan tombol voice assistant pada SmartCane.

```text
NavigationScreen
  -> tombol voice assistant SmartCane ditekan
  -> STT mulai mendengarkan
  -> pengguna menyebut perintah
  -> STT berhenti
  -> aplikasi menjalankan aksi
```

Perintah navigasi:

```text
Sebut nama/kategori/alamat tempat
  -> pilih tempat sebagai tujuan
  -> mulai navigasi

Sebut "cek jarak"
  -> TTS membacakan sisa jarak ke tujuan

Sebut "cek waktu"
  -> TTS membacakan estimasi waktu menuju tujuan

Sebut "hentikan"
  -> navigasi dihentikan

Sebut "halaman utama", "beranda", atau "home"
  -> kembali ke halaman utama

Sebut "sos", "darurat", "tolong", atau "bantuan"
  -> kirim SOS
```

## Flow Buku Panduan

Halaman buku panduan berada di `EbookScreen`.

```text
Halaman Utama
  -> Buku Panduan
  -> Halaman Buku Panduan
```

Isi halaman buku panduan:

- Panduan Navigasi
- Koneksi Bluetooth
- Panduan SmartCane
- Tips & Trik
- Panduan Keamanan
- FAQ / Bantuan Umum

Flow interaksi:

```text
Halaman Buku Panduan
  -> tampil daftar panduan
  -> pengguna tap salah satu panduan
  -> tampil snackbar "Membuka [judul panduan]"
```

Catatan: Pada kode saat ini, item buku panduan belum membuka halaman detail khusus. Interaksi masih berupa snackbar.

## Flow Pengaturan

Halaman pengaturan berada di `TunaNetraSettingsScreen`.

```text
Halaman Utama
  -> Pengaturan
  -> Halaman Pengaturan
```

Menu pada halaman pengaturan:

- Profil
- Kata Sandi
- Keluarga
- Keluar

Flow dari halaman pengaturan:

```text
Halaman Pengaturan
  -> Profil
       -> Halaman Profil

Halaman Pengaturan
  -> Kata Sandi
       -> Halaman Kata Sandi

Halaman Pengaturan
  -> Keluarga
       -> Halaman Akun Keluarga

Halaman Pengaturan
  -> Keluar
       -> Dialog konfirmasi logout
       -> Login Screen
```

## Flow Profil

Halaman profil berada di `TunaNetraProfileScreen`.

```text
Halaman Pengaturan
  -> Profil
  -> Halaman Profil
  -> load data pengguna
  -> tampil informasi profil
```

Data yang ditampilkan:

- Nama
- Email
- Nomor telepon
- Tipe akun
- Tanggal bergabung
- Kode penghubung keluarga

Flow ubah profil:

```text
Halaman Profil
  -> Ubah Profil
  -> form edit profil
  -> Simpan Perubahan
  -> update data pengguna
  -> kembali ke mode tampilan profil
```

Flow buat ulang kode penghubung:

```text
Halaman Profil
  -> tekan refresh kode penghubung
  -> dialog konfirmasi
  -> buat kode baru
  -> simpan kode pairing baru
```

## Flow Kata Sandi

Halaman kata sandi berada di `PasswordSettingsScreen`.

```text
Halaman Pengaturan
  -> Kata Sandi
  -> Halaman Kata Sandi
```

Flow ganti sandi:

```text
Halaman Kata Sandi
  -> Ganti Sandi
  -> dialog ganti sandi
  -> isi sandi lama
  -> isi sandi baru
  -> konfirmasi sandi baru
  -> Simpan
  -> update password akun
```

Flow reset sandi:

```text
Halaman Kata Sandi
  -> Atur Ulang Sandi
  -> dialog konfirmasi
  -> kirim tautan reset sandi ke email akun
```

## Flow Akun Keluarga

Halaman akun keluarga berada di `ConnectedFamilyAccountsScreen`.

```text
Halaman Pengaturan
  -> Keluarga
  -> Halaman Akun Keluarga
  -> load daftar keluarga terhubung
```

Kondisi halaman:

```text
Jika masih loading
  -> tampil loading state

Jika belum ada keluarga
  -> tampil empty state

Jika ada keluarga terhubung
  -> tampil daftar kartu keluarga
```

Informasi keluarga yang ditampilkan:

- Nama keluarga
- Email
- Nomor HP
- Tanggal terhubung

Flow putus koneksi keluarga:

```text
Halaman Akun Keluarga
  -> Putuskan Koneksi
  -> dialog konfirmasi
  -> hapus relasi keluarga
  -> daftar keluarga diperbarui
```

## Flow SOS Pengguna

SOS dapat dikirim dari:

- Tombol `Kirim SOS` di halaman utama
- Perintah STT global
- Tombol SOS dari SmartCane
- Perintah STT saat halaman navigasi

Flow SOS:

```text
Trigger SOS
  -> cek cooldown agar tidak terkirim berulang
  -> TTS: Mengirim SOS darurat
  -> SosService.sendSosAlert()
  -> jika berhasil
       -> tampil status berhasil
       -> TTS: Status SOS, berhasil dikirim ke keluarga
  -> jika gagal
       -> tampil status gagal
       -> TTS: Status SOS, gagal dikirim
```

## Flow STT Global Pengguna

STT global dipakai di beberapa halaman pengguna melalui `TunaNetraHomeVoiceCommandMixin`.

Halaman yang memakai listener STT global:

- Buku Panduan
- Pengaturan
- Profil
- Kata Sandi
- Akun Keluarga

Flow STT global:

```text
Halaman dengan listener STT global
  -> tombol voice assistant SmartCane ditekan
  -> STT mulai mendengarkan
  -> pengguna memberi perintah suara
  -> jika perintah dikenal
       -> jalankan aksi
  -> jika tidak dikenal
       -> abaikan atau fallback ke command global
```

Perintah global:

```text
"halaman utama" / "beranda" / "home"
  -> kembali ke Halaman Utama

"sos" / "darurat" / "tolong" / "bantuan"
  -> kirim SOS
```

Perintah khusus pada halaman pengaturan:

```text
"profil" / "profile"
  -> buka Halaman Profil

"kata sandi" / "password" / "sandi"
  -> buka Halaman Kata Sandi

"keluarga" / "akun keluarga"
  -> buka Halaman Akun Keluarga
```

## Perintah STT dan Respons TTS Pengguna

Bagian ini merangkum perintah suara yang digunakan pengguna serta respons suara dari TTS yang relevan.

### 1. Perintah STT Global

Perintah ini dapat digunakan di hampir semua halaman yang mengaktifkan listener STT global.

| Perintah Suara | Fungsi |
| --- | --- |
| "Halaman utama" | Kembali ke halaman utama |
| "Butuh bantuan" | Mengirim SOS darurat |

Contoh variasi perintah yang juga dikenali:

- "Beranda"
- "Home"
- "SOS"
- "Darurat"
- "Tolong"
- "Bantuan"

Contoh respons TTS:

```text
Membuka halaman utama
Kamu sudah berada di halaman utama
Mengirim SOS darurat
Status SOS, berhasil dikirim ke keluarga
Status SOS, gagal dikirim
```

### 2. Perintah STT Halaman Home / Beranda

Perintah ini digunakan saat pengguna berada di halaman utama TunaNetra.

| Perintah Suara | Fungsi |
| --- | --- |
| "Navigasi" | Membuka halaman navigasi atau halaman pilih tempat |
| "Buku panduan" | Membuka halaman buku panduan |
| "Pengaturan" | Membuka halaman pengaturan |
| "Hubungkan SmartCane" | Membuka koneksi SmartCane melalui Bluetooth via BLE |
| "Cek koneksi" | Membacakan status koneksi SmartCane |
| "Cek baterai" | Membacakan baterai SmartCane |
| "Cek SmartCane" | Membacakan status SmartCane |
| "Cek GPS" | Membacakan status GPS/lokasi |
| "Cek cuaca" | Membacakan informasi cuaca |

Contoh respons TTS:

```text
Membuka navigasi
Membuka buku panduan
Membuka pengaturan
SmartCane belum terhubung.
SmartCane terhubung. Baterai 75 persen.
Status GPS aktif.
Cuaca hari ini 30 derajat, kelembapan 70 persen, kecepatan angin 10 kilometer per jam.
Mengirim SOS darurat.
```

Catatan implementasi:

- Perintah pada tabel halaman Home/Beranda sudah dipetakan ke handler STT di halaman utama.
- Perintah "Hubungkan SmartCane" juga menerima variasi "Hubungkan tongkat", "Hubungkan smartcane", dan "Hubungkan smarthcane".
- Perintah status menggunakan pola "Cek", seperti "Cek koneksi", "Cek baterai", "Cek SmartCane", "Cek GPS", dan "Cek cuaca".

## Diagram Flow Utama Pengguna

```text
Splash
  -> Login
  -> Halaman Utama TunaNetra
       -> Koneksi SmartCane
            -> Scan BLE
            -> Pairing perangkat
            -> SmartCane terhubung
       -> Mulai Navigasi
            -> Halaman Pilih Tempat
            -> Halaman Navigasi Aktif
            -> Selesai / Kembali
       -> Kirim SOS
            -> Alert keluarga terkirim
       -> Buku Panduan
            -> Daftar panduan
       -> Pengaturan
            -> Profil
            -> Kata Sandi
            -> Akun Keluarga
            -> Logout
```

## Catatan Implementasi

- `Halaman Pilih Tempat` bukan file screen terpisah. Halaman ini adalah state awal dari `NavigationScreen` saat `_selectedPlace == null`.
- `Halaman Navigasi Aktif` juga bagian dari `NavigationScreen`, muncul setelah pengguna memilih tempat dan `_selectedPlace` terisi.
- Subhalaman `Profil`, `Kata Sandi`, dan `Akun Keluarga` tidak didaftarkan sebagai named route di `AppRoutes`, tetapi dibuka dari halaman pengaturan menggunakan `MaterialPageRoute`.
- Perintah suara pada pengguna sebagian besar dipicu oleh event tombol voice assistant dari SmartCane.
- Flow keluarga seperti dashboard family, monitoring, dan manajemen tempat tidak dibahas detail karena dokumen ini fokus pada sisi pengguna TunaNetra.
