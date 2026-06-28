# Rangkuman TTS Peringatan SmartCane

Berlaku untuk **mode jelajah** dan **mode navigasi** (satu pipeline, `_handleSensorTts`).  
Prinsip: satu pesan = satu informasi paling kritis, ≤ 5 kata, hierarki ketat.

---

## Hierarki Prioritas

| Level | Kategori | Sumber Data |
|-------|----------|-------------|
| 1 | Sensor ultrasonik danger | `data.isDanger` |
| 2 | Bahaya fisik ML (road / pothole) | `data.detections` |
| 3 | Waspada (obstacle, tangga, kendaraan) | `data.detections` |
| 4 | Info lingkungan (zebra cross, genangan) | `data.detections` |
| 5 | Arah saja dari RPi | `data.decision` |
| — | Jalur kembali aman | transisi level ≥ 2 → < 2, stabil 1 detik |

---

## Pesan TTS per Kondisi

### Level 1 — Sensor Ultrasonik Danger

| Kondisi | Pesan TTS |
|---------|-----------|
| Danger + arah kiri | `"Bahaya! Belok kiri."` |
| Danger + arah kanan | `"Bahaya! Belok kanan."` |
| Danger + stop | `"Bahaya! Berhenti."` |
| Danger tanpa info tambahan | `"Bahaya! Berhenti."` |

> Decision yang dikenali: `kiri`, `belok kiri`, `pindah kiri`, `pindah ke kiri`, `geser kiri`, `geser ke kiri` (dan versi kanan), `stop`, `berhenti`, `berhenti sementara`.

---

### Level 2 — Bahaya Fisik ML

| Kondisi | Pesan TTS |
|---------|-----------|
| Road di tengah / depan | `"Jalur kendaraan! Mundur."` |
| Road di sisi kiri | `"Jalur kendaraan kiri!"` |
| Road di sisi kanan | `"Jalur kendaraan kanan!"` |
| Pothole di tengah / depan | `"Lubang di depan."` |
| Pothole di sisi kiri | `"Lubang kiri."` |
| Pothole di sisi kanan | `"Lubang kanan."` |

---

### Level 3 — Waspada (Obstacle, Tangga, Kendaraan)

| Kondisi | Pesan TTS |
|---------|-----------|
| 1 objek + posisi tengah | `"{objek}, waspada."` |
| 1 objek + posisi kiri/kanan | `"{objek} kiri/kanan, waspada."` |
| 1 objek + arah dari RPi | `"{objek}. Belok kiri/kanan."` |
| 2 objek atau lebih | `"{objek1} dan {objek2}, waspada."` |

Label yang masuk level 3: `obstacle` → hambatan, `stair/stairs` → tangga, `person` → orang, `bicycle` → sepeda, `car` → mobil, `motorcycle/motorbike` → motor, `bus`, `truck` → truk.

---

### Warning tanpa Label Spesifik

| Kondisi | Pesan TTS |
|---------|-----------|
| Warning + arah kiri/kanan | `"Hambatan, belok kiri/kanan."` |
| Warning + stop | `"Hambatan, berhenti."` |
| Warning tanpa info tambahan | `"Hati-hati! Hambatan."` |

---

### Level 4 — Info Lingkungan

| Kondisi | Pesan TTS |
|---------|-----------|
| Zebra cross (label apapun yang mengandung "zebra") | `"Zebra cross, waspada."` |
| Genangan di tengah | `"Genangan, waspada."` |
| Genangan di sisi kiri/kanan | `"Genangan kiri/kanan, waspada."` |
| Objek lain (bukan walkable/road) | `"{objek} kiri/kanan, waspada."` |

---

### Level 5 — Arah Saja

| Kondisi | Pesan TTS |
|---------|-----------|
| Hanya ada decision arah, tanpa deteksi bahaya | `"Belok kiri."` / `"Belok kanan."` |

---

### Jalur Kembali Aman

| Kondisi | Pesan TTS |
|---------|-----------|
| Status tidak lagi danger/warning, stabil selama **1 detik** | `"Jalur aman."` |

---

## Catatan Posisi

Posisi **tengah** tidak disebutkan dalam TTS (default).  
Posisi **kiri** / **kanan** selalu disebut di akhir nama objek, contoh: `"Lubang kiri."`, `"Orang kanan, waspada."`.
