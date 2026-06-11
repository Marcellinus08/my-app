# Manajemen TTS Global Teman Arah

## 1. Tujuan

Teman Arah dapat menerima beberapa informasi suara dalam waktu yang
berdekatan, seperti:

- peringatan bahaya dari Smart Cane;
- status hati-hati dan jalur aman;
- instruksi navigasi;
- status pengiriman SOS;
- respons perintah suara;
- informasi koneksi, baterai, dan halaman;
- pembacaan Buku Panduan.

Semua informasi tersebut dikelola oleh satu `TTSService` global agar suara
tidak saling bertabrakan dan informasi keselamatan selalu didahulukan.

File utama:

```text
lib/services/tts_service.dart
```

---

## 2. Tingkat Prioritas

TTS menggunakan lima tingkat prioritas:

| Prioritas | Penggunaan |
| --- | --- |
| `critical` | Bahaya Smart Cane, SOS, dan tiba di tujuan |
| `warning` | Hati-hati, jalur kembali aman, dan keluar rute |
| `navigation` | Panduan jarak, area belok, dan instruksi rute |
| `normal` | Status koneksi, baterai, halaman, dan respons biasa |
| `low` | Pembacaan panjang seperti Buku Panduan |

Urutan pemrosesan:

```text
critical > warning > navigation > normal > low
```

---

## 3. Aturan Interupsi

### Critical

Pesan `critical` langsung memotong suara yang sedang berjalan.

Contoh:

```text
Bahaya, orang terdeteksi sebagai hambatan. Berhenti.
Mengirim SOS darurat.
Anda telah tiba di tujuan.
```

### Warning

Pesan `warning` memotong pesan `navigation`, `normal`, atau `low`.

Pesan `warning` tidak memotong pesan `critical` yang sedang berjalan.

Contoh:

```text
Hati-hati, kursi terdeteksi sebagai hambatan. Pindah ke kanan.
Anda keluar jalur. Menghitung ulang rute.
Jalur sudah aman. Silakan lanjutkan perjalanan.
```

### Informasi Biasa

Pesan `navigation`, `normal`, dan `low` menunggu pesan yang lebih penting
selesai dibacakan.

---

## 4. Antrean Global

Seluruh halaman menggunakan instance `TTSService` yang sama.

```dart
final TTSService ttsService = TTSService();
```

Permintaan suara dimasukkan ke satu antrean global:

```dart
await ttsService.speak(
  'Jalur sudah aman. Silakan lanjutkan perjalanan.',
  priority: TtsPriority.warning,
);
```

Pesan dalam antrean dipilih berdasarkan:

1. tingkat prioritas tertinggi;
2. urutan waktu masuk jika prioritasnya sama.

---

## 5. Deduplikasi Pesan

`deduplicationKey` digunakan untuk mencegah pesan yang sama masuk ke
antrean berulang kali.

```dart
await ttsService.speak(
  'Anda keluar jalur. Menghitung ulang rute.',
  priority: TtsPriority.warning,
  deduplicationKey: 'navigation-off-route',
);
```

Pesan tidak dimasukkan kembali jika:

- sedang dibacakan;
- sudah menunggu di antrean;
- baru saja selesai dibacakan dalam jendela deduplikasi.

Jika `deduplicationKey` tidak diberikan, teks pesan yang sudah
dinormalisasi digunakan sebagai kunci.

---

## 6. Penggantian Pesan Lama

`replacementKey` digunakan ketika hanya informasi terbaru yang masih
relevan.

Semua panduan navigasi menggunakan:

```text
navigation-guidance
```

Contoh:

```dart
await ttsService.speak(
  'Dalam 10 meter, belok kanan.',
  priority: TtsPriority.navigation,
  replacementKey: 'navigation-guidance',
  maxAge: const Duration(seconds: 8),
);
```

Jika instruksi baru masuk sebelum instruksi lama dibacakan, instruksi lama
dihapus dari antrean.

Saat navigasi berakhir, semua panduan rute dibatalkan dengan:

```dart
await ttsService.cancelByReplacementKey('navigation-guidance');
```

---

## 7. Masa Berlaku Pesan

Setiap pesan memiliki batas waktu agar informasi lama tidak dibacakan
setelah konteksnya berubah.

Masa berlaku default:

| Prioritas | Masa berlaku |
| --- | --- |
| `low` | 8 detik |
| `normal` | 12 detik |
| `navigation` | 8 detik |
| `warning` | 15 detik |
| `critical` | 30 detik |

Masa berlaku dapat ditentukan secara khusus:

```dart
await ttsService.speak(
  'Anda sudah masuk area belok kanan.',
  priority: TtsPriority.navigation,
  maxAge: const Duration(seconds: 6),
);
```

Pesan yang sudah kedaluwarsa dibuang sebelum dibacakan.

---

## 8. Hubungan dengan STT

Ketika STT mulai mendengarkan:

1. suara TTS yang sedang berjalan dihentikan;
2. pesan biasa dan navigasi yang menunggu dibuang;
3. permintaan TTS biasa yang baru muncul tidak dimasukkan ke antrean;
4. pesan `warning` dan `critical` tetap disimpan;
5. peringatan keselamatan yang terpotong dimasukkan kembali ke antrean.

Setelah STT selesai:

- antrean TTS diproses kembali;
- peringatan keselamatan yang belum kedaluwarsa dibacakan berdasarkan
  prioritasnya.

Alur:

```text
TTS berjalan
    |
STT diaktifkan
    |
TTS berhenti
    |
Peringatan keselamatan disimpan
    |
STT selesai
    |
Peringatan dibacakan
```

---

## 9. Smart Cane

Peringatan Smart Cane menggabungkan:

- tingkat bahaya;
- nama objek jika tersedia;
- hasil keputusan arah jika tersedia.

Contoh:

```text
Hati-hati, kursi terdeteksi sebagai hambatan. Pindah ke kanan.
Bahaya, orang terdeteksi sebagai hambatan. Berhenti.
```

Pemetaan keputusan:

| Data Smart Cane | Hasil UI dan TTS |
| --- | --- |
| `maju` | Maju |
| `kiri`, `belok kiri`, `left` | Pindah ke kiri |
| `kanan`, `belok kanan`, `right` | Pindah ke kanan |
| `stop`, `berhenti` | Berhenti |

Saat kondisi aman stabil selama sekitar 1,5 detik:

```text
Jalur sudah aman. Silakan lanjutkan perjalanan.
```

---

## 10. Navigasi

Instruksi navigasi menggunakan prioritas `navigation`.

Contoh:

```text
Dalam 30 meter, belok kanan.
Dalam 20 meter, belok kanan.
Dalam 10 meter, belok kanan.
Anda sudah masuk area belok kanan.
Belok berhasil. Lanjutkan perjalanan.
```

Seluruh instruksi tersebut memakai `replacementKey` yang sama agar
instruksi terbaru menggantikan instruksi lama.

Peringatan keluar rute menggunakan prioritas `warning`:

```text
Anda keluar jalur. Menghitung ulang rute.
```

Informasi tiba menggunakan prioritas `critical`:

```text
Anda telah tiba di tujuan.
```

---

## 11. SOS

Status SOS menggunakan prioritas `critical`.

Contoh:

```text
Mengirim SOS darurat.
SOS berhasil dikirim ke keluarga.
SOS gagal dikirim.
```

Pesan SOS dapat memotong seluruh informasi lain karena berhubungan dengan
keselamatan pengguna.

---

## 12. Buku Panduan

Pembacaan Buku Panduan menggunakan:

```dart
priority: TtsPriority.low
replacementKey: 'ebook-guide'
```

Ketika pengguna menghentikan pembacaan, aplikasi hanya membatalkan suara
Buku Panduan:

```dart
await ttsService.cancelByReplacementKey('ebook-guide');
```

Peringatan Smart Cane dan SOS tidak ikut dibatalkan.

---

## 13. Contoh Integrasi

### Pesan biasa

```dart
await TTSService().speak(
  'SmartCane siap digunakan.',
  priority: TtsPriority.normal,
);
```

### Panduan navigasi

```dart
await TTSService().speak(
  'Dalam 10 meter, belok kiri.',
  priority: TtsPriority.navigation,
  deduplicationKey: 'navigation-cue-2-10',
  replacementKey: 'navigation-guidance',
  maxAge: const Duration(seconds: 8),
);
```

### Peringatan

```dart
await TTSService().speak(
  'Hati-hati, kursi terdeteksi sebagai hambatan. Pindah ke kanan.',
  priority: TtsPriority.warning,
  replacementKey: 'smart-cane-hazard',
);
```

### Bahaya

```dart
await TTSService().speak(
  'Bahaya, orang terdeteksi sebagai hambatan. Berhenti.',
  priority: TtsPriority.critical,
  replacementKey: 'smart-cane-hazard',
);
```

---

## 14. Panduan Pengembangan

Saat menambahkan TTS baru:

1. Gunakan `TTSService()` global.
2. Tentukan prioritas berdasarkan dampaknya terhadap keselamatan.
3. Berikan `deduplicationKey` untuk pesan yang dapat muncul berulang.
4. Berikan `replacementKey` jika hanya pesan terbaru yang relevan.
5. Tentukan `maxAge` untuk informasi yang cepat berubah.
6. Jangan menggunakan `stop()` global untuk menghentikan suara satu fitur.
7. Gunakan `cancelByReplacementKey()` agar fitur lain tidak terganggu.
8. Hindari membuat antrean TTS lokal baru pada halaman.

---

## 15. Verifikasi

Layanan utama yang perlu diperiksa:

```text
lib/services/tts_service.dart
lib/services/stt_service.dart
lib/services/smart_cane_status_notification_service.dart
lib/screens/tunanetra/navigation_screen.dart
lib/screens/tunanetra/tunanetra_home_screen.dart
lib/screens/tunanetra/ebook_screen.dart
```

Perintah pemeriksaan:

```bash
dart analyze lib/services/tts_service.dart
flutter test test/services/smart_cane_sensor_data_test.dart
```

Skenario pengujian perangkat:

1. Jalankan instruksi navigasi, lalu munculkan status bahaya.
2. Pastikan bahaya langsung memotong instruksi navigasi.
3. Aktifkan STT ketika peringatan bahaya sedang berjalan.
4. Pastikan peringatan dibacakan kembali setelah STT selesai.
5. Kirim beberapa instruksi navigasi dalam waktu berdekatan.
6. Pastikan hanya instruksi terbaru yang dibacakan.
7. Buka Buku Panduan lalu hentikan pembacaan.
8. Pastikan peringatan Smart Cane tetap dapat dibacakan.
9. Ulangi data sensor yang sama.
10. Pastikan TTS tidak melakukan spam.

