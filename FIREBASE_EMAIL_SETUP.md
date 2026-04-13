# 📧 Firebase Email Verification Setup (Production)

## Overview

Email verification menggunakan Firebase built-in system. User akan menerima email dari Firebase dengan verification link. Setelah diklik, email akan ter-verify.

---

## 🔧 Step-by-Step Setup

### **Step 1: Firebase Console - Setup Email Template**

1. Buka: https://console.firebase.google.com/
2. Select Project: **smarthcane-11b47**
3. Navigate ke: **Authentication → Templates** (atau "Email Templates")
4. Cari: **Email Verification** template
5. Click **edit icon** (pensil)

### **Step 2: Customize Email Template**

Ubah **Subject** dan **Email Body** dengan template Anda sendiri.

**Contoh Template (Copy-paste):**

```
Subject:
🔗 Verifikasi Email SmartCane Anda

Email Body:
Halo [USER_NAME],

Terima kasih telah mendaftar di SmartCane!

Silakan klik link di bawah untuk memverifikasi email Anda:
[VERIFICATION_LINK]

Atau gunakan kode verifikasi ini:
[VERIFICATION_CODE]

Link berlaku selama 24 jam.

Jika Anda tidak mendaftar, abaikan email ini.

—
SmartCane Support Team
```

**PENTING:** 
- ❌ Jangan ubah placeholder: `[VERIFICATION_LINK]`, `[USER_NAME]`, `[VERIFICATION_CODE]`
- ✅ Customize tekst sesuai brand Anda

### **Step 3: Setup Custom Display Name (Optional tapi Recommended)**

1. Settings → General
2. Scroll ke "Public-facing name"
3. Isi: **SmartCane Support**
4. Email dari akan terlihat lebih profesional

### **Step 4: Verify Authentication Configuration**

Pastikan di Firebase Console:

✅ **Authentication:**
- Email/Password provider: **ENABLED**
- App registered: **com.example.my_app** (Android)

✅ **Firestore:**
- Database: **CREATED**

✅ **Project Settings:**
- Project ID: **smarthcane-11b47**
- No errors in "Warnings"

---

## 📱 App-Side Features (SUDAH IMPLEMENTED)

### **1. Registration dengan Email Verification**

```dart
// In register_screen.dart
final user = await _authService.registerWithEmailPasswordAndVerification(
  email: email,
  password: password,
  name: name,
  phoneNumber: phone,
  userType: UserType.tunanetra,
);

// User otomatis ter-create
// Verification email AUTOMATICALLY dikirim ke user
// Firestore: emailVerified = false
```

**Log Output:**
```
[REGISTER] STEP 1: Validating inputs
[REGISTER] STEP 2: Creating Firebase Auth account
[REGISTER] STEP 3: Sending verification email
✅ Verification email SENT to: user@email.com
[REGISTER] STEP 4: Saving user profile to Firestore
```

### **2. Login dengan Email Verification Check**

```dart
// In login_screen.dart
final userCredential = await _authService.loginWithEmailPasswordNew(email, password);

// Auto-check email verification status
final isVerified = await _authService.isEmailVerified();

if (!isVerified) {
  // Show warning: "Email belum diverifikasi"
  // Button: "Kirim Ulang Email Verifikasi"
} else {
  // Allow login, navigate to home
}
```

**User Flow:**
1. User login dengan email+password
2. Jika email belum verified → Warning ditampilkan
3. Button "Kirim Ulang" untuk resend verification email
4. Setelah verified → Normal login

### **3. Resend Verification Email**

```dart
// User bisa resend dari 2 tempat:

// A. Di login screen (jika belum verify)
await _authService.resendVerificationEmail();

// B. Di profile settings (after login)
await _authService.resendVerificationEmail();
```

**Features:**
- ✅ Automatic retry 3x jika gagal
- ✅ Timeout handling 30s per attempt
- ✅ User-friendly error messages
- ✅ Prevent resend jika sudah verified

### **4. Check Email Verification**

```dart
// Check current status anytime
final isVerified = await _authService.isEmailVerified();

// Auto-refresh dari Firebase dan return true/false
```

---

## ✅ Testing Checklist

Setelah setup Firebase Console:

- [ ] Register user baru dengan email yang bisa diakses
- [ ] Buka email inbox → Cari email dari Firebase
- [ ] Klik verification link di email
- [ ] Firebase Auth Console → Email verified status berubah ✅
- [ ] Login user → Tidak ada warning (sudah verified)
- [ ] Delete user dan tes resend feature
- [ ] Check Firestore → emailVerified field status 

---

## 🚨 Troubleshooting

### **Email tidak masuk ke inbox?**

1. **Cek Spam/Junk folder** ✅ Priority #1
2. Pastikan Email/Password provider **ENABLED** di Firebase Console
3. Check Firebase Console → Authentication → Users → Status
4. Verify email domain configured di Firebase Console

### **[Optional] Setup Custom Email Provider**

Jika Firebase built-in tidak cukup (e.g., custom templates, tracking):

**Option A: SendGrid Integration (Recommended)**
- More control over template & styling
- Better delivery rates
- Requires SendGrid account + API key

**Option B: Cloud Functions + Custom Email Service**
- Already partially setup (`functions/`)
- Need to activate Firebase Blaze plan
- Requires deployment

**Option C: Firebase Extension**
- Pre-built extension untuk email
- Easy to setup
- No coding required

---

## 📊 Monitoring & Analytics

**Firebase Console → Authentication:**
- Users created count
- Email verification rate (%)
- Sign-in methods used

**Cloud Firestore → users collection:**
- emailVerified field (true/false)
- verificationSentAt timestamp

---

## 📝 Code References

**AuthService Methods:**
- `registerWithEmailPasswordAndVerification()` - Register + auto-send verification
- `isEmailVerified()` - Check current email status (auto-refresh)
- `resendVerificationEmail()` - Resend with retry logic
- `checkAndWaitForEmailVerification()` - Wait for user to verify (polling)

**Login Screen:**
- Auto-checks email verification after login
- Shows warning + "Resend" button jika belum verify

**Register Screen:**
- Auto-sends verification email after registration
- Shows success message with pairing code
- Redirects to login after 3 seconds

---

## 🔒 Security Notes

✅ **Best Practices Implemented:**
- Email verification required (2-step protection)
- Firestore has emailVerified field tracking
- resendVerificationEmail() prevents re-verify jika sudah verified
- Proper error handling & logging

⚠️ **Next Steps (Future):**
- Implement rate-limiting di Firestore (prevent spam resend)
- Add verification reminder email (3 hari belum verify)
- Dashboard untuk admin track unverified users
- GDPR compliance (delete unverified after 30 hari)

---

## 🎯 Current Status

✅ **App-side implementation: COMPLETE**
- Registration dengan auto email verification
- Login dengan verification check
- Resend feature dengan retry logic
- Proper logging & error handling

⏳ **Pending (Your Action):**
1. Setup Email Template di Firebase Console
2. Test dengan user baru
3. Verify production configuration

---

Last Updated: April 9, 2026
SmartCane Project
