# Cloud Functions Setup Guide

## Overview
Firebase Cloud Function untuk mengirim OTP email ke user saat registrasi.

**Directory:** `functions/`
- `package.json` - Dependencies (Firebase Functions, Admin SDK, Nodemailer)
- `index.js` - Cloud Function code untuk sendOtpEmail
- `.env.example` - Template konfigurasi email

---

## Setup Steps

### Step 1: Install Firebase CLI (jika belum)

```bash
npm install -g firebase-tools
```

### Step 2: Initialize Functions Project

Di root project:

```bash
firebase init functions
```

Pilih:
- Project: `my-app` (atau project ID Anda)
- Language: `JavaScript`
- Install dependencies: `Yes`

### Step 3: Copy Files

1. Copy isi `functions/index.js` ke `functions/index.js` yang sudah ada
2. Update `functions/package.json` dengan dependencies dari file template
3. Copy `.env.example` ke `functions/.env` dan isi konfigurasinya

### Step 4: Configure Email Provider

#### Option A: Gmail (untuk development/testing)

1. **Setup Gmail App Password:**
   - Buka: https://myaccount.google.com/apppasswords
   - Login dengan Gmail Anda
   - Pilih: Mail → Windows Computer (atau device Anda)
   - Akan generate 16-character password
   - Copy password ini

2. **Edit `functions/.env`:**
   ```env
   EMAIL_PROVIDER=gmail
   GMAIL_EMAIL=your-email@gmail.com
   GMAIL_APP_PASSWORD=xxxx xxxx xxxx xxxx
   EMAIL_FROM_ADDRESS=your-email@gmail.com
   EMAIL_FROM_NAME=Smart Cane Assistant
   ```

#### Option B: SendGrid (untuk production)

1. **Setup SendGrid Account:**
   - Daftar di: https://sendgrid.com/
   - Verify sender email
   - Buat API Key: Settings → API Keys → Create API Key

2. **Edit `functions/.env`:**
   ```env
   EMAIL_PROVIDER=sendgrid
   SENDGRID_API_KEY=SG.xxxxxxxxxxxxxxxxxxxx
   EMAIL_FROM_ADDRESS=noreply@smartcane.app
   EMAIL_FROM_NAME=Smart Cane Assistant
   ```

3. **Install SendGrid package** (tambahkan ke `functions/package.json`):
   ```bash
   cd functions
   npm install @sendgrid/mail
   ```

### Step 5: Deploy Cloud Function

```bash
# Deploy hanya functions
firebase deploy --only functions

# Atau dengan verbose logging
firebase deploy --only functions --debug
```

**Output akan terlihat:**
```
✔  functions[sendOtpEmail(us-central1)] Successful create operation.
Function URL: https://us-central1-[PROJECT_ID].cloudfunctions.net/sendOtpEmail
REST API (HTTP) Endpoint: https://us-central1-[PROJECT_ID].cloudfunctions.net/sendOtpEmail
```

### Step 6: Get Function URL

Copy function URL dari output. Format: `https://[REGION]-[PROJECT_ID].cloudfunctions.net/sendOtpEmail`

Contoh: `https://us-central1-my-app.cloudfunctions.net/sendOtpEmail`

---

## Update AuthService untuk Menggunakan Cloud Function

### Di `lib/services/email_otp_service.dart`

Edit method `_sendViaCloudFunction()` (baris ~120):

```dart
Future<void> _sendViaCloudFunction(String email, String otp) async {
  try {
    print('   🔧 Calling Firebase Cloud Function...');

    // GANTI DENGAN URL ANDA
    const CLOUD_FUNCTION_URL =
        'https://us-central1-my-app.cloudfunctions.net/sendOtpEmail';

    final response = await http.post(
      Uri.parse(CLOUD_FUNCTION_URL),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'otp': otp,
        'appName': 'Smart Cane Assistant',
      }),
    );

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body);
      throw Exception(errorBody['message'] ?? 'Cloud Function error: ${response.statusCode}');
    }

    final result = jsonDecode(response.body);
    if (!result['success']) {
      throw Exception(result['message'] ?? 'Cloud Function returned false');
    }

    print('   ✅ Cloud Function succeeded!');
  } catch (e) {
    print('   ❌ Cloud Function error: $e');
    throw Exception('Cloud Function failed: $e');
  }
}
```

Tambahkan dependency di `pubspec.yaml`:
```yaml
dependencies:
  http: ^1.1.0
```

---

## Test Cloud Function

### Via cURL (Terminal)

```bash
curl -X POST https://[YOUR_FUNCTION_URL] \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "otp": "123456",
    "appName": "Smart Cane Assistant"
  }'
```

### Via Firebase Console

1. Buka: https://console.firebase.google.com/
2. Project: `my-app`
3. Functions → `sendOtpEmail`
4. Testing tab → Create a test request
5. Input JSON body:
   ```json
   {
     "email": "your-email@gmail.com",
     "otp": "123456",
     "appName": "Smart Cane Assistant"
   }
   ```
6. Run test

---

## Troubleshooting

### Error: "Gmail credentials not configured"
**Solution:** Pastikan `.env` di `functions/` folder memiliki:
- `GMAIL_EMAIL`
- `GMAIL_APP_PASSWORD`

### Error: "CORS error" saat app memanggil function
**Solution:** Already handled di code - CORS headers sudah di-set.

### Error: "Timeout"
**Solution:** 
- Check internet connection
- Verify Cloud Function deploy berhasil
- Check Cloud Function logs: `firebase functions:log`

### Error: "Invalid app password"
**Solution:**
- Buat app password baru di https://myaccount.google.com/apppasswords
- Make sure: 2-factor authentication enabled di Gmail
- 2-factor auth harus sudah setup sebelum bisa buat app password

### Email tidak dikirim tapi function return success
**Solution:**
- Check spam folder
- Verify email domain in SendGrid settings (jika pakai SendGrid)
- Check Cloud Function logs untuk details

---

## Cloud Function Logs

Lihat real-time logs:
```bash
firebase functions:log
```

Atau di Firebase Console:
1. Buka: https://console.firebase.google.com/
2. Project → Functions → sendOtpEmail
3. Logs tab

---

## Monitoring

Function logs akan tersimpan di:
- **Firebase Console:** Functions → sendOtpEmail → Logs tab
- **Firestore:** collection `email_logs` (untuk tracking email sent/failed)

---

## Security Best Practices

1. **Jangan expose credentials di code**
   - Gunakan `.env` file untuk store sensitif data
   - Add `.env` to `.gitignore`

2. **Setup Firebase Security Rules**
   - Hanya allow Cloud Function untuk call Firestore
   - Block direct user access ke email_logs collection

3. **Rate limiting**
   - Implementasi: max 5 OTP requests per email per 24 jam
   - Check di Firestore sebelum send

4. **Production checklist**
   - Setup SendGrid (lebih reliable dari Gmail)
   - Setup email domain verification
   - Monitor bounce rates
   - Setup error alerts

---

## Additional Notes

- OTP valid untuk 10 menit (configurable di code)
- Email template responsive untuk mobile
- Support tanto Gmail maupun SendGrid
- Logs tersimpan di Firestore untuk audit trail
- Suitable untuk production use

---

## Next Steps

1. ✅ Setup Cloud Function (sudah ada skeleton code)
2. ✅ Deploy ke Firebase
3. ⏳ Update AuthService untuk gunakan Cloud Function URL
4. ⏳ Test end-to-end flow
