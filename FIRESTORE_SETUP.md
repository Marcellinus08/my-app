# 🔥 Firestore Setup & Troubleshooting Guide

## ⏰ Status Saat Ini
**PROBLEM**: `Write timeout` - Firestore backend tidak accessible

---

## ✅ CHECKLIST SETUP (Lakukan Urutan Ini)

### 1️⃣ Pastikan Firestore Database Sudah Ada

**Buka Firebase Console:**
- Url: https://console.firebase.google.com/
- Pilih project: `my-app`

**Check Firestore Database:**
- Di sidebar kiri, cari menu `Build` → `Firestore Database`
- Jika **belum ada**:
  - Klik `Create Database`
  - Pilih: `Start in Test mode` (untuk development)
  - Location: `asia-southeast1` (atau dekat dengan lokasi Anda)
  - Klik `Create`

**Tunggu 1-2 menit** sampai database selesai dibuat.

---

### 2️⃣ Deploy Security Rules

**Di Firebase Console:**
1. Masuk ke `Firestore Database` → Tab `Rules`
2. Copy-paste isi file `firestore.rules` dari project:

```
rules_version = 2;

service cloud.firestore {
  match /databases/{database}/documents {
    
    // OTP Collection - Allow creation and verification
    match /otp_codes/{document=**} {
      allow create, write: if request.resource.data.email is string;
      allow read: if true;
      allow update: if true;
      allow delete: if false;
    }
    
    // Users Collection - Registration and profile data
    match /users/{uid} {
      allow create: if 
        request.resource.data.keys().hasAll(['email', 'username']) &&
        request.resource.data.email is string &&
        request.resource.data.username is string;
      allow read: if request.auth.uid == uid || true;
      allow update: if request.auth.uid == uid || true;
      allow delete: if false;
    }
    
    // Pairing Codes - For linking TunaNetra with Family
    match /pairing_codes/{code} {
      allow create: if request.resource.data.keys().hasAll(['userId', 'code']);
      allow read: if true;
      allow update: if true;
      allow delete: if false;
    }
    
    // Default deny all
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

3. Klik `Publish` (top-right)
4. Tunggu sampai publish selesai ✅

---

### 3️⃣ Check Android Emulator Network

**Di Emulator, buka Settings:**
- `Settings` → `About` → `Status`
- Check kalau ada `IP address` (bukan "Unknown")
- Kalau hanya ada IPv6 tapi tidak ada IPv4, emulator offline

**Jika offline, coba:**
```bash
# Di terminal (stop app dulu dengan Ctrl+C)
flutter pub get
flutter run
```

---

### 4️⃣ Verify google-services.json

**File location:** `android/app/google-services.json`

**Buka dan check:**
- Temukan field `"project_id"`
- Harus match dengan project di Firebase Console
- Contoh:
  ```json
  {
    "project_info": {
      "project_id": "my-app-12345",
      ...
    }
  }
  ```

**Jika tidak ada atau tidak match:**
1. Buka Firebase Console
2. Project Settings (gear icon top-left)
3. Tab `Service Accounts`
4. Klik `Generate new private key` atau download `google-services.json`
5. Replace file di `android/app/google-services.json`
6. Run: `flutter pub get`
7. Run: `flutter run`

---

## 🚀 QUICK TEST (Setelah Setup)

Setelah selesai:

1. **Restart Flutter app**:
   ```bash
   flutter run
   ```

2. **Lihat console output** - cari ini:
   - ✅ `✅ Firestore write test PASSED` → SUCCESS!
   - ❌ `❌ Firestore connection test FAILED` → Ada masalah, lanjut ke troubleshooting bawah

3. **Jika berhasil**, di Firestore Console → `Firestore Database` akan ada collection `_test` (test document)

---

## 🔧 ADVANCED TROUBLESHOOTING

### Problem: "Still getting Write timeout"

**Solusi 1: Enable Test Mode (Temporary)**
1. Firebase Console → `Firestore` → Tab `Rules`
2. Replace dengan:
   ```
   rules_version = 2;
   service cloud.firestore {
     match /databases/{database}/documents {
       match /{document=**} {
         allow read, write; // TEMPORARY FOR TESTING
       }
     }
   }
   ```
3. Klik `Publish`
4. Test app lagi
5. **Jangan lupa:** Ganti kembali ke security rules yang proper sebelum production!

**Solusi 2: Restart Emulator**
1. Di Android Studio: `AVD Manager` → pilih emulator → tombol `Stop` (⏹️)
2. Tunggu 10 detik
3. Run: `flutter run`

**Solusi 3: Wipe Emulator Data**
1. `AVD Manager` → pilih emulator → dropdown `...` → `Wipe Data`
2. Restart emulator
3. Run: `flutter run`

---

## 📱 Testing OTP Registration

Setelah Firestore connected:

1. **Di app, klik tab `Daftar`**
2. **Pilih `Pengguna`**
3. **Isi form:**
   - Email: `test@gmail.com`
   - Nama: `Budi Santoso`
   - HP: `081234567890`
   - Kontak Keluarga: `Ibu Siti`
   - HP Keluarga: `082345678901`
4. **Klik `DAFTAR & KIRIM OTP`**

**Output di terminal harus:**
```
╔═══════════════════════════════════════════════════════╗
║ [PENGGUNA REGISTRATION] USER CLICKED DAFTAR BUTTON   ║
╚═══════════════════════════════════════════════════════╝

[AUTH] STEP 1: Validating input
✅ Email format valid: test@gmail.com

[OTP SERVICE] STEP 2: Generating OTP code
✅ OTP generated: 123456

🔥 [OTP SERVICE] STEP 4: Saving OTP to Firestore
✅ Firestore write SUCCESS in 2s
```

---

## ❓ FAQ

**Q: Berapa lama Firestore database selesai dibuat?**  
A: Biasanya 1-2 menit. Jika sudah 5 menit masih pending, refresh halaman browser.

**Q: Apakah saya perlu create collection manual?**  
A: Tidak! App akan auto-create collection saat first write.

**Q: Bagaimana kalau emulator offline terus?**  
A: Coba dengan physical device (bukan emulator). Tapi buat testing, emulator ok juga asal punya internet.

**Q: Apakah semua orang bisa see my data di Test Mode?**  
A: Ya, test mode allow semua baca-tulis tanpa auth. JANGAN gunakan di production!

---

## 📞 Support

Jika masih error:
1. Check console output - cari error message yang spesifik
2. Copy error message
3. Search di: https://firebase.google.com/support
4. Atau check di: https://stackoverflow.com/ dengan tag `firebase` + `flutter`

