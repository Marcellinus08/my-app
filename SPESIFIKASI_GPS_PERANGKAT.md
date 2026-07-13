# Spesifikasi GPS Perangkat Uji

Diambil langsung dari device fisik lewat `adb shell dumpsys location` / `adb shell getprop`. Hanya mencakup bagian yang berpengaruh terhadap **kecepatan update** dan **performa fix GPS** — bukan spesifikasi umum device.

## Device

| Item | Nilai |
|---|---|
| Model | Samsung Galaxy A54 5G (`SM-A546E`) |
| Android version | 16 |
| Chipset (SoC) | Exynos 1380 (`s5e8835`) |

## Chip GNSS

| Item | Nilai | Pengaruh ke performa |
|---|---|---|
| Hardware model | `S.LSI,K057,SPOTNAV_4.11.1_25_E87` | Chip GNSS Samsung LSI dengan positioning engine SpotNav |
| Konstelasi satelit didukung | `GPS, GLONASS, QZSS, BEIDOU, GALILEO` (5 sistem) | Semakin banyak konstelasi yang ditangkap, semakin cepat & stabil time-to-first-fix dan akurasi, terutama di kondisi sinyal terhalang (indoor/urban canyon) |
| Dual-frequency tracking | Ada (`MULTIBAND_TRACKING_POWER`, `MULTIBAND_ACQUISITION_POWER`) | Chip mendukung band L1+L5, mengurangi efek multipath yang jadi penyebab utama error besar di area urban/indoor |
| A-GPS / PSDS | Aktif (`vendor.gnss.psds` terisi data prediksi satelit terbaru) | Mempercepat time-to-first-fix karena device tidak perlu decode almanak satelit dari nol |
| LPP (LTE Positioning Protocol) | `persist.sys.gps.lpp = 2` | Device bisa memakai bantuan jaringan seluler (network-assisted positioning) untuk mempercepat fix |
| Mock location | Dinonaktifkan (`ro.allow.mock.location = 0`) | Data yang dibaca tool pengujian dijamin dari GPS asli, bukan lokasi palsu/simulasi |

## Kapabilitas GNSS Manager (relevan performa)

Dari `dumpsys location` → `GNSS Manager: Capabilities`:

```
SCHEDULING, MSB, MSA, SINGLE_SHOT, ON_DEMAND_TIME, NAVIGATION_MESSAGES,
LOW_POWER_MODE, SATELLITE_BLOCKLIST, SATELLITE_PVT,
MEASUREMENT_CORRECTIONS_FOR_DRIVING, SINGLEBAND_TRACKING_POWER,
MULTIBAND_TRACKING_POWER, SINGLEBAND_ACQUISITION_POWER,
MULTIBAND_ACQUISITION_POWER
```

Poin penting:
- `MEASUREMENT_CORRECTIONS_FOR_DRIVING` — chip mendukung koreksi pengukuran untuk mengurangi efek multipath (pantulan sinyal dari gedung).
- `SATELLITE_BLOCKLIST` — bisa mengabaikan satelit dengan sinyal buruk/tidak sehat secara otomatis, menjaga kualitas fix.
- `LOW_POWER_MODE` — device bisa menyesuaikan duty-cycle GNSS untuk hemat baterai tanpa mematikan tracking sepenuhnya.

## Interval update yang teramati di device yang sama

Dari log `dumpsys location` saat aplikasi navigasi lain berjalan di device ini:

```
com.google.android.apps.maps: min/max interval = 0s/1s
```

Google Maps (aplikasi navigasi pembanding paling umum dipakai) meminta interval hingga **1 detik** di device yang sama — dipakai sebagai pembanding bahwa parameter `intervalDuration: 1 detik` yang dipakai aplikasi Teman Arah (lihat `lib/services/live_tracking_service.dart`, `_navigationLocationSettings`) selaras dengan praktik aplikasi navigasi mainstream, bukan angka sembarangan.

## Kaitan dengan konfigurasi aplikasi Teman Arah

| Mode tracking di app | Parameter | Constraint fisik chip |
|---|---|---|
| Navigasi aktif | `distanceFilter: 1m`, `intervalDuration: 1 detik` | Selaras dengan laju output default chip GNSS konsumen (~1 Hz); meminta lebih cepat dari ini tidak menghasilkan fix tambahan karena chip fisiknya dibatasi ~1 Hz untuk mode standar |
| Home tracking | `distanceFilter: 5m`, tanpa `intervalDuration` (ikut default OS) | Update dikontrol timer aplikasi tiap 10 detik + event pergerakan ≥5m |
