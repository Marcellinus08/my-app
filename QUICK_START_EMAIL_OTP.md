# 🚀 Quick Start: Email OTP Setup

## 5-Minute Setup

### 1️⃣ Setup Gmail App Password (2 min)

1. Buka: https://myaccount.google.com/apppasswords
2. Login dengan Gmail Anda
3. Pilih: Mail → Windows Computer
4. Generate dan copy 16-character password
5. Simpan di tempat aman

### 2️⃣ Configure Cloud Functions (2 min)

1. **Edit `functions/.env`:**
   ```env
   EMAIL_PROVIDER=gmail
   GMAIL_EMAIL=your-email@gmail.com
   GMAIL_APP_PASSWORD=xxxx xxxx xxxx xxxx
   EMAIL_FROM_ADDRESS=your-email@gmail.com
   EMAIL_FROM_NAME=Smart Cane Assistant
   ```

2. **Save file**

### 3️⃣ Deploy Cloud Function (1 min)

```bash
cd functions
npm install
firebase deploy --only functions
```

**Copy output URL** (contoh: `https://us-central1-my-app.cloudfunctions.net/sendOtpEmail`)

### 4️⃣ Update App Code

Di `lib/services/email_otp_service.dart` line ~151:

```dart
const CLOUD_FUNCTION_URL =
    'https://us-central1-my-app.cloudfunctions.net/sendOtpEmail';  // Paste URL here
```

### 5️⃣ Add Dependency

Di `pubspec.yaml`:

```yaml
dependencies:
  http: ^1.1.0
```

Run:
```bash
flutter pub get
```

---

## ✅ Done! Test It

```bash
flutter run
```

1. Register dengan email
2. Check email inbox untuk OTP
3. Masukkan OTP untuk complete registration

---

## 📝 If Something Breaks

| Error | Solution |
|-------|----------|
| "Cloud Function error: 404" | URL salah - check di `firebase functions:list` |
| "Gmail credentials not configured" | `.env` tidak ada di `functions/` folder |
| "Timeout" | Check internet, atau run `firebase functions:log` |
| "Email tidak dikirim" | Check spam folder, atau verify di [Gmail settings](https://myaccount.google.com/security) |

---

## 📚 Full Documentation

- **Setup detail:** [CLOUD_FUNCTIONS_SETUP.md](CLOUD_FUNCTIONS_SETUP.md)
- **Integration steps:** [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)

---

## 🔑 Important

- ⚠️ Jangan commit `.env` file - sudah di `.gitignore`
- ⚠️ Jangan share GMAIL_APP_PASSWORD
- ✅ Cloud Function URL aman untuk di-share

---

That's it! Enjoy real email OTP! 🎉
