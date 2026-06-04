# Fitur STT dan TTS - Sisi Pengguna TunaNetra

## Ringkasan
Dokumentasi ini menjelaskan penggunaan Speech-to-Text (STT) dan Text-to-Speech (TTS) pada sisi pengguna TunaNetra. Kedua fitur ini digunakan untuk membuat aplikasi dapat menerima perintah suara pengguna dan memberikan panduan suara balik.

## Lokasi Implementasi Utama
- `lib/services/stt_service.dart`
- `lib/services/tts_service.dart`
- `lib/screens/tunanetra/tunanetra_home_screen.dart`
- `lib/screens/tunanetra/navigation_screen.dart`

## Tujuan Fitur
Fitur STT dan TTS bertujuan untuk:
- membantu pengguna TunaNetra mengoperasikan aplikasi melalui suara
- memberikan informasi awal seperti sapaan dan cuaca
- membuka fitur tertentu melalui perintah suara
- memandu pengguna saat navigasi
- memberi peringatan suara ketika keluar jalur
- memberi informasi suara ketika pengguna sampai tujuan

## Speech-to-Text (STT)

### Service STT
STT diimplementasikan pada `STTService` dengan package `speech_to_text`.

Konfigurasi utama:
- menggunakan locale `id_ID`
- menjalankan `initialize()` sebelum mulai mendengar
- menggunakan `listen()` untuk menangkap suara
- mengembalikan hasil melalui callback `onResult(result.recognizedWords)`

Method utama:
- `init()` untuk inisialisasi STT
- `startListening(Function(String) onResult)` untuk mulai mendengarkan suara
- `stopListening()` untuk menghentikan STT

## STT pada Halaman Utama TunaNetra
File: `lib/screens/tunanetra/tunanetra_home_screen.dart`

STT aktif setelah aplikasi selesai membacakan sapaan awal dan informasi cuaca. Setelah TTS selesai berbicara, aplikasi memanggil `_startListening()`.

### Kondisi STT Aktif
STT mulai aktif pada kondisi berikut:
- setelah sapaan awal dan informasi cuaca selesai dibacakan
- setelah pengguna kembali ke halaman utama dari halaman lain
- setelah perintah tidak dikenali dan sistem selesai memberi umpan balik suara

### Perintah Suara yang Dikenali
Perintah diproses jika hasil STT memiliki panjang minimal 15 karakter. Teks hasil STT diubah menjadi huruf kecil, lalu dicek menggunakan `contains()`.

Perintah yang dikenali:
- mengandung `bluetooth` untuk membuka pengaturan Bluetooth
- mengandung `navigasi` untuk membuka halaman navigasi
- mengandung `ebook` atau `buku panduan` untuk membuka buku panduan
- mengandung `tongkat pintar` untuk membuka pengaturan smartcane
- mengandung `pengaturan` untuk membuka halaman pengaturan

Jika perintah tidak dikenali, aplikasi membacakan "Perintah tidak dikenali", lalu STT diaktifkan kembali.

## STT pada Halaman Navigasi
File: `lib/screens/tunanetra/navigation_screen.dart`

STT aktif saat halaman navigasi selesai dibuka. Aplikasi terlebih dahulu membacakan instruksi agar pengguna menyebutkan tujuan, lalu memanggil `_startVoiceNavigation()`.

### Kondisi STT Aktif
STT mulai aktif pada kondisi berikut:
- setelah halaman navigasi dibuka
- setelah TTS membacakan "Halaman navigasi dibuka. Silahkan pilih tempat tujuan anda"

### Perintah Suara yang Dikenali
Perintah suara pada halaman navigasi digunakan untuk memilih tujuan dan menghentikan navigasi.

Perintah yang dikenali:
- jika ucapan mengandung nama tempat dari daftar `_places`, aplikasi memilih tempat tersebut sebagai tujuan
- jika ucapan mengandung `cek jarak`, aplikasi membacakan sisa jarak ke tujuan
- jika ucapan mengandung `cek waktu`, aplikasi membacakan estimasi waktu menuju tujuan
- jika ucapan mengandung `hentikan`, aplikasi menghentikan navigasi dan kembali ke halaman sebelumnya

Saat nama tempat dikenali:
- STT dihentikan
- `_selectedPlace` diisi dengan tempat yang sesuai
- location streaming dimulai
- rute dimuat
- TTS membacakan "Memulai navigasi ke [nama tempat]"

Saat perintah `hentikan` dikenali:
- STT dihentikan
- TTS membacakan "Navigasi dihentikan"
- sesi navigasi diakhiri
- halaman navigasi ditutup

## Text-to-Speech (TTS)

### Service TTS
TTS diimplementasikan pada `TTSService` dengan package `flutter_tts`.

Konfigurasi utama:
- menggunakan bahasa `id-ID`
- pitch suara diset ke `1.0`
- `awaitSpeakCompletion(true)` digunakan agar proses bicara dapat ditunggu sampai selesai
- sebelum membacakan teks baru, service memanggil `stop()` terlebih dahulu

Method utama:
- `init()` untuk konfigurasi awal TTS
- `speak(String text)` untuk membacakan teks

## TTS pada Halaman Utama TunaNetra
File: `lib/screens/tunanetra/tunanetra_home_screen.dart`

TTS digunakan sebagai umpan balik suara dan pengantar sebelum STT aktif.

### Kondisi TTS Berjalan
TTS digunakan pada kondisi berikut:
- ketika data nama pengguna dan cuaca sudah siap
- ketika pengguna kembali ke halaman utama
- ketika perintah suara dikenali
- ketika perintah suara tidak dikenali

### Teks yang Dibacakan
Saat data pengguna dan cuaca siap:
- "Selamat datang [nama]. Cuaca hari ini [suhu] derajat, kelembapan [persen] persen, kecepatan angin [kecepatan] kilometer per jam."

Saat kembali ke halaman utama:
- "Kamu kembali ke halaman utama"

Saat perintah dikenali:
- "Membuka pengaturan bluetooth"
- "Membuka navigasi"
- "Membuka buku panduan"
- "Membuka pengaturan smartcane"
- "Membuka pengaturan"

Saat perintah tidak dikenali:
- "Perintah tidak dikenali"

## TTS pada Halaman Navigasi
File: `lib/screens/tunanetra/navigation_screen.dart`

TTS digunakan untuk memberi instruksi navigasi, konfirmasi perintah, peringatan keluar jalur, dan informasi ketika pengguna sampai tujuan.

### Kondisi TTS Berjalan
TTS digunakan pada kondisi berikut:
- saat halaman navigasi dibuka
- saat navigasi ke tujuan dimulai
- saat pengguna menghentikan navigasi
- saat pengguna mendekati instruksi belokan
- saat pengguna keluar jalur
- saat pengguna tiba di tujuan

### Teks yang Dibacakan
Saat halaman navigasi dibuka:
- "Halaman navigasi dibuka. Silahkan pilih tempat tujuan anda"

Saat navigasi dimulai:
- "Memulai navigasi ke [nama tempat]"

Saat pengguna bertanya jarak:
- "Sisa jarak ke [nama tempat] [sisa jarak]."

Saat pengguna bertanya waktu:
- "Estimasi waktu menuju [nama tempat] [estimasi waktu]."

Saat navigasi dihentikan:
- "Navigasi dihentikan"

Saat mendekati instruksi navigasi:
- "Dalam 30 meter, [instruksi]"
- "Dalam 10 meter, [instruksi]"
- "Sekarang [instruksi]"

Saat keluar jalur:
- "Anda keluar jalur. Menghitung ulang rute"

Saat sampai tujuan:
- "Anda telah tiba di [nama tempat]"
- sesi navigasi diakhiri
- halaman navigasi aktif ditutup
- aplikasi kembali ke halaman utama

## Hubungan STT dan TTS
Pada beberapa bagian, STT dan TTS saling bergantian agar suara aplikasi tidak bertabrakan dengan input suara pengguna.

Pola yang digunakan:
- TTS berbicara terlebih dahulu
- setelah TTS selesai, STT mulai mendengarkan
- ketika STT menangkap perintah, STT dihentikan
- aplikasi menjalankan aksi
- TTS membacakan konfirmasi

Pada halaman utama dan navigasi terdapat flag `_isSpeaking` untuk menandai bahwa aplikasi sedang berbicara. Jika `_isSpeaking` aktif, hasil STT diabaikan agar suara dari TTS tidak ikut terbaca sebagai perintah pengguna.

## Catatan Implementasi
- STT saat ini menggunakan Bahasa Indonesia melalui `id_ID`.
- TTS saat ini menggunakan Bahasa Indonesia melalui `id-ID`.
- Perintah suara masih berbasis pencocokan teks sederhana menggunakan `contains()`.
- STT pada halaman utama belum digunakan untuk mengirim SOS.
- TTS sudah digunakan untuk navigasi turn-by-turn, termasuk cue jarak 30 meter, 10 meter, dan instruksi "Sekarang".
