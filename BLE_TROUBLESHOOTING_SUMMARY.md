# Ringkasan Permasalahan BLE Teman Arah

## Konteks

Aplikasi Flutter Teman Arah sedang diintegrasikan dengan tongkat pintar berbasis Raspberry Pi melalui Bluetooth Low Energy atau BLE.

Peran perangkat:

- Flutter Android: BLE Central
- Raspberry Pi: BLE Peripheral / GATT Server
- Nama perangkat BLE: `TemanArah-Cane`
- Service UUID: `0000a001-0000-1000-8000-00805f9b34fb`
- Characteristic UUID: `0000a002-0000-1000-8000-00805f9b34fb`
- Characteristic digunakan untuk mengirim data sensor ultrasonik melalui BLE Notify.

Data sensor ultrasonik sudah berhasil dikirim dari Raspberry Pi ke Flutter dalam format JSON, misalnya:

```json
{"distanceCm":31.7,"status":"danger","message":"Bahaya, hambatan dekat","timestamp":1779730651}
```

## Masalah Utama

Koneksi BLE antara aplikasi Flutter dan Raspberry Pi berhasil tersambung sebentar, data sensor ultrasonik berhasil masuk, tetapi beberapa detik kemudian koneksi otomatis terputus.

Selain itu, Android sering menampilkan dialog pairing seperti:

- `Bluetooth pairing request`
- `Pair with TemanArah-Cane`
- `Enter PIN to pair with TemanArah-Cane`
- `Pairing rejected by TemanArah-Cane`

Padahal target awalnya adalah koneksi BLE untuk membaca notify sensor, bukan koneksi audio atau pairing Bluetooth klasik.

## Gejala dari Flutter

Log Flutter menunjukkan koneksi awal berhasil:

```text
[SMARTCANE_BLE] connect success: name="TemanArah-Cane"
[SMARTCANE_BLE] subscribeUltrasonicData()
[SMARTCANE_BLE] ultrasonic notify subscribed
[SMARTCANE_BLE] ultrasonic notify payload: {...}
```

Namun beberapa detik kemudian terputus:

```text
onConnectionStateChange: disconnected
status: CONNECTION_TERMINATED_BY_LOCAL_HOST
[SMARTCANE_BLE] device connectionState: disconnected
```

Android juga terlihat mencoba proses bonding:

```text
OnBondStateChanged: bonding prev: bond-none
OnBondStateChanged: bond-none prev: bonding
```

Artinya Android mencoba membuat bond/pairing, tetapi proses pairing gagal atau ditolak.

## Gejala dari Raspberry Pi

Pada script BlueZ D-Bus, Raspberry Pi sudah berhasil menjalankan BLE peripheral:

```text
GATT app registered
Advertisement registered
BLE peripheral aktif: TemanArah-Cane
```

Saat Flutter connect dan subscribe notify:

```text
Flutter connected / notify started
Notify: {"distanceCm":31.7,"status":"danger",...}
```

Namun kemudian:

```text
Flutter disconnected / notify stopped
```

Ini sesuai dengan log Flutter bahwa koneksi diputus setelah proses pairing/bonding gagal.

## Hal yang Sudah Dicoba

1. Menggunakan package Flutter:
   - `flutter_blue_plus`
   - `permission_handler`
   - `shared_preferences`

2. Membuat service Flutter khusus:
   - `SmartCaneBluetoothService`
   - scan BLE
   - connect
   - disconnect
   - test connection
   - subscribe ultrasonic notify
   - stream data sensor ke UI navigasi

3. Menonaktifkan auto reconnect sementara, supaya tidak terjadi loop reconnect.

4. Menonaktifkan STT di halaman Bluetooth, karena sebelumnya ada indikasi log `BluetoothHeadset.startVoiceRecognition` yang bisa mengganggu audio/Bluetooth.

5. Menghindari subscribe otomatis ke Service Changed characteristic `0x2A05` dengan:

```dart
discoverServices(subscribeToServicesChanged: false)
```

6. Mengubah sisi Raspberry Pi dari `bless` ke BlueZ D-Bus manual agar kontrol GATT dan advertising lebih jelas.

7. Mengatur Raspberry Pi sebagai BLE-only:

```bash
sudo btmgmt bredr off
sudo btmgmt le on
```

8. Mencoba menonaktifkan pairing/bonding:

```bash
sudo btmgmt bondable off
bluetoothctl pairable off
```

9. Mencoba mematikan Secure Connections:

```bash
sudo btmgmt sc off
```

10. Mencoba mengaktifkan privacy:

```bash
sudo btmgmt privacy on
```

11. Mengecek status adapter:

```text
current settings: powered connectable le privacy
```

## Analisis Sementara

Flutter sebenarnya sudah bisa connect dan menerima data notify. Jadi masalah utama bukan pada parsing JSON atau UI sensor ultrasonik.

Masalah paling kuat terlihat pada proses bonding/pairing Android:

- Android tetap mencoba melakukan bonding.
- Raspberry Pi sebelumnya diset `bondable off` dan `pairable off`.
- Karena Raspberry Pi menolak pairing, Android menampilkan pesan `Pairing rejected by TemanArah-Cane`.
- Setelah pairing gagal, Android memutus koneksi GATT.

Jadi masalahnya kemungkinan besar bukan karena data sensor, bukan karena Firebase, bukan karena maps, dan bukan karena UI Flutter. Masalahnya berada di lapisan sistem Bluetooth Android dan konfigurasi pairing/bonding Raspberry Pi.

## Kenapa Aplikasi Terlihat Connect Dulu Baru Minta PIN?

Pada BLE, hal ini bisa terjadi.

Alurnya:

1. Flutter melakukan GATT connect ke `TemanArah-Cane`.
2. Android menganggap koneksi awal berhasil.
3. Setelah service/characteristic diakses, Android mencoba bonding.
4. Dialog pairing/PIN muncul.
5. Jika pairing gagal, koneksi diputus.

Jadi terlihat seperti "sudah terhubung lalu baru minta PIN", tetapi itu masih normal dalam BLE Android.

## Kenapa Muncul Input PIN?

Dialog PIN muncul karena Android memilih metode pairing lama, biasanya fallback ke PIN `0000` atau `1234`.

Penyebab yang mungkin:

- Raspberry Pi tidak memiliki Bluetooth agent yang cocok.
- Android memaksa bonding untuk perangkat tersebut.
- Konfigurasi BlueZ menolak pairing.
- Android masih menyimpan cache/bond lama yang bermasalah.
- Mode pairing Raspberry Pi belum konsisten antara `btmgmt` dan `bluetoothctl`.

## Arah Solusi Berikutnya

Ada dua pendekatan utama.

## Opsi 1: Tanpa Pairing Sama Sekali

Target:

- BLE GATT connect langsung.
- Tidak ada dialog pairing.
- Characteristic `read` dan `notify` tidak membutuhkan authentication/encryption.

Status:

- Sudah dicoba dengan `bondable off` dan `pairable off`.
- Namun HP Android tetap mencoba bonding.
- Pada perangkat yang sedang dites, opsi ini belum berhasil.

## Opsi 2: Pairing Sekali Saja

Target:

- Raspberry Pi menerima pairing.
- Android menyimpan bond.
- Setelah berhasil sekali, koneksi berikutnya tidak minta PIN lagi.

Konfigurasi yang disarankan:

```bash
sudo bluetoothctl
power on
agent NoInputNoOutput
default-agent
pairable on
discoverable off
quit
```

Jika masih muncul PIN, coba:

```bash
sudo bluetoothctl
power on
agent KeyboardDisplay
default-agent
pairable on
discoverable off
quit
```

Lalu jalankan ulang script BLE:

```bash
sudo python3 ultrasonic_ble.py
```

Jika Android meminta PIN, coba:

- `0000`
- `1234`

## Langkah Bersih yang Disarankan

Sebelum tes ulang, bersihkan pairing lama.

Di Android:

1. Buka pengaturan Bluetooth.
2. Forget / lupakan `TemanArah-Cane` atau `raspberrypi`.
3. Matikan dan nyalakan Bluetooth HP.

Di Raspberry Pi:

```bash
bluetoothctl
devices
remove <MAC_HP>
quit
```

Lalu restart Bluetooth:

```bash
sudo systemctl restart bluetooth
```

Jalankan ulang script BLE.

## Status Saat Ini

Yang sudah berhasil:

- Raspberry Pi terdeteksi sebagai BLE device.
- Flutter bisa scan `TemanArah-Cane`.
- Flutter bisa connect sementara.
- Flutter berhasil subscribe characteristic notify.
- Data ultrasonic JSON berhasil masuk ke Flutter.
- UI sensor ultrasonik di halaman navigasi bisa menggunakan data BLE.

Yang masih bermasalah:

- Android tetap memicu pairing/bonding.
- Dialog PIN/pairing masih muncul.
- Pairing ditolak oleh Raspberry Pi jika mode pairable/bondable dimatikan.
- Setelah pairing gagal, koneksi BLE diputus otomatis.

## Kesimpulan

Masalah utama saat ini adalah konflik antara kebutuhan koneksi BLE GATT dan perilaku bonding Android.

Untuk melanjutkan, fokus berikutnya adalah memilih salah satu:

1. Membuat koneksi BLE benar-benar tanpa pairing.
2. Mengizinkan pairing satu kali agar Android tidak meminta pairing terus.

Melihat perilaku HP yang sedang digunakan, solusi paling realistis saat ini adalah mengizinkan pairing satu kali dengan agent BlueZ yang benar, lalu memastikan bond tersimpan di Android dan Raspberry Pi.
