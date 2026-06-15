// ============================================================
//  TEMAN ARAH — Firebase & External API Stress Test
//
//  Menguji performa:
//  [Firebase]  Realtime Database (live tracking)
//  [Firebase]  Firestore (riwayat navigasi)
//  [External]  OSRM   — routing navigasi (router.project-osrm.org)
//  [External]  Nominatim — reverse geocoding (OpenStreetMap)
//  [External]  Open-Meteo — data cuaca
//
//  CARA MENJALANKAN:
//    npm run test:tahap1   →  10 pengguna
//    npm run test:tahap2   →  50 pengguna
//    npm run test:tahap3   → 100 pengguna
//    npm run test:tahap4   → 150 pengguna
//    npm run test:tahap5   → 200 pengguna
//    npm run test:all      → semua tahap berurutan
//
//  CATATAN PENTING:
//  Nominatim & OSRM adalah public API dengan rate limit.
//  Script ini membatasi concurrency external API agar tidak
//  melanggar ToS (Nominatim: maks 1 req/detik per IP).
// ============================================================

const admin = require('firebase-admin');
const fetch = require('node-fetch');
const serviceAccount = require('./serviceAccountKey.json');

// ---- Inisialisasi Firebase Admin ----
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://smarthcane-11b47-default-rtdb.asia-southeast1.firebasedatabase.app',
});

const db   = admin.firestore();
const rtdb = admin.database();

// ---- Konfigurasi ----
const SESSION_ID = `stress_${Date.now()}`;

const STAGES = {
  all: [10, 50, 100, 150, 200],
  10:  [10],
  50:  [50],
  100: [100],
  150: [150],
  200: [200],
};

// Koordinat pengujian (area Jakarta - sesuai target pengguna app)
const TEST_COORDS = [
  { lat: -6.2088, lng: 106.8456 },  // Monas
  { lat: -6.1944, lng: 106.8229 },  // Kota Tua
  { lat: -6.2297, lng: 106.8295 },  // Gambir
  { lat: -6.2615, lng: 106.7810 },  // Kebayoran Baru
  { lat: -6.1751, lng: 106.8650 },  // Kelapa Gading
];

// ================================================================
//  OPERASI FIREBASE
// ================================================================

async function rtdbWrite(userId) {
  const sw = Date.now();
  try {
    const coord = TEST_COORDS[userId % TEST_COORDS.length];
    await rtdb
      .ref(`stress_test/${SESSION_ID}/live_tracking/user_${userId}`)
      .set({
        userId:           `stress_user_${userId}`,
        lat:              coord.lat + (userId * 0.00001),
        lng:              coord.lng + (userId * 0.00001),
        isNavigating:     true,
        speed:            1.2 + (userId % 5) * 0.3,
        batteryLevel:     80 - (userId % 20),
        smartCaneBattery: 70 - (userId % 15),
        gpsStatus:        'gps_live',
        connectionStatus: 'online',
        updatedAt:        admin.database.ServerValue.TIMESTAMP,
      });
    return { success: true, latency: Date.now() - sw };
  } catch (e) {
    return { success: false, latency: Date.now() - sw, error: e.message };
  }
}

async function rtdbRead(userId) {
  const sw = Date.now();
  try {
    const target = userId % Math.max(1, Math.floor(TEST_COORDS.length));
    await rtdb
      .ref(`stress_test/${SESSION_ID}/live_tracking/user_${target}`)
      .once('value');
    return { success: true, latency: Date.now() - sw };
  } catch (e) {
    return { success: false, latency: Date.now() - sw, error: e.message };
  }
}

async function firestoreWrite(userId) {
  const sw = Date.now();
  try {
    await db
      .collection('stress_test')
      .doc(SESSION_ID)
      .collection('navigation_history')
      .add({
        userId:          `stress_user_${userId}`,
        destinationName: `Tujuan_Test_${userId}`,
        distanceKm:      1.5 + (userId % 10) * 0.2,
        durationSeconds: 300 + userId * 5,
        endReason:       'arrived',
        createdAt:       admin.firestore.FieldValue.serverTimestamp(),
      });
    return { success: true, latency: Date.now() - sw };
  } catch (e) {
    return { success: false, latency: Date.now() - sw, error: e.message };
  }
}

async function firestoreRead(userId) {
  const sw = Date.now();
  try {
    await db
      .collection('stress_test')
      .doc(SESSION_ID)
      .collection('navigation_history')
      .limit(5)
      .get();
    return { success: true, latency: Date.now() - sw };
  } catch (e) {
    return { success: false, latency: Date.now() - sw, error: e.message };
  }
}

// ================================================================
//  OPERASI EXTERNAL API
// ================================================================

// OSRM — routing navigasi (simulasi: user meminta rute)
async function osrmRouting(userId) {
  const sw = Date.now();
  try {
    const origin = TEST_COORDS[userId % TEST_COORDS.length];
    const dest   = TEST_COORDS[(userId + 1) % TEST_COORDS.length];
    const url =
      `https://router.project-osrm.org/route/v1/foot/` +
      `${origin.lng},${origin.lat};${dest.lng},${dest.lat}` +
      `?overview=false&steps=false`;

    const res = await fetch(url, {
      headers: { 'User-Agent': 'TemanArah-StressTest/1.0' },
      timeout: 15000,
    });
    const data = await res.json();
    const ok = res.ok && data.code === 'Ok';
    return { success: ok, latency: Date.now() - sw, statusCode: res.status };
  } catch (e) {
    return { success: false, latency: Date.now() - sw, error: e.message };
  }
}

// Nominatim — reverse geocoding (simulasi: app mencari nama lokasi)
// PENTING: Nominatim public API = maks 1 req/detik per IP.
// Script membatasi concurrency menjadi 5 sekaligus dengan jeda.
async function nominatimGeocode(userId) {
  const sw = Date.now();
  try {
    const coord = TEST_COORDS[userId % TEST_COORDS.length];
    const url =
      `https://nominatim.openstreetmap.org/reverse` +
      `?format=json&lat=${coord.lat}&lon=${coord.lng}&zoom=10`;

    const res = await fetch(url, {
      headers: {
        'User-Agent': 'TemanArah-StressTest/1.0 (kamisemangattea@gmail.com)',
        'Accept-Language': 'id',
      },
      timeout: 15000,
    });
    const ok = res.status === 200;
    if (ok) await res.json();
    return { success: ok, latency: Date.now() - sw, statusCode: res.status };
  } catch (e) {
    return { success: false, latency: Date.now() - sw, error: e.message };
  }
}

// Open-Meteo — cuaca (simulasi: app memuat data cuaca)
async function openMeteoWeather(userId) {
  const sw = Date.now();
  try {
    const coord = TEST_COORDS[userId % TEST_COORDS.length];
    const url =
      `https://api.open-meteo.com/v1/forecast` +
      `?latitude=${coord.lat}&longitude=${coord.lng}` +
      `&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m` +
      `&timezone=auto&forecast_days=1`;

    const res = await fetch(url, {
      headers: { 'User-Agent': 'TemanArah-StressTest/1.0' },
      timeout: 15000,
    });
    const ok = res.status === 200;
    if (ok) await res.json();
    return { success: ok, latency: Date.now() - sw, statusCode: res.status };
  } catch (e) {
    return { success: false, latency: Date.now() - sw, error: e.message };
  }
}

// ================================================================
//  RUNNER
// ================================================================

// Runner standar: semua concurrent sekaligus (Firebase)
async function runConcurrent(count, label, operationFn) {
  const start = Date.now();
  const results = await Promise.all(
    Array.from({ length: count }, (_, i) => operationFn(i))
  );
  return buildMetrics(label, results, Date.now() - start);
}

// Runner dengan batching (untuk external API yang punya rate limit)
async function runBatched(count, label, operationFn, batchSize = 5, delayMs = 1000) {
  const allResults = [];
  const start = Date.now();

  for (let i = 0; i < count; i += batchSize) {
    const batch = Array.from(
      { length: Math.min(batchSize, count - i) },
      (_, j) => operationFn(i + j)
    );
    const batchResults = await Promise.all(batch);
    allResults.push(...batchResults);

    process.stdout.write(
      `\r    Progress: ${Math.min(i + batchSize, count)}/${count} permintaan dikirim...`
    );

    if (i + batchSize < count) {
      await new Promise(r => setTimeout(r, delayMs));
    }
  }
  process.stdout.write('\r' + ' '.repeat(60) + '\r');

  return buildMetrics(label, allResults, Date.now() - start);
}

// ================================================================
//  METRICS
// ================================================================

function buildMetrics(label, results, totalMs) {
  const latencies = results.map(r => r.latency).sort((a, b) => a - b);
  const successes = results.filter(r => r.success).length;
  const errors    = results.length - successes;
  const sum       = latencies.reduce((a, b) => a + b, 0);
  const avg       = Math.round(sum / latencies.length);
  const p95i      = Math.ceil(latencies.length * 0.95) - 1;
  const p95       = latencies[Math.max(0, p95i)];
  const tput      = (results.length / (totalMs / 1000)).toFixed(1);

  return { label, results, totalMs, latencies, successes, errors, avg, p95, tput };
}

// ================================================================
//  OUTPUT
// ================================================================

function printMetrics(m) {
  const errRate = ((m.errors / m.results.length) * 100).toFixed(1);
  const icon    = m.errors === 0 ? '[OK]' : '[!!]';

  console.log(`  +-----------------------------------------------+`);
  console.log(`  | ${m.label.substring(0, 47).padEnd(47)} |`);
  console.log(`  +-------------------------+---------------------+`);
  console.log(`  | Berhasil / Gagal        | ${`${m.successes} / ${m.errors}`.padStart(19)} |`);
  console.log(`  | Error Rate              | ${`${errRate} %`.padStart(19)} |`);
  console.log(`  | Min Latency             | ${`${m.latencies[0]} ms`.padStart(19)} |`);
  console.log(`  | Max Latency             | ${`${m.latencies[m.latencies.length - 1]} ms`.padStart(19)} |`);
  console.log(`  | Avg Latency             | ${`${m.avg} ms`.padStart(19)} |`);
  console.log(`  | P95 Latency             | ${`${m.p95} ms`.padStart(19)} |`);
  console.log(`  | Throughput              | ${`${m.tput} req/s`.padStart(19)} |`);
  console.log(`  | Total Waktu             | ${`${m.totalMs} ms`.padStart(19)} |`);
  console.log(`  +-------------------------+---------------------+`);

  if (m.errors === 0) {
    console.log(`  ${icon}  Semua ${m.results.length} operasi berhasil\n`);
  } else {
    console.log(`  ${icon}  ${m.errors}/${m.results.length} gagal`);
    const errMsgs = [...new Set(
      m.results.filter(r => !r.success)
               .map(r => r.error ?? `HTTP ${r.statusCode}`)
    )].slice(0, 3);
    errMsgs.forEach(e => console.log(`       -> ${e.substring(0, 70)}`));
    console.log();
  }
}

function printStageHeader(userCount, stageNum) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`  TAHAP ${stageNum} — ${userCount} PENGGUNA BERSAMAAN`);
  console.log(`${'='.repeat(60)}`);
}

function printSectionTitle(title) {
  console.log(`\n  ---- ${title} ${'─'.repeat(Math.max(0, 45 - title.length))}`);
}

function printSummary(allStageResults) {
  const divider = '='.repeat(115);
  console.log(`\n${divider}`);
  console.log(`  RINGKASAN HASIL STRESS TEST — TEMAN ARAH`);
  console.log(`  Tanggal  : ${new Date().toLocaleString('id-ID')}`);
  console.log(`  Proyek   : smarthcane-11b47`);
  console.log(`${divider}`);

  // Tabel Firebase
  console.log(`\n  [A] FIREBASE (Realtime Database & Firestore)`);
  console.log(
    `  ${'Tahap'.padEnd(7)}` +
    `${'Users'.padStart(6)}` +
    `${'RTDB-W'.padStart(10)}` +
    `${'RTDB-R'.padStart(10)}` +
    `${'FST-W'.padStart(10)}` +
    `${'FST-R'.padStart(10)}` +
    `${'RTDB Err'.padStart(10)}` +
    `${'FST Err'.padStart(9)}`
  );
  console.log(`  ${'─'.repeat(75)}`);
  allStageResults.forEach(({ userCount, rtdbW, rtdbR, fstW, fstR }, i) => {
    console.log(
      `  ${ `Tahap ${i+1}`.padEnd(7)}` +
      `${String(userCount).padStart(6)}` +
      `${`${rtdbW.avg}ms`.padStart(10)}` +
      `${`${rtdbR.avg}ms`.padStart(10)}` +
      `${`${fstW.avg}ms`.padStart(10)}` +
      `${`${fstR.avg}ms`.padStart(10)}` +
      `${`${((rtdbW.errors/rtdbW.results.length)*100).toFixed(0)}%`.padStart(10)}` +
      `${`${((fstW.errors/fstW.results.length)*100).toFixed(0)}%`.padStart(9)}`
    );
  });

  // Tabel External API
  console.log(`\n  [B] EXTERNAL API`);
  console.log(
    `  ${'Tahap'.padEnd(7)}` +
    `${'Users'.padStart(6)}` +
    `${'OSRM Avg'.padStart(12)}` +
    `${'OSRM P95'.padStart(12)}` +
    `${'Nominatim'.padStart(12)}` +
    `${'OpenMeteo'.padStart(12)}` +
    `${'Err%'.padStart(8)}`
  );
  console.log(`  ${'─'.repeat(75)}`);
  allStageResults.forEach(({ userCount, osrm, nominatim, openMeteo }, i) => {
    const extErrors = osrm.errors + nominatim.errors + openMeteo.errors;
    const extTotal  = osrm.results.length + nominatim.results.length + openMeteo.results.length;
    console.log(
      `  ${ `Tahap ${i+1}`.padEnd(7)}` +
      `${String(userCount).padStart(6)}` +
      `${`${osrm.avg}ms`.padStart(12)}` +
      `${`${osrm.p95}ms`.padStart(12)}` +
      `${`${nominatim.avg}ms`.padStart(12)}` +
      `${`${openMeteo.avg}ms`.padStart(12)}` +
      `${`${((extErrors/extTotal)*100).toFixed(0)}%`.padStart(8)}`
    );
  });

  // Analisis
  console.log(`\n  ANALISIS PER TAHAP:`);
  allStageResults.forEach(({ userCount, rtdbW, fstW, osrm }, i) => {
    const rtdbErr = (rtdbW.errors / rtdbW.results.length) * 100;
    const fstErr  = (fstW.errors  / fstW.results.length)  * 100;
    let status;
    if (rtdbErr > 50 || fstErr > 50)         status = '[!!] BANYAK ERROR Firebase — periksa service account';
    else if (rtdbW.avg > 2000 || fstW.avg > 3000) status = '[!!] LAMBAT — Firebase mulai throttling';
    else if (osrm.avg > 3000)                 status = '[!!] OSRM lambat — server publik sedang tinggi';
    else if (rtdbW.avg > 800 || fstW.avg > 1500)  status = '[~~] SEDANG — performa dapat diterima';
    else                                      status = '[OK] BAIK — performa responsif';
    console.log(`    Tahap ${i+1} (${userCount} users): ${status}`);
  });

  console.log(`\n  KETERANGAN KOLOM:`);
  console.log(`    RTDB-W     = Realtime Database Write (update lokasi navigasi tunanetra)`);
  console.log(`    RTDB-R     = Realtime Database Read  (keluarga memantau lokasi)`);
  console.log(`    FST-W      = Firestore Write         (simpan riwayat navigasi)`);
  console.log(`    FST-R      = Firestore Read          (baca riwayat navigasi)`);
  console.log(`    OSRM       = Routing API (router.project-osrm.org) — rute jalan kaki`);
  console.log(`    Nominatim  = Reverse Geocoding (OpenStreetMap) — nama lokasi`);
  console.log(`    OpenMeteo  = Weather API (api.open-meteo.com) — data cuaca`);
  console.log(`    P95        = 95% permintaan selesai dalam waktu <= nilai ini`);
  console.log(`\n${divider}\n`);
}

// ================================================================
//  CLEANUP
// ================================================================

async function cleanup() {
  process.stdout.write('\n[CLEANUP] Menghapus data test dari Firebase...');
  try {
    await rtdb.ref(`stress_test/${SESSION_ID}`).remove();
    const snap = await db
      .collection('stress_test').doc(SESSION_ID)
      .collection('navigation_history').get();
    if (!snap.empty) {
      const batch = db.batch();
      snap.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
    }
    await db.collection('stress_test').doc(SESSION_ID).delete();
    console.log(' Selesai.');
  } catch (e) {
    console.log(` Gagal: ${e.message}`);
  }
}

// ================================================================
//  MAIN
// ================================================================

async function runStage(userCount, stageNum) {
  printStageHeader(userCount, stageNum);

  // --- Firebase ---
  printSectionTitle('FIREBASE — Realtime Database');
  console.log(`  Menulis update lokasi dari ${userCount} pengguna secara bersamaan...`);
  const rtdbW = await runConcurrent(userCount, 'RTDB Write  — Update Lokasi Navigasi', rtdbWrite);
  printMetrics(rtdbW);

  console.log(`  Membaca lokasi oleh ${userCount} anggota keluarga bersamaan...`);
  const rtdbR = await runConcurrent(userCount, 'RTDB Read   — Keluarga Pantau Lokasi', rtdbRead);
  printMetrics(rtdbR);

  printSectionTitle('FIREBASE — Firestore');
  console.log(`  Menyimpan riwayat navigasi ${userCount} pengguna bersamaan...`);
  const fstW = await runConcurrent(userCount, 'Firestore Write — Simpan Riwayat Navigasi', firestoreWrite);
  printMetrics(fstW);

  console.log(`  Membaca riwayat navigasi ${userCount} pengguna bersamaan...`);
  const fstR = await runConcurrent(userCount, 'Firestore Read  — Baca Riwayat Navigasi', firestoreRead);
  printMetrics(fstR);

  // --- External API ---
  // Batched karena public API ada rate limit
  const batchSize = Math.min(5, userCount);
  const batchDelay = 1100; // 1.1 detik — aman untuk Nominatim (maks 1 req/s)

  printSectionTitle('EXTERNAL API — OSRM Routing');
  console.log(`  Mengirim ${userCount} permintaan rute ke OSRM (batch ${batchSize}, jeda ${batchDelay}ms)...`);
  const osrm = await runBatched(userCount, 'OSRM — Routing Jalan Kaki (router.project-osrm.org)', osrmRouting, batchSize, batchDelay);
  printMetrics(osrm);

  printSectionTitle('EXTERNAL API — Nominatim Reverse Geocoding');
  console.log(`  Mengirim ${userCount} permintaan geocoding ke Nominatim (batch ${batchSize}, jeda ${batchDelay}ms)...`);
  const nominatim = await runBatched(userCount, 'Nominatim — Reverse Geocoding (nominatim.openstreetmap.org)', nominatimGeocode, batchSize, batchDelay);
  printMetrics(nominatim);

  printSectionTitle('EXTERNAL API — Open-Meteo Cuaca');
  console.log(`  Mengirim ${userCount} permintaan cuaca ke Open-Meteo (batch ${batchSize}, jeda ${batchDelay}ms)...`);
  const openMeteo = await runBatched(userCount, 'Open-Meteo — Data Cuaca (api.open-meteo.com)', openMeteoWeather, batchSize, batchDelay);
  printMetrics(openMeteo);

  return { userCount, rtdbW, rtdbR, fstW, fstR, osrm, nominatim, openMeteo };
}

async function main() {
  const arg    = process.argv[2] ?? 'all';
  const counts = STAGES[arg];

  if (!counts) {
    console.error(`Argumen tidak valid: "${arg}". Gunakan: 10 | 50 | 100 | 150 | 200 | all`);
    process.exit(1);
  }

  console.log(`\n${'='.repeat(60)}`);
  console.log(`  TEMAN ARAH — FIREBASE & EXTERNAL API STRESS TEST`);
  console.log(`  Proyek  : smarthcane-11b47`);
  console.log(`  Sesi    : ${SESSION_ID}`);
  console.log(`  Waktu   : ${new Date().toLocaleString('id-ID')}`);
  console.log(`${'='.repeat(60)}`);

  const allResults = [];
  for (let idx = 0; idx < counts.length; idx++) {
    const count  = counts[idx];
    const result = await runStage(count, idx + 1);
    allResults.push(result);

    if (idx < counts.length - 1) {
      process.stdout.write(`\n  Jeda 5 detik sebelum tahap berikutnya...`);
      await new Promise(r => setTimeout(r, 5000));
      console.log(' lanjut.\n');
    }
  }

  if (allResults.length > 1) {
    printSummary(allResults);
  }

  await cleanup();
  process.exit(0);
}

main().catch(err => {
  console.error('\nError fatal:', err.message);
  process.exit(1);
});
