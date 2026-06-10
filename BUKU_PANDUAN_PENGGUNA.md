# Buku Panduan Pengguna Teman Arah dan Smart Cane

## Tentang Buku Panduan

Buku panduan ini menjelaskan penggunaan sistem Teman Arah secara
keseluruhan, mulai dari menyiapkan Smart Cane, menghubungkan alat ke
aplikasi, menggunakan sensor dan perintah suara, menjalankan navigasi,
hingga mengirim SOS.

Sistem Teman Arah terdiri dari:

- Aplikasi Teman Arah pada telepon pengguna.
- Smart Cane sebagai alat bantu mobilitas.
- Aplikasi keluarga untuk pemantauan lokasi dan penerimaan SOS.

Teman Arah dan Smart Cane merupakan alat bantu. Pengguna tetap perlu
menggunakan teknik orientasi dan mobilitas, memperhatikan suara
lingkungan, serta memeriksa jalur menggunakan tongkat.

---

## 1. Mengenal Sistem

Teman Arah dan Smart Cane bekerja sebagai satu sistem untuk membantu
mobilitas dan keselamatan pengguna tunanetra.

### Teman Arah

Teman Arah adalah aplikasi pendamping pada telepon pengguna. Aplikasi
ini menyediakan:

- Navigasi berbasis GPS dan panduan suara.
- Informasi sensor dan hasil deteksi objek dari Smart Cane.
- Perintah suara atau Speech-to-Text.
- SOS darurat.
- Informasi baterai telepon dan Smart Cane.
- Pengiriman lokasi perjalanan serta kondisi SOS kepada keluarga yang
  sudah terhubung.

### Smart Cane

Smart Cane adalah tongkat bantu yang membaca kondisi di sekitar
pengguna. Smart Cane dilengkapi dengan:

- Tiga sensor untuk membaca jarak di sisi kiri, tengah, dan kanan.
- Kamera dan model untuk membantu mengenali objek.
- Sistem pembacaan pergerakan dan baterai alat.
- Tombol asisten suara atau STT.
- Tombol SOS.

### Cara Smart Cane dan Teman Arah bekerja bersama

Smart Cane terhubung ke aplikasi Teman Arah melalui Bluetooth. Smart
Cane dapat mengirim:

- Jarak sensor kiri dalam sentimeter.
- Jarak sensor tengah dalam sentimeter.
- Jarak sensor kanan dalam sentimeter.
- Status jalur aman, peringatan, atau bahaya.
- Saran arah seperti maju, kiri, kanan, atau berhenti.
- Nama objek yang terdeteksi kamera.
- Persentase baterai Smart Cane.
- Event tombol asisten suara dan event SOS.

Teman Arah mengolah data tersebut menjadi informasi visual dan suara.
Ketika navigasi aktif, Teman Arah membantu menunjukkan rute, sedangkan
Smart Cane membantu pengguna memeriksa kondisi jalan secara langsung.

Contoh informasi pada aplikasi:

```text
Kiri 35 cm | Tengah 78 cm | Kanan 42 cm
Keputusan: Pindah ke kiri
Hati-hati, hambatan: kursi
```

Teman Arah dan Smart Cane merupakan alat bantu. Pengguna tetap perlu
meraba jalur menggunakan tongkat dan memperhatikan kondisi lingkungan.

---

## 2. Persiapan

Siapkan Smart Cane, aplikasi Teman Arah, telepon, dan koneksi keluarga
sebelum memulai perjalanan:

1. Pastikan baterai Smart Cane mencukupi.
2. Pastikan baterai telepon mencukupi.
3. Nyalakan Smart Cane.
4. Nyalakan telepon dan buka aplikasi Teman Arah.
5. Aktifkan Bluetooth.
6. Aktifkan GPS atau layanan lokasi.
7. Aktifkan koneksi internet.
8. Pastikan volume media telepon dapat terdengar.
9. Pastikan akun pengguna sudah terhubung dengan akun keluarga.
10. Tunggu proses izin dan layanan awal Teman Arah selesai.

### Izin aplikasi

Pada penggunaan pertama, berikan izin berikut:

- Lokasi, untuk navigasi dan pemantauan keluarga.
- Bluetooth, untuk menghubungkan Smart Cane.
- Mikrofon, untuk perintah suara.
- Notifikasi, untuk informasi penting dari aplikasi.

Jika salah satu izin ditolak, beberapa fitur mungkin tidak dapat
digunakan.

---

## 3. Menghidupkan Smart Cane dan Fungsi Tombol

### Tombol hitam untuk menghidupkan dan mematikan Smart Cane

Tombol hitam berfungsi sebagai tombol daya Smart Cane.

1. Tekan tombol hitam satu kali untuk menghidupkan Smart Cane.
2. Tunggu Smart Cane menyala dan Teman Arah mulai melakukan proses
   koneksi.
3. Setelah selesai digunakan, tekan tombol hitam satu kali lagi untuk
   mematikan Smart Cane.

### Tombol merah untuk asisten suara

1. Pastikan Smart Cane sudah terhubung dan Teman Arah telah mengatakan
   bahwa alat siap digunakan.
2. Tekan dan tahan tombol merah pada Smart Cane.
3. Smart Cane mengirim event mulai mendengarkan kepada Teman Arah.
4. Tetap tahan tombol merah, lalu ucapkan satu perintah dengan singkat,
   jelas, dan tidak terlalu cepat.
5. Lepaskan tombol merah setelah selesai berbicara.
6. Smart Cane mengirim event berhenti mendengarkan. Teman Arah kemudian
   memproses ucapan pengguna.
7. Dengarkan respons Teman Arah sampai selesai sebelum memberikan
   perintah berikutnya.

Jika perintah tidak dikenali, kurangi kebisingan, tekan dan tahan
kembali tombol merah, lalu ulangi perintah.

### Tombol SOS

SOS dikirim menggunakan tombol merah yang sama dengan tombol asisten
suara, tetapi menggunakan pola tekan yang berbeda.

Cara mengirim SOS:

1. Tekan tombol merah sebanyak lima kali dengan cepat.
2. Smart Cane mengirim event SOS kepada Teman Arah.
3. Teman Arah mengirim data SOS kepada keluarga.
4. Lokasi pengguna dan data pendukung dikirim jika tersedia.
5. Teman Arah membacakan status pengiriman SOS.

Gunakan pola lima kali tekan hanya ketika pengguna membutuhkan bantuan
segera.

---

## 4. Menghubungkan Smart Cane

### Menghubungkan untuk pertama kali

1. Nyalakan Smart Cane.
2. Dekatkan Smart Cane dengan telepon.
3. Pastikan Bluetooth telepon aktif.
4. Buka aplikasi Teman Arah.
5. Pilih bagian koneksi Smart Cane pada halaman utama.
6. Mulai pencarian perangkat Bluetooth.
7. Pilih perangkat Smart Cane yang tersedia.
8. Tunggu sampai Teman Arah menyatakan Smart Cane terhubung.

Pengguna juga dapat membuka proses koneksi melalui perintah suara:

```text
Hubungkan SmartCane
```

Variasi yang dapat dikenali:

- "Hubungkan tongkat"
- "Hubungkan SmartCane"
- "Bluetooth"

### Penyambungan kembali

Setelah pernah terhubung, aplikasi menyimpan perangkat Smart Cane dan
akan mencoba menyambungkannya kembali secara otomatis.

Jika penyambungan otomatis gagal:

1. Pastikan Smart Cane masih menyala.
2. Pastikan Bluetooth telepon aktif.
3. Dekatkan Smart Cane dengan telepon.
4. Buka kembali menu koneksi.
5. Pilih perangkat dan hubungkan ulang.

### Mendengarkan tanda Smart Cane siap

Pengguna tidak perlu memeriksa status alat secara visual. Setelah proses
koneksi dimulai, dengarkan informasi suara atau TTS dari aplikasi.

Urutan informasi yang mungkin terdengar:

```text
SmartCane terhubung. Menunggu sistem siap.
```

Smart Cane benar-benar siap digunakan setelah aplikasi mengatakan:

```text
SmartCane siap digunakan.
```

Jangan mulai mengandalkan informasi sensor sebelum mendengar bahwa
Smart Cane siap digunakan.

---

## 5. Memeriksa Status Sistem

Halaman utama menampilkan:

- Nama pengguna.
- Status koneksi Smart Cane.
- Status sensor dan model.
- Baterai Smart Cane.
- Baterai telepon.
- Status GPS.
- Tombol Mulai Navigasi.
- Tombol Kirim SOS.
- Menu Buku Panduan.
- Menu Pengaturan.

Pengguna tidak harus memeriksa seluruh status secara visual. Gunakan
perintah "Cek SmartCane", "Cek koneksi", "Cek baterai", dan "Cek GPS"
untuk mendengarkan kondisi sistem.

Sebelum memulai perjalanan, pastikan:

- GPS aktif.
- Smart Cane terhubung.
- Sensor aktif.
- Model deteksi aktif.
- Baterai telepon dan Smart Cane mencukupi.
- Teman Arah sudah mengatakan bahwa Smart Cane siap digunakan.

---

## 6. Memahami Data Sensor

Smart Cane membaca tiga data jarak, kemudian mengirimkannya ke Teman
Arah melalui Bluetooth:

- Kiri, yaitu jarak hambatan pada sisi kiri.
- Tengah, yaitu jarak hambatan di depan atau bagian tengah.
- Kanan, yaitu jarak hambatan pada sisi kanan.

Teman Arah menampilkan data tersebut dalam sentimeter dan dapat
membacakan peringatan yang dihasilkan. Semakin kecil nilainya, semakin
dekat hambatan dengan pengguna.

### Status sensor

Status yang dapat muncul:

| Status | Arti |
| --- | --- |
| Aman | Jalur berdasarkan data sensor tidak menunjukkan bahaya dekat |
| Hati-hati | Sensor atau model menemukan hambatan yang perlu diperhatikan |
| Bahaya | Hambatan terdeteksi sangat dekat atau membutuhkan tindakan segera |

Jika model Smart Cane mengenali objek ketika ada hambatan, Teman Arah
akan menyebutkan nama objek tersebut. Contohnya, aplikasi mengatakan
"Hati-hati, kursi terdeteksi sebagai hambatan." Jika nama objek belum
tersedia, aplikasi tetap memberikan peringatan hambatan secara umum.

Jika Smart Cane juga mengirim keputusan arah, keputusan tersebut langsung
ditambahkan pada TTS. Contohnya, "Hati-hati, kursi terdeteksi sebagai
hambatan. Pindah ke kanan."

Setelah peringatan hati-hati atau bahaya, Teman Arah akan mengatakan
"Jalur sudah aman. Silakan lanjutkan perjalanan." ketika pembacaan sensor
sudah kembali aman dan stabil. Pengumuman ini diberikan satu kali agar
pengguna mengetahui bahwa perjalanan dapat dilanjutkan tanpa menerima
pesan berulang.

### Keputusan arah

Smart Cane dapat mengirim keputusan:

- Maju.
- Pindah ke kiri.
- Pindah ke kanan.
- Berhenti.

Smart Cane menghasilkan keputusan dari sensor dan model. Teman Arah
menampilkan atau membacakannya agar pengguna dapat memahami kondisi
alat. Pengguna tetap perlu meraba kondisi jalan dengan tongkat.

### Deteksi objek

Kamera Smart Cane dapat memberikan nama objek kepada Teman Arah,
misalnya:

- Orang.
- Sepeda.
- Mobil.
- Motor.
- Bus atau truk.
- Lampu lalu lintas.
- Bangku atau kursi.
- Hewan.
- Tas, botol, payung, dan objek lain yang dikenali model.

Teman Arah menampilkan atau membacakan nama objek bersama peringatan.
Hasil deteksi dapat salah atau terlambat. Jangan menggunakannya sebagai
satu-satunya dasar untuk menyeberang atau menghindari bahaya.

---

## 7. Perintah Suara

Bagian ini berisi daftar kalimat yang dapat diucapkan setelah asisten
suara diaktifkan menggunakan tombol merah. Cara penggunaan tombol
dijelaskan pada bagian tombol Smart Cane.

### 7.1 Perintah global

Perintah global tersedia pada halaman yang mengaktifkan listener suara
global.

| Perintah utama | Variasi yang dikenali | Fungsi |
| --- | --- | --- |
| "Halaman utama" | "Beranda", "Home" | Kembali ke halaman utama |
| "SOS" | "Darurat", "Tolong", "Bantuan", "Butuh bantuan" | Mengirim SOS kepada keluarga |

Jika pengguna sudah berada di halaman utama, perintah "Halaman utama"
akan menghasilkan respons:

```text
Kamu sudah berada di halaman utama.
```

### 7.2 Perintah pada halaman utama

| Perintah suara | Fungsi |
| --- | --- |
| "Navigasi" | Membuka halaman navigasi dan daftar tujuan |
| "Buku panduan" | Membuka halaman Buku Panduan |
| "Ebook" | Membuka halaman Buku Panduan |
| "Pengaturan" | Membuka halaman Pengaturan |
| "Hubungkan SmartCane" | Membuka proses koneksi Bluetooth Smart Cane |
| "Hubungkan tongkat" | Membuka proses koneksi Bluetooth Smart Cane |
| "Bluetooth" | Membuka proses koneksi Bluetooth Smart Cane |
| "Cek koneksi" | Membacakan status koneksi Smart Cane |
| "Cek baterai" | Membacakan baterai Smart Cane |
| "Cek SmartCane" | Membacakan kesiapan koneksi, sensor, model, dan baterai |
| "Cek tongkat" | Membacakan kesiapan Smart Cane |
| "Cek GPS" | Membacakan status GPS |
| "Cek cuaca" | Membacakan informasi cuaca saat ini |

Contoh respons:

```text
SmartCane terhubung. Baterai 75 persen.
```

```text
Baterai SmartCane 75 persen.
```

```text
Status GPS aktif.
```

Jika aplikasi tidak memahami ucapan, aplikasi akan mengatakan:

```text
Perintah tidak dikenali.
```

### 7.3 Perintah pada halaman navigasi

| Perintah suara | Fungsi |
| --- | --- |
| Nama tempat tujuan | Memilih tempat dan memulai proses navigasi |
| "Cek jarak" | Membacakan sisa jarak menuju tujuan |
| "Cek waktu" | Membacakan estimasi waktu menuju tujuan |
| "Hentikan navigasi" | Menghentikan sesi navigasi |
| "Halaman utama" | Menghentikan alur halaman dan kembali ke halaman utama |
| "SOS" atau "Butuh bantuan" | Mengirim SOS dari halaman navigasi |

Nama tempat dapat dikenali dari:

- Nama tempat.
- Kategori tempat.
- Alamat tempat.

Contoh:

```text
Rumah
```

```text
Indomaret
```

```text
Stasiun Bandung
```

Jika tempat ditemukan, aplikasi akan mengatakan:

```text
Memilih Indomaret.
```

Jika rute belum tersedia dan pengguna mengucapkan "Cek jarak" atau
"Cek waktu", aplikasi akan mengatakan:

```text
Rute navigasi belum tersedia.
```

---

## 8. Navigasi

### Memilih tujuan melalui layar

1. Pastikan Smart Cane terhubung dan Teman Arah menyatakan alat siap.
2. Buka menu Navigasi.
3. Pilih tempat dari daftar tujuan.
4. Pastikan nama dan alamat tujuan benar.
5. Tunggu Teman Arah memperoleh GPS.
6. Tunggu sampai rute ditemukan.
7. Dengarkan panduan awal sebelum mulai berjalan.

### Memilih tujuan melalui suara

1. Buka halaman Navigasi.
2. Aktifkan tombol asisten suara pada Smart Cane.
3. Ucapkan nama tempat, kategori, atau alamat.
4. Dengarkan konfirmasi tempat yang dipilih.
5. Tunggu sampai Teman Arah menemukan rute.

### Informasi navigasi

Selama navigasi, Teman Arah memberikan:

- Informasi arah pada jarak sekitar 30 meter.
- Informasi arah pada jarak sekitar 20 meter.
- Informasi arah pada jarak sekitar 10 meter.
- Informasi masuk area belok pada jarak sekitar 5 meter.
- Konfirmasi setelah pengguna berhasil berbelok.
- Informasi ketika pengguna keluar rute.
- Informasi ketika rute baru ditemukan.
- Informasi saat mendekati dan mencapai tujuan.

Contoh:

```text
Dalam 30 meter, belok kanan ke Gang Gotong Royong.
```

```text
Anda sudah masuk area belok kanan.
```

```text
Belok berhasil. Lanjutkan perjalanan.
```

### Saat memasuki area belok

1. Kurangi kecepatan berjalan.
2. Gunakan Smart Cane untuk meraba batas jalan dan bukaan belokan.
3. Dengarkan informasi sensor Smart Cane yang disampaikan Teman Arah.
4. Mulai berbelok setelah jalur terasa aman.
5. Dengarkan konfirmasi bahwa belokan berhasil.

Teman Arah membantu menunjukkan area belok. Posisi belokan nyata
tetap perlu ditemukan menggunakan Smart Cane dan kondisi lingkungan.

### Jika keluar rute

1. Berhenti atau kurangi kecepatan.
2. Dengarkan peringatan dari Teman Arah.
3. Tunggu Teman Arah menghitung rute baru.
4. Jangan kembali ke jalan secara tiba-tiba.
5. Periksa lingkungan menggunakan tongkat sebelum melanjutkan.

### Mengakhiri navigasi

Navigasi dapat berakhir ketika:

- Pengguna sudah tiba di tujuan.
- Pengguna memilih menghentikan navigasi.
- Pengguna mengucapkan "Hentikan navigasi".

---

## 9. SOS

SOS dapat dikirim dengan tiga cara:

1. Menekan tombol merah pada Smart Cane sebanyak lima kali dengan cepat.
2. Menekan tombol Kirim SOS pada Teman Arah.
3. Mengucapkan "SOS", "Darurat", "Tolong", "Bantuan", atau
   "Butuh bantuan".

### Data yang dapat dikirim

Ketika tersedia, keluarga dapat menerima:

- Nama pengguna.
- Waktu SOS dikirim.
- Koordinat lokasi pengguna.
- Baterai telepon.
- Baterai Smart Cane.

### Setelah SOS dikirim

1. Dengarkan konfirmasi pengiriman.
2. Tetap berada di tempat yang aman jika memungkinkan.
3. Tunggu keluarga menghubungi atau mendatangi pengguna.
4. Gunakan telepon untuk menghubungi layanan darurat jika diperlukan.

Kemungkinan respons aplikasi:

```text
Mengirim SOS darurat.
```

```text
Status SOS, berhasil dikirim ke keluarga.
```

```text
Status SOS, gagal dikirim.
```

Jika gagal, periksa internet dan GPS, lalu kirim ulang atau hubungi
keluarga melalui telepon.

---

## 10. Pemantauan oleh Keluarga

Setelah akun terhubung, keluarga dapat:

- Melihat status pengguna.
- Melihat lokasi pengguna.
- Memantau perjalanan aktif.
- Melihat riwayat perjalanan.
- Melihat baterai telepon.
- Melihat baterai Smart Cane jika datanya tersedia.
- Menerima peringatan SOS.
- Membuka lokasi SOS.
- Menandai SOS sebagai ditangani.

Pastikan akun keluarga sudah terhubung sebelum pengguna melakukan
perjalanan sendiri.

---

## 11. Selesai Menggunakan Sistem

Setelah perjalanan selesai:

1. Pastikan navigasi sudah berakhir.
2. Kembali ke halaman utama.
3. Putuskan Smart Cane jika alat tidak akan digunakan lagi.
4. Matikan Smart Cane.
5. Isi daya Smart Cane jika diperlukan.
6. Isi daya telepon jika diperlukan.
7. Simpan Smart Cane di tempat yang aman dan kering.

---

## 12. Pemecahan Masalah dan Keselamatan

### Smart Cane tidak ditemukan

- Pastikan Smart Cane menyala.
- Pastikan Bluetooth telepon aktif.
- Dekatkan alat dengan telepon.
- Jalankan pencarian perangkat kembali.
- Matikan dan nyalakan Bluetooth jika diperlukan.

### Smart Cane terhubung tetapi sensor belum aktif

- Tunggu beberapa saat sampai data sensor masuk.
- Pastikan sistem utama Smart Cane sudah selesai menyala.
- Putuskan lalu sambungkan kembali perangkat.
- Nyalakan ulang Smart Cane jika data tetap tidak masuk.

### Model deteksi belum aktif

- Tunggu proses model selesai dimuat.
- Pastikan kamera Smart Cane tidak tertutup.
- Pastikan sistem utama alat aktif.
- Sambungkan kembali jika status tidak berubah.

### Baterai Smart Cane belum terbaca

- Pastikan Smart Cane terhubung.
- Tunggu data baterai berikutnya.
- Periksa sistem pembacaan baterai pada alat jika nilai tetap kosong.

### GPS belum aktif atau tidak akurat

- Aktifkan layanan lokasi.
- Berikan izin lokasi kepada aplikasi.
- Berpindah ke area terbuka.
- Tunggu beberapa saat sampai posisi stabil.

### Perintah suara tidak dikenali

- Pastikan izin mikrofon diberikan.
- Kurangi kebisingan di sekitar.
- Ucapkan satu perintah secara singkat.
- Gunakan salah satu kalimat yang tercantum pada daftar perintah.
- Tunggu TTS selesai sebelum berbicara.

### Suara aplikasi tidak terdengar

- Naikkan volume media telepon.
- Pastikan telepon tidak berada dalam mode senyap.
- Periksa perangkat audio atau headset yang terhubung.

### Rute tidak ditemukan

- Periksa koneksi internet.
- Pastikan GPS sudah aktif.
- Periksa kembali koordinat atau tempat tujuan.
- Coba mulai navigasi kembali.

### SOS gagal dikirim

- Periksa koneksi internet.
- Pastikan izin lokasi tersedia.
- Coba kirim ulang.
- Hubungi keluarga atau layanan darurat melalui telepon.

---

## 13. Panduan Keselamatan

- Periksa baterai telepon dan Smart Cane sebelum perjalanan.
- Pastikan keluarga sudah terhubung.
- Gunakan Smart Cane selama berjalan.
- Jangan hanya bergantung pada GPS atau deteksi kamera.
- GPS dapat bergeser beberapa meter dari posisi sebenarnya.
- Data peta dapat berbeda dari kondisi jalan nyata.
- Deteksi objek dapat salah atau terlambat.
- Berhenti jika panduan aplikasi berbeda dengan kondisi nyata.
- Gunakan speaker atau headset satu sisi agar suara lingkungan tetap
  terdengar.
- Jangan memeriksa layar sambil berjalan.
- Berhenti di tempat aman sebelum mengubah pengaturan aplikasi.
- Gunakan SOS jika membutuhkan bantuan segera.

---

## 14. Ringkasan Penggunaan Cepat

```text
Isi baterai alat dan telepon
-> Nyalakan Smart Cane
-> Buka aplikasi Teman Arah
-> Aktifkan Bluetooth, GPS, dan internet
-> Hubungkan Smart Cane
-> Pastikan sensor dan model aktif
-> Pilih tujuan navigasi
-> Ikuti informasi suara
-> Gunakan Smart Cane untuk menemukan jalur dan area belok
-> Kirim SOS jika membutuhkan bantuan
-> Akhiri navigasi
-> Matikan dan simpan alat
```

---

## Catatan Penyusunan untuk Implementasi Halaman

Dokumen ini dapat dipecah menjadi bagian halaman Buku Panduan berikut:

1. Mengenal Smart Cane.
2. Persiapan dan koneksi.
3. Sensor dan deteksi objek.
4. Tombol Smart Cane.
5. Halaman utama aplikasi.
6. Perintah suara.
7. Navigasi.
8. SOS dan pemantauan keluarga.
9. Masalah umum.
10. Keselamatan.

Setiap bagian sebaiknya menyediakan:

- Tombol dengarkan seluruh bagian.
- Tombol dengarkan per langkah.
- Judul yang singkat.
- Nomor langkah yang jelas.
- Catatan keselamatan yang mudah dikenali.
