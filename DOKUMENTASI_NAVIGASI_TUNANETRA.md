# 📱 Dokumentasi Sistem Navigasi untuk Pengguna Tuna Netra

**Versi**: 1.0  
**Tanggal**: Mei 2026  
**Bahasa**: Indonesia

---

## 📋 Daftar Isi

1. [Pengenalan](#pengenalan)
2. [Fitur Utama](#fitur-utama)
3. [Panduan Penggunaan](#panduan-penggunaan)
4. [Navigasi GPS](#navigasi-gps)
5. [Konektivitas & Perangkat](#konektivitas--perangkat)
6. [Panduan Aksesibilitas](#panduan-aksesibilitas)
7. [Pengaturan & Kustomisasi](#pengaturan--kustomisasi)
8. [Troubleshooting](#troubleshooting)
9. [FAQ](#faq)

---

## 🎯 Pengenalan

Aplikasi ini adalah sistem navigasi dan monitoring khusus yang dirancang untuk membantu pengguna tuna netra (pengguna dengan kehilangan atau gangguan penglihatan) bergerak dengan lebih mandiri dan aman. Aplikasi ini mengintegrasikan teknologi GPS real-time, pembacaan instruksi turn-by-turn, dan konektivitas Bluetooth dengan perangkat smartcane.

### Tujuan Aplikasi

- ✅ Memberikan navigasi akurat untuk perjalanan sehari-hari
- ✅ Monitoring kesehatan dan keselamatan pengguna melalui smartcane
- ✅ Memudahkan komunikasi dengan keluarga dan kontak darurat
- ✅ Menyediakan akses ke konten digital (eBook)
- ✅ Interface yang fully accessible untuk pembaca layar

---

## ⭐ Fitur Utama

### 1. **Navigasi GPS Turn-by-Turn**
- Panduan langkah demi langkah menuju destinasi
- Deteksi lokasi real-time dengan akurasi tinggi
- Peringatan ketika pengguna keluar dari rute
- Kalkulasi otomatis rute terdekat

### 2. **Smartcane Monitoring**
- Konektivitas Bluetooth dengan smartcane
- Monitoring status baterai perangkat
- Deteksi hambatan otomatis melalui sensor
- Integrasi dengan sistem navigasi

### 3. **Panduan Instruksi Verbal**
- Pembacaan instruksi dalam bahasa Indonesia
- Notifikasi audio untuk pergantian arah
- Informasi jarak hingga destinasi
- Daftar rute alternatif yang tersedia

### 4. **Manajemen Tempat Favorit**
- Simpan lokasi tempat yang sering dikunjungi
- Akses cepat ke rute favorit
- Kategori tempat (rumah, kantor, toko, dll)

### 5. **Kontak Darurat**
- Daftar keluarga dan kontak penting
- Tombol SOS untuk situasi darurat
- Sharing lokasi real-time dengan keluarga

### 6. **Konten Digital (eBook)**
- Perpustakaan digital yang accessible
- Fitur pembacaan dengan screen reader
- Bookmark dan notes untuk referensi

---

## 📖 Panduan Penggunaan

### Layar Utama (Home Screen)

#### Akses Menu Utama
1. Buka aplikasi dengan tap pada ikon aplikasi
2. Anda akan masuk ke **Home Screen** dengan sambutan personal ("Halo [Nama Anda]")

#### Elemen-Elemen Utama di Home Screen
- **Greeting Message**: Ucapan selamat datang personal
- **Weather Information**: Informasi cuaca lokasi Anda
- **Smartcane Status**: Status koneksi dan baterai smartcane
- **Navigation Menu**: Akses ke semua fitur utama

### Menu Navigasi Utama

```
┌─────────────────────────────────┐
│      HOME SCREEN MENU           │
├─────────────────────────────────┤
│ 1. 🗺️  NAVIGASI                 │
│    → Mulai navigasi ke tempat   │
│                                 │
│ 2. 📡 KONEKSI BLUETOOTH         │
│    → Hubungkan smartcane        │
│                                 │
│ 3. 📚 E-BOOK                    │
│    → Baca konten digital        │
│                                 │
│ 4. 📱 MONITORING SMARTCANE      │
│    → Cek status perangkat       │
│                                 │
│ 5. 👨‍👩‍👧 KONTAK KELUARGA          │
│    → Kelola kontak & SOS        │
│                                 │
│ 6. ⚙️  PENGATURAN               │
│    → Konfigurasi aplikasi       │
└─────────────────────────────────┘
```

---

## 🗺️ Navigasi GPS

### Memulai Navigasi

#### Langkah 1: Masuk ke Menu Navigasi
1. Dari Home Screen, pilih **"🗺️ NAVIGASI"**
2. Sistem akan meminta izin lokasi (jika pertama kali)
3. Tap **"Izinkan"** untuk mengaktifkan GPS

#### Langkah 2: Memilih Destinasi
Anda memiliki 3 opsi:

**Opsi A: Dari Daftar Tempat Tersimpan**
- Sistem akan menampilkan list tempat favorit
- Swipe ke atas/bawah untuk memilih tempat
- Tap destinasi yang ingin dituju
- Sistem akan otomatis mencari rute

**Opsi B: Dari Rekomendasi Terdekat**
- Kategori: Rumah Sakit, Masjid, Toko, Kantor, dll
- Pilih kategori yang ingin dicari
- Tap untuk melihat lokasi terdekat

**Opsi C: Pencarian Manual**
- Gunakan tombol "Cari Tempat"
- Ketik nama atau alamat destinasi
- Pilih dari hasil pencarian

#### Langkah 3: Konfirmasi Rute
Sebelum memulai navigasi:
- **Jarak**: Jarak total ke destinasi
- **Perkiraan Waktu**: Waktu estimasi perjalanan (berdasarkan kecepatan jalan kaki ~1.4 m/s)
- **Tipe Rute**: Pejalan kaki (default)
- Tap **"Mulai Navigasi"** untuk memulai

### Selama Perjalanan

#### Interface Navigasi Aktif

```
┌──────────────────────────────────┐
│   📍 NAVIGASI AKTIF              │
├──────────────────────────────────┤
│ Destinasi: [Nama Tempat]         │
│                                  │
│ Instruksi Saat Ini:              │
│ "Lurus 50 meter, kemudian        │
│  belok kanan"                    │
│                                  │
│ Sisa Jarak: 234 meter            │
│ Sisa Waktu: 2 menit 45 detik     │
│                                  │
│ Status Rute:                     │
│ ✓ Anda berada di rute            │
│ ✓ Lokasi ter-update              │
│                                  │
│ [ PAUSE ]  [ STOP ]  [ DETAIL ]  │
└──────────────────────────────────┘
```

#### Pembacaan Instruksi

Sistem akan **secara otomatis membaca** instruksi ketika:
- ✓ Anda memulai navigasi
- ✓ Jarak sisa berkurang (~50 meter sebelum pergantian arah)
- ✓ Anda keluar dari rute
- ✓ Anda mencapai poin checkpoint
- ✓ Lokasi GPS ter-update (setiap 3-5 detik)

#### Gesture & Kontrol

| Gesture | Fungsi |
|---------|--------|
| **Double Tap** | Baca ulang instruksi saat ini |
| **Swipe Kiri** | Instruksi berikutnya |
| **Swipe Kanan** | Instruksi sebelumnya |
| **3-Finger Tap** | Pause navigasi |
| **Volume Atas** | Naikkan volume pembacaan |
| **Volume Bawah** | Turunkan volume pembacaan |

### Situasi Khusus Selama Perjalanan

#### 1. Keluar dari Rute (Off-Route)
- **Indikasi**: Notifikasi audio berbunyi
- **Durasi Konfirmasi**: 2 detik
- **Aksi Otomatis**: Sistem akan mencari rute alternatif
- **Notifikasi**: "Anda telah keluar dari rute. Mencari rute baru..."
- **Cooldown**: 20 detik sebelum dapat melakukan reroute lagi

#### 2. GPS Signal Lemah
- **Indikasi**: "Sinyal GPS lemah"
- **Aksi**: Sistem menggunakan prediksi berbasis accelerometer
- **Durasi Prediksi**: Maksimal 18 meter dari posisi terakhir
- **Notifikasi**: "Menggunakan perkiraan lokasi"

#### 3. Tiba di Destinasi
- **Indikasi Audio**: Notifikasi khusus "Anda telah sampai di destinasi"
- **Pilihan**: 
  - Simpan waktu & rute ke history
  - Cari destinasi baru
  - Kembali ke Home

### Riwayat Navigasi

Setiap perjalanan dicatat dengan:
- ✓ Tanggal & waktu
- ✓ Tempat asal & destinasi
- ✓ Jarak total
- ✓ Waktu tempuh
- ✓ Kecepatan rata-rata

---

## 📡 Konektivitas & Perangkat

### Koneksi Bluetooth dengan Smartcane

#### Setup Awal (First Time)

1. **Nyalakan Smartcane**
   - Tekan tombol power pada smartcane
   - Tunggu 3-5 detik hingga LED menyala biru

2. **Aktifkan Bluetooth pada Ponsel**
   - Masuk ke Pengaturan Sistem
   - Aktifkan Bluetooth

3. **Buka Menu Koneksi Bluetooth**
   - Dari Home Screen → Pilih "📡 KONEKSI BLUETOOTH"

4. **Scan Perangkat**
   - Tap "Scan Perangkat"
   - Sistem akan mencari smartcane terdekat
   - Tunggu maksimal 10 detik

5. **Pasang Perangkat**
   - Pilih smartcane dari daftar yang muncul
   - Tap untuk melakukan pairing
   - Sistem akan meminta PIN (default: 0000)

6. **Konfirmasi Koneksi**
   - Tunggu pesan "Smartcane berhasil terhubung"
   - Lampu LED pada smartcane akan berubah hijau

#### Monitoring Smartcane

Setelah terhubung, Anda dapat:

| Fitur | Deskripsi |
|-------|-----------|
| **Status Baterai** | Persentase baterai smartcane (real-time) |
| **Status Sensor** | Fungsi sensor ultra-sonik (aktif/tidak aktif) |
| **Last Connection** | Waktu koneksi terakhir |
| **Signal Strength** | Kekuatan sinyal Bluetooth (1-5 bar) |
| **Firmware Version** | Versi software smartcane |

#### Troubleshooting Koneksi

**Masalah**: Smartcane tidak terdeteksi
- ✓ Pastikan smartcane dalam mode pairing
- ✓ Jarak ponsel & smartcane < 10 meter
- ✓ Tidak ada perangkat lain yang mengganggu

**Masalah**: Koneksi sering terputus
- ✓ Jarak ponsel & smartcane terlalu jauh (>20 meter)
- ✓ Baterai smartcane rendah
- ✓ Interference dari WiFi/mikro gelombang

**Masalah**: PIN pairing salah
- ✓ Coba PIN: 0000, 1234, atau 12345
- ✓ Reset smartcane dan coba lagi

---

## ♿ Panduan Aksesibilitas

### Screen Reader Support

Aplikasi ini fully compatible dengan:
- **Android**: TalkBack (built-in)
- **Voice Assistant**: Google Assistant, OK Google

#### Mengaktifkan TalkBack
1. Buka Pengaturan Sistem
2. Masuk ke "Aksesibilitas"
3. Pilih "TalkBack"
4. Tap toggle untuk mengaktifkan
5. Ikuti tutorial awal

#### Gesture TalkBack

| Gesture | Fungsi |
|---------|--------|
| **Single Tap** | Membaca elemen |
| **Double Tap** | Mengaktifkan elemen |
| **Swipe Kanan** | Elemen berikutnya |
| **Swipe Kiri** | Elemen sebelumnya |
| **Swipe Bawah** | Kembali ke menu |
| **Swipe Atas** | Lanjut ke layar berikutnya |

### Text-to-Speech (TTS)

Semua teks dalam aplikasi dapat dibaca secara otomatis:
- **Bahasa**: Indonesia (Bahasa Indonesia - Indonesia)
- **Kecepatan**: Dapat disesuaikan (0.8x - 2.0x)
- **Pitch**: Normal, Tinggi, Rendah
- **Volume**: Independen dari volume media

#### Konfigurasi TTS

Dari **Menu Pengaturan → Aksesibilitas**:
1. Buka "Pengaturan Text-to-Speech"
2. Pilih bahasa: "Bahasa Indonesia"
3. Atur kecepatan pembacaan
4. Atur pitch (tinggi nada)
5. Test audio

### Kontras & Ukuran Font

#### Meningkatkan Kontras
- Menu → Pengaturan → Tampilan
- Aktifkan "Mode Kontras Tinggi"
- Pilih tema: Gelap (rekomendasi)

#### Mengubah Ukuran Font
- Menu → Pengaturan → Tampilan
- Ukuran font: Kecil / Normal / Besar / Sangat Besar
- Ukuran heading juga akan menyesuaikan

### Keyboard Navigation

Navigasi penuh menggunakan keyboard:
- **Tab**: Pindah ke elemen berikutnya
- **Shift + Tab**: Pindah ke elemen sebelumnya
- **Enter/Spasi**: Activate tombol
- **Esc**: Batal/Kembali
- **Arrow Keys**: Navigasi list atau menu

---

## ⚙️ Pengaturan & Kustomisasi

### Menu Pengaturan

Akses melalui: **Home Screen → ⚙️ Pengaturan**

#### Kategori Pengaturan

```
┌─────────────────────────────────┐
│      MENU PENGATURAN            │
├─────────────────────────────────┤
│ 📊 Profil Pengguna              │
│    • Nama, Email, Foto          │
│    • Kontak Darurat             │
│                                 │
│ 🌍 Navigasi                     │
│    • Mode navigasi              │
│    • Notifikasi rute            │
│    • Jarak warning off-route    │
│                                 │
│ 🔊 Audio & Notifikasi           │
│    • Kecepatan TTS              │
│    • Pitch pembacaan            │
│    • Volume notifikasi          │
│                                 │
│ 🎨 Tampilan                     │
│    • Tema (Terang/Gelap)        │
│    • Ukuran font                │
│    • Kontras tinggi             │
│                                 │
│ 🔐 Privasi & Keamanan          │
│    • Sharing lokasi             │
│    • Riwayat aktivitas          │
│    • Data storage               │
│                                 │
│ 📱 Perangkat & Konektivitas    │
│    • Bluetooth settings         │
│    • WiFi settings              │
│    • GPS settings               │
│                                 │
│ 📞 Kontak Darurat              │
│    • Tambah/edit kontak         │
│    • Tombol SOS                 │
│                                 │
│ ℹ️  Tentang                     │
│    • Versi aplikasi             │
│    • Kredit                     │
│    • Lisensi                    │
└─────────────────────────────────┘
```

### Konfigurasi Navigasi

#### Mode Navigasi

**1. Mode Normal (Default)**
- Instruksi penuh untuk setiap pergantian arah
- Notifikasi every 3-5 detik
- Ideal untuk pengguna pertama kali

**2. Mode Minimal**
- Notifikasi hanya pada pergantian arah penting
- Update lokasi less frequent
- Hemat baterai

#### Notifikasi Rute

| Setting | Default | Deskripsi |
|---------|---------|-----------|
| Off-Route Threshold | 35 meter | Jarak max sebelum warning |
| Off-Route Confirm Duration | 2 detik | Waktu tunggu sebelum reroute |
| Reroute Cooldown | 20 detik | Cooldown antar reroute |
| Route Trim Threshold | 12 meter | Jarak snap to route |
| Route Snap Threshold | 20 meter | Jarak guidance snap |

### Konfigurasi Audio

#### Text-to-Speech

- **Bahasa**: Bahasa Indonesia (id-ID)
- **Kecepatan**: 0.8x - 2.0x (default: 1.0x)
- **Pitch**: 0.8 - 1.2 (default: 1.0)
- **Volume**: 0 - 100% (default: 80%)

#### Notifikasi Audio

- **Sound notification**: On/Off
- **Vibration**: On/Off
- **Sound type**: Bell, Chime, Alert
- **Max volume warning**: On/Off

---

## 🆘 Troubleshooting

### Masalah GPS & Navigasi

#### GPS Tidak Akurat
```
GEJALA:
- Lokasi melompat-lompat
- Petunjuk arah tidak sesuai
- Sering off-route

SOLUSI:
1. Pastikan GPS active & "Precise location" enabled
2. Buka lokasi area outdoor (sinyal satelit lebih baik)
3. Buka aplikasi Google Maps 5 menit untuk kalibrasi
4. Restart aplikasi & coba ulang
5. Jika masih tidak baik, tunggu GPS warm-up
```

#### Rute Tidak Ditemukan
```
GEJALA:
- "Rute tidak ditemukan"
- "Server error"

SOLUSI:
1. Periksa koneksi internet (WiFi/Mobile data)
2. Pastikan lokasi origin & destination valid
3. Coba ubah destinasi
4. Jika masih error, lapor ke developer
```

#### Instruksi Tidak Dibaca
```
GEJALA:
- Tidak ada suara pembacaan
- TTS tidak berfungsi

SOLUSI:
1. Cek volume ponsel (bukan media volume)
2. Buka Pengaturan → Aksesibilitas → TTS
3. Pilih engine TTS yang benar
4. Cek bahasa → pilih "Bahasa Indonesia"
5. Test dengan tombol "Test Audio"
```

### Masalah Bluetooth & Smartcane

#### Smartcane Tidak Terhubung
```
GEJALA:
- Status: "Tidak terhubung"
- Smartcane tidak ditemukan

SOLUSI:
1. Nyalakan Bluetooth di ponsel
2. Nyalakan smartcane (tekan 3 detik)
3. Tunggu LED biru berkedip (mode pairing)
4. Tap "Scan" di aplikasi
5. Jika tidak ada, coba reset smartcane
```

#### Koneksi Sering Putus
```
GEJALA:
- Status: "Terhubung → Terputus"
- Connection unstable

SOLUSI:
1. Jarak ponsel & smartcane < 10 meter
2. Hapus obstacle antara ponsel & smartcane
3. Restart Bluetooth ponsel
4. Unpair & pair ulang perangkat
5. Update firmware smartcane jika ada
```

### Masalah Performa & Baterai

#### Aplikasi Lambat / Lag
```
GEJALA:
- Interface responsif lambat
- Freeze sesaat

SOLUSI:
1. Tutup aplikasi lain yang berjalan
2. Clear cache: Pengaturan → Apps → Clear Cache
3. Restart ponsel
4. Uninstall & reinstall aplikasi
```

#### Baterai Cepat Habis
```
GEJALA:
- Battery drain 10% per jam
- Aktivitas background tinggi

SOLUSI:
1. Matikan GPS ketika tidak navigasi
2. Kurangi frekuensi update lokasi
3. Matikan Bluetooth jika tidak menggunakan smartcane
4. Gunakan mode "Minimal" navigasi
5. Charge baterai secara teratur
```

---

## ❓ FAQ (Pertanyaan yang Sering Diajukan)

### Q1: Berapa akurasi GPS aplikasi ini?
**A**: Akurasi tergantung kondisi lingkungan:
- **Area terbuka** (outdoor): ±5-10 meter
- **Area terbatas** (urban): ±10-20 meter
- **Dalam bangunan**: ±20-50 meter (tidak rekomendasi)

### Q2: Apakah bisa navigasi tanpa internet?
**A**: Tidak. Aplikasi membutuhkan internet untuk:
- Fetch data lokasi
- Kalkulasi rute (OSRM)
- Update instruksi
Namun GPS tidak perlu internet (hanya satelit).

### Q3: Bagaimana cara menambah tempat favorit?
**A**: 
1. Dari Home → Pilih "Navigasi"
2. Cari tempat yang diinginkan
3. Tap tempat
4. Pilih "Simpan ke Favorit"
5. Berikan nama & kategori

### Q4: Dapatkah saya berbagi lokasi dengan keluarga?
**A**: Ya. Melalui menu "Kontak Keluarga":
1. Tambahkan kontak keluarga
2. Pilih kontak yang ingin berbagi lokasi
3. Aktifkan "Live Location Sharing"
4. Keluarga dapat melihat lokasi Anda real-time

### Q5: Apa yang harus dilakukan jika ada keadaan darurat?
**A**: 
1. Tekan **tombol SOS** (home screen)
2. Pilih kontak darurat
3. Sistem akan:
   - Mengirim lokasi real-time
   - Mengirim pesan otomatis
   - Mengaktifkan audio recording

### Q6: Berapa lama baterai smartcane bertahan?
**A**: Sekitar 8-10 jam penggunaan normal. Tergantung:
- Intensitas sensor ultra-sonik
- Frekuensi Bluetooth communication
- Setting battery mode

### Q7: Apakah ada fitur offline maps?
**A**: Saat ini belum. Rencana untuk versi mendatang:
- Download maps area
- Navigasi offline
- Update otomatis maps

### Q8: Bagaimana cara melapor bug atau error?
**A**: Hubungi developer melalui:
- Email: support@myapp.com
- Menu → Tentang → "Laporkan Bug"
- Sertakan screenshot & deskripsi error

### Q9: Apakah data saya aman?
**A**: Ya, data dienkripsi:
- Koneksi: HTTPS (SSL/TLS)
- Database: Firebase encrypted
- Lokasi: Privacy mode tersedia

### Q10: Bagaimana update aplikasi?
**A**: Melalui Play Store:
1. Buka Play Store
2. Cari "My App"
3. Tap "Update" jika tersedia
4. Tunggu download & install selesai

---

## 📞 Dukungan & Kontak

### Tim Dukungan

| Saluran | Waktu | Response |
|---------|-------|----------|
| **Email** | Setiap hari | < 24 jam |
| **Chat** | 09:00 - 18:00 WIB | < 30 menit |
| **Phone** | 08:00 - 17:00 WIB | Immediate |

### Informasi Kontak
- **Email Support**: support@myapp.com
- **Chat Support**: in-app chat feature
- **Hotline**: +62-XXX-XXXXXX
- **Website**: www.myapp.com/support
- **Social Media**: @myappofficial

---

## 🔄 Changelog & Update History

### Versi 1.0 (Mei 2026)
- ✅ Fitur navigasi GPS dasar
- ✅ Integrasi Bluetooth smartcane
- ✅ Screen reader support (TalkBack)
- ✅ Turn-by-turn guidance
- ✅ Emergency contacts
- ✅ eBook reader

### Versi Mendatang (Roadmap)
- 🔄 Offline maps support
- 🔄 Voice commands
- 🔄 AR-based navigation (audio)
- 🔄 Community safety alerts
- 🔄 Machine learning untuk route optimization

---

## 📄 Lisensi & Disclaimer

**Lisensi**: MIT License  
**Developer**: MyApp Development Team

### Disclaimer
Aplikasi ini disediakan "sebagaimana adanya". Developer tidak bertanggung jawab atas:
- Kehilangan data
- Kerusakan perangkat
- Kesalahan navigasi yang menyebabkan kecelakaan
- Keterlambatan atau kegagalan GPS
- Loss of privacy

Pengguna menggunakan aplikasi ini dengan risiko sendiri.

---

## 📚 Referensi & Sumber Daya

### Teknologi yang Digunakan
- **Flutter**: Framework development
- **Firebase**: Backend & database
- **OSRM**: Open Street Routing Machine (routing engine)
- **OpenStreetMap**: Base maps
- **Geolocator**: GPS positioning
- **Sensors Plus**: Accelerometer & gyroscope

### Library Aksesibilitas
- **Android TalkBack**: Screen reader built-in
- **Flutter Semantics**: Semantic accessibility
- **Text-to-Speech Engine**: Google TTS

### Dokumentasi Referensi
- [Flutter Accessibility](https://flutter.dev/docs/accessibility-and-localization/accessibility)
- [Android Accessibility](https://developer.android.com/guide/topics/ui/accessibility)
- [OSRM API](https://project-osrm.org/)
- [OpenStreetMap](https://www.openstreetmap.org/)

---

## 🙏 Penutup

Terima kasih telah menggunakan aplikasi ini. Kami berkomitmen untuk terus meningkatkan pengalaman Anda. Feedback dan saran Anda sangat berharga untuk pengembangan aplikasi lebih lanjut.

**Selamat menggunakan, dan perjalanan yang aman!**

---

*Dokumentasi ini ditulis dalam Bahasa Indonesia untuk memastikan pemahaman yang mudah bagi pengguna tuna netra Indonesia. Update dokumentasi akan dilakukan seiring dengan pelepasan versi baru aplikasi.*

**Terakhir Diupdate**: Mei 2026  
**Versi Dokumentasi**: 1.0
