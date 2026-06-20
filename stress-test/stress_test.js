'use strict';

const admin = require('firebase-admin');
const fetch = require('node-fetch');
const path = require('path');
const fs = require('fs');

// ── Firebase Init ───────────────────────────────────────────────────────────
const SERVICE_ACCOUNT_PATH = path.join(__dirname, 'serviceAccountKey.json');
if (!fs.existsSync(SERVICE_ACCOUNT_PATH)) {
  console.error('\n[ERROR] File serviceAccountKey.json tidak ditemukan di folder stress-test/');
  console.error('Cara download:');
  console.error('  Firebase Console → Project Settings → Service Accounts → Generate new private key');
  console.error('  Simpan file sebagai: stress-test/serviceAccountKey.json\n');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(SERVICE_ACCOUNT_PATH)),
  databaseURL: 'https://smarthcane-11b47-default-rtdb.asia-southeast1.firebasedatabase.app',
});

const db = admin.database();
const firestore = admin.firestore();

// ── Konstanta ───────────────────────────────────────────────────────────────
const RTDB_TEST_PATH = 'stress_test_live_tracking';
const FS_TEST_COLLECTION = 'stress_test_users';

// Koordinat area Indonesia untuk simulasi
const COORDS = [
  { lat: -6.2088, lng: 106.8456 },
  { lat: -6.9175, lng: 107.6191 },
  { lat: -7.2575, lng: 112.7521 },
  { lat: -8.6705, lng: 115.2126 },
  { lat: -3.8004, lng: 102.2655 },
  { lat: -0.9492, lng: 100.3543 },
  { lat:  1.4748, lng: 124.8421 },
  { lat: -5.1477, lng: 119.4327 },
];
const coord = () => COORDS[Math.floor(Math.random() * COORDS.length)];
const uid = (i) => `stress_${Date.now()}_${i}`;

// ── Timer ────────────────────────────────────────────────────────────────────
async function timed(fn) {
  const t = Date.now();
  try {
    await fn();
    return { ok: true, ms: Date.now() - t };
  } catch (e) {
    return { ok: false, ms: Date.now() - t, error: e.message };
  }
}

// ── Operasi Firebase RTDB ───────────────────────────────────────────────────
function rtdbWrite(userId) {
  const c = coord();
  return timed(() =>
    db.ref(`${RTDB_TEST_PATH}/${userId}`).set({
      lat: c.lat, lng: c.lng, accuracy: 5, timestamp: Date.now(),
    })
  );
}

function rtdbRead(userId) {
  return timed(async () => {
    const snap = await db.ref(`${RTDB_TEST_PATH}/${userId}`).get();
    if (!snap.exists()) throw new Error('Data tidak ditemukan');
  });
}

// ── Operasi Firestore ───────────────────────────────────────────────────────
function firestoreWrite(userId) {
  return timed(() =>
    firestore.collection(FS_TEST_COLLECTION).doc(userId).set({
      name: `Stress User ${userId}`,
      role: 'tunanetra',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    })
  );
}

function firestoreRead(userId) {
  return timed(async () => {
    const doc = await firestore.collection(FS_TEST_COLLECTION).doc(userId).get();
    if (!doc.exists) throw new Error('Dokumen tidak ditemukan');
  });
}

// ── Operasi External API ────────────────────────────────────────────────────
function osrmRouting() {
  const from = coord();
  const to = coord();
  return timed(() =>
    fetch(
      `https://router.project-osrm.org/route/v1/foot/${from.lng},${from.lat};${to.lng},${to.lat}?overview=false`,
      { timeout: 15000 }
    ).then(r => {
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return r.json();
    })
  );
}

function nominatimGeocode() {
  const c = coord();
  return timed(() =>
    fetch(
      `https://nominatim.openstreetmap.org/reverse?lat=${c.lat}&lon=${c.lng}&format=json`,
      { timeout: 15000, headers: { 'User-Agent': 'TemanArahStressTest/1.0 (stress-test)' } }
    ).then(r => {
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return r.json();
    })
  );
}

function openMeteoWeather() {
  const c = coord();
  return timed(() =>
    fetch(
      `https://api.open-meteo.com/v1/forecast?latitude=${c.lat}&longitude=${c.lng}&current_weather=true`,
      { timeout: 15000 }
    ).then(r => {
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return r.json();
    })
  );
}

// ── Batch runner ────────────────────────────────────────────────────────────
async function runBatched(tasks, batchSize, delayMs = 0) {
  const results = [];
  for (let i = 0; i < tasks.length; i += batchSize) {
    const batch = tasks.slice(i, i + batchSize).map(fn => fn());
    const res = await Promise.all(batch);
    results.push(...res);
    if (delayMs && i + batchSize < tasks.length) {
      await new Promise(r => setTimeout(r, delayMs));
    }
  }
  return results;
}

// ── Statistik ───────────────────────────────────────────────────────────────
function stats(results) {
  const sorted = results.map(r => r.ms).sort((a, b) => a - b);
  const errors = results.filter(r => !r.ok).length;
  const total = results.length;
  const avg = Math.round(sorted.reduce((a, b) => a + b, 0) / total);
  const p95 = sorted[Math.ceil(total * 0.95) - 1] ?? sorted[total - 1];
  return {
    avg, p95,
    min: sorted[0],
    max: sorted[total - 1],
    errors,
    total,
    errorRate: ((errors / total) * 100).toFixed(1),
  };
}

const SEP = '─'.repeat(65);
const SEP2 = '═'.repeat(65);

function printResult(label, s) {
  const errFlag = parseFloat(s.errorRate) > 0 ? ' ⚠' : '';
  console.log(`\n  ${label}${errFlag}`);
  console.log(`  ${SEP}`);
  console.log(`  Avg: ${s.avg}ms  |  P95: ${s.p95}ms  |  Min: ${s.min}ms  |  Max: ${s.max}ms`);
  console.log(`  Total: ${s.total}  |  Errors: ${s.errors}  |  Error Rate: ${s.errorRate}%`);
}

// ── Cleanup ──────────────────────────────────────────────────────────────────
async function cleanup(userIds) {
  process.stdout.write('\n[CLEANUP] Menghapus data test... ');
  try {
    await db.ref(RTDB_TEST_PATH).remove();

    // Firestore batch delete (max 500 per batch)
    for (let i = 0; i < userIds.length; i += 500) {
      const batch = firestore.batch();
      userIds.slice(i, i + 500).forEach(id =>
        batch.delete(firestore.collection(FS_TEST_COLLECTION).doc(id))
      );
      await batch.commit();
    }
    console.log('selesai.');
  } catch (e) {
    console.log(`error: ${e.message}`);
  }
}

// ── Stage ────────────────────────────────────────────────────────────────────
async function runStage(n) {
  const userIds = Array.from({ length: n }, (_, i) => uid(i));

  console.log(`\n${SEP2}`);
  console.log(`  STRESS TEST — ${n} PENGGUNA CONCURRENT`);
  console.log(`  Waktu mulai: ${new Date().toLocaleString('id-ID')}`);
  console.log(SEP2);

  // ── RTDB ──
  console.log('\n---- FIREBASE — Realtime Database');
  process.stdout.write(`  Write ${n} records... `);
  const rtdbWriteRes = await Promise.all(userIds.map(id => rtdbWrite(id)));
  console.log('selesai');
  printResult(`RTDB Write (live_tracking) — ${n} concurrent`, stats(rtdbWriteRes));

  await new Promise(r => setTimeout(r, 300));

  process.stdout.write(`  Read ${n} records... `);
  const rtdbReadRes = await Promise.all(userIds.map(id => rtdbRead(id)));
  console.log('selesai');
  printResult(`RTDB Read (live_tracking) — ${n} concurrent`, stats(rtdbReadRes));

  // ── Firestore ──
  console.log('\n---- FIREBASE — Firestore');
  process.stdout.write(`  Write ${n} docs... `);
  const fsWriteRes = await Promise.all(userIds.map(id => firestoreWrite(id)));
  console.log('selesai');
  printResult(`Firestore Write (${FS_TEST_COLLECTION}) — ${n} concurrent`, stats(fsWriteRes));

  await new Promise(r => setTimeout(r, 300));

  process.stdout.write(`  Read ${n} docs... `);
  const fsReadRes = await Promise.all(userIds.map(id => firestoreRead(id)));
  console.log('selesai');
  printResult(`Firestore Read (${FS_TEST_COLLECTION}) — ${n} concurrent`, stats(fsReadRes));

  // ── OSRM ──
  // Batch 5 concurrent, no delay — OSRM terbatas tapi toleran
  const osrmN = Math.min(n, 50);
  console.log(`\n---- EXTERNAL API — OSRM Routing (${osrmN} requests, batch 5)`);
  process.stdout.write('  Mengirim requests... ');
  const osrmRes = await runBatched(
    Array.from({ length: osrmN }, () => osrmRouting),
    5, 100
  );
  console.log('selesai');
  printResult(`OSRM Routing — ${osrmN} requests`, stats(osrmRes));

  // ── Nominatim ──
  // Maksimal 1 req/sec sesuai usage policy Nominatim
  const nominatimN = Math.min(n, 10);
  console.log(`\n---- EXTERNAL API — Nominatim Reverse Geocoding (${nominatimN} requests, 1/detik)`);
  process.stdout.write('  Mengirim requests... ');
  const nominatimRes = await runBatched(
    Array.from({ length: nominatimN }, () => nominatimGeocode),
    1, 1100
  );
  console.log('selesai');
  printResult(`Nominatim Geocoding — ${nominatimN} requests`, stats(nominatimRes));

  // ── Open-Meteo ──
  const meteoN = Math.min(n, 50);
  console.log(`\n---- EXTERNAL API — Open-Meteo Cuaca (${meteoN} requests, batch 10)`);
  process.stdout.write('  Mengirim requests... ');
  const meteoRes = await runBatched(
    Array.from({ length: meteoN }, () => openMeteoWeather),
    10, 100
  );
  console.log('selesai');
  printResult(`Open-Meteo Cuaca — ${meteoN} requests`, stats(meteoRes));

  // ── Jeda screenshot ──
  const JEDA_DETIK = 30;
  console.log(`\n${'─'.repeat(65)}`);
  console.log(`  SEMUA TEST SELESAI — silakan screenshot semua tool sekarang`);
  console.log(`  Cleanup otomatis dalam ${JEDA_DETIK} detik...`);
  console.log(`${'─'.repeat(65)}`);
  for (let i = JEDA_DETIK; i > 0; i--) {
    process.stdout.write(`\r  Cleanup dalam: ${String(i).padStart(2, '0')} detik...`);
    await new Promise(r => setTimeout(r, 1000));
  }
  process.stdout.write('\r' + ' '.repeat(40) + '\r');

  // ── Cleanup ──
  await cleanup(userIds);

  console.log(`\n${SEP2}`);
  console.log(`  TEST SELESAI — ${new Date().toLocaleString('id-ID')}`);
  console.log(`${SEP2}\n`);
}

// ── Entry Point ───────────────────────────────────────────────────────────────
async function main() {
  const arg = process.argv[2];
  if (!arg) {
    console.error('Usage: node stress_test.js <jumlah|all>');
    console.error('Contoh: node stress_test.js 10');
    process.exit(1);
  }

  const stages = arg === 'all' ? [10, 50, 100, 200] : [parseInt(arg, 10)];

  if (stages.some(isNaN)) {
    console.error(`[ERROR] Argumen tidak valid: "${arg}"`);
    process.exit(1);
  }

  for (let i = 0; i < stages.length; i++) {
    await runStage(stages[i]);
    if (i < stages.length - 1) {
      console.log('Menunggu 15 detik sebelum tahap berikutnya...\n');
      await new Promise(r => setTimeout(r, 15000));
    }
  }

  await admin.app().delete();
  process.exit(0);
}

main().catch(err => {
  console.error('\n[FATAL]', err.message);
  process.exit(1);
});
