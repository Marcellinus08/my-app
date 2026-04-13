# Implementation Steps: Email OTP via Cloud Functions

## Overview
Integrasi Cloud Functions ke Flutter app untuk mengirim OTP via email real.

---

## Step 1: Add Dependencies ke `pubspec.yaml`

Di file `pubspec.yaml`, tambahkan dependency:

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^2.24.2
  firebase_auth: ^4.17.0
  cloud_firestore: ^4.14.0
  http: ^1.1.0                    # ADD THIS LINE
  # ... dependencies lainnya
```

Kemudian run:
```bash
flutter pub get
```

---

## Step 2: Update `lib/services/email_otp_service.dart`

### 2.1: Add Import di top of file

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import 'package:http/http.dart' as http;    // ADD THIS
import 'dart:convert';                       // ADD THIS for jsonEncode/Decode
```

### 2.2: Update method `_sendViaCloudFunction()` (baris ~120)

**FIND:**
```dart
Future<void> _sendViaCloudFunction(String email, String otp) async {
  try {
    print('   🔧 Attempting Firebase Cloud Function...');
    print('   📝 Setup instructions:');
    print('   1. Create Cloud Function in Firebase Console');
    // ... existing comments ...

    const CLOUD_FUNCTION_URL =
        'https://YOUR_REGION-YOUR_PROJECT_ID.cloudfunctions.net/sendOtpEmail';

    print('   📡 Calling Cloud Function...');
    // Example code (uncomment when Cloud Function is ready):
    /*
    final response = await http.post(
      Uri.parse(CLOUD_FUNCTION_URL),
      // ... etc
    */
```

**REPLACE WITH:**
```dart
Future<void> _sendViaCloudFunction(String email, String otp) async {
  try {
    print('   🔧 Calling Firebase Cloud Function...');

    // TODO: Ganti dengan URL Cloud Function Anda
    // Dapatkan dari: firebase deploy --only functions
    // Format: https://[REGION]-[PROJECT_ID].cloudfunctions.net/sendOtpEmail
    const CLOUD_FUNCTION_URL =
        'https://us-central1-my-app.cloudfunctions.net/sendOtpEmail';

    print('   📡 Sending request to Cloud Function...');
    print('      URL: $CLOUD_FUNCTION_URL');

    final response = await http
        .post(
          Uri.parse(CLOUD_FUNCTION_URL),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'otp': otp,
            'appName': 'Smart Cane Assistant',
          }),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () =>
              throw Exception('Cloud Function timeout (30s) - check internet'),
        );

    print('   📬 Response received: ${response.statusCode}');

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body);
      throw Exception(
          errorBody['message'] ?? 'Cloud Function error: ${response.statusCode}');
    }

    final result = jsonDecode(response.body);
    if (!result['success']) {
      throw Exception(
          result['message'] ?? 'Cloud Function returned success: false');
    }

    print('   ✅ Cloud Function succeeded! Email queued for sending.');
  } catch (e) {
    print('   ❌ Cloud Function error: $e');
    throw Exception('Failed to send via Cloud Function: $e');
  }
}
```

---

## Step 3: Update `lib/services/auth_service.dart`

### 3.1: Change import dari OtpService ke EmailOtpService

**FIND (baris 5):**
```dart
import 'otp_service.dart';
```

**REPLACE WITH:**
```dart
import 'email_otp_service.dart';
```

### 3.2: Update method `requestRegistrationOtp()` (baris ~73)

**FIND:**
```dart
print('\n[AUTH] STEP 2: Creating OTP Service instance');
final otpService = OtpService();
print('✅ OTP Service created');

print('\n[AUTH] STEP 3: Calling OTP Service sendOtpToEmail()');
final success = await otpService.sendOtpToEmail(email);
```

**REPLACE WITH:**
```dart
print('\n[AUTH] STEP 2: Creating EmailOtpService instance');
final emailOtpService = EmailOtpService();
print('✅ EmailOtpService created');

print('\n[AUTH] STEP 3: Sending OTP email via Cloud Function');
final success = await emailOtpService.sendOtpToEmail(
  email,
  serviceType: EmailServiceType.firebaseFunction,  // Use Cloud Function
);
```

### 3.3: Update method `registerWithEmailPasswordAndOtp()` (baris ~633)

**FIND:**
```dart
print('\n[REGISTER] STEP 2: Verifying OTP');
final otpService = OtpService();
final verifiedEmail = await otpService.verifyOtp(email, otp);
```

**REPLACE WITH:**
```dart
print('\n[REGISTER] STEP 2: Verifying OTP');
final emailOtpService = EmailOtpService();
final verifiedEmail = await emailOtpService.verifyOtp(email, otp);
```

---

## Step 4: Deploy Cloud Functions

Di terminal, di root project:

```bash
# 1. Navigate ke functions folder
cd functions

# 2. Install dependencies (jika deps belum ada)
npm install

# 3. Deploy ke Firebase
firebase deploy --only functions
```

**OUTPUT akan terlihat seperti:**
```
✔  functions[sendOtpEmail(us-central1)] Successful create operation.
Function URL: https://us-central1-my-app.cloudfunctions.net/sendOtpEmail
```

### Copy Function URL

Dari output di atas, copy URL function. Contoh:
```
https://us-central1-my-app.cloudfunctions.net/sendOtpEmail
```

---

## Step 5: Update Cloud Function URL di Code

Di `lib/services/email_otp_service.dart`, line ~151:

**FIND:**
```dart
const CLOUD_FUNCTION_URL =
    'https://us-central1-my-app.cloudfunctions.net/sendOtpEmail';
```

**REPLACE dengan URL dari Step 4:**
```dart
const CLOUD_FUNCTION_URL =
    'https://us-central1-MY-APP-ID.cloudfunctions.net/sendOtpEmail';
```

---

## Step 6: Test Flow

### 6.1: Test Cloud Function (sebelum app)

```bash
curl -X POST https://us-central1-my-app.cloudfunctions.net/sendOtpEmail \
  -H "Content-Type: application/json" \
  -d '{
    "email": "your-email@gmail.com",
    "otp": "123456",
    "appName": "Smart Cane Assistant"
  }'
```

Harus dapat response:
```json
{
  "success": true,
  "message": "✅ OTP email sent successfully",
  "email": "your-email@gmail.com",
  "timestamp": "2024-04-09T10:30:00.000Z"
}
```

### 6.2: Test App Flow

```bash
flutter clean
flutter pub get
flutter run
```

1. Go to Register screen
2. Input email: `your-email@gmail.com`
3. Input password & other fields
4. Click "DAFTAR & KIRIM OTP"
5. Check email inbox untuk OTP code
6. Lihat console output untuk debugging

---

## Verification Checklist

- [ ] `pubspec.yaml` sudah add `http` dependency
- [ ] `functions/package.json` sudah deployed
- [ ] Cloud Function URL sudah update di code
- [ ] `.env` file di functions folder sudah configured (GMAIL_EMAIL & GMAIL_APP_PASSWORD)
- [ ] `firebase deploy --only functions` sudah dijalankan
- [ ] Email test received ke inbox
- [ ] Register flow works end-to-end

---

## Troubleshooting

### Issue: "Cloud Function error: 404"
**Solution:** URL salah atau function belum deployed
- Run: `firebase functions:list` untuk lihat URL
- Pastikan URL match exactly di code

### Issue: "Timeout"
**Solution:**
- Check internet connection
- Verify function deployed: `firebase functions:list`
- Check function logs: `firebase functions:log`

### Issue: "Gmail app password error"
**Solution:**
- Setup 2-factor authentication di Gmail dulu
- Generate new app password
- Check GMAIL_APP_PASSWORD format (16 chars dengan spasi)

### Issue: "Email tidak dikirim tapi function return success"
**Solution:**
- Check spam folder
- Verify email address di function logs
- Check Cloud Function logs untuk error details

---

## Security Notes

1. **Jangan hardcode credentials di code** ✅ Already done - using `.env`
2. **Jangan commit `.env` file** - Add ke `.gitignore`
3. **Jangan share GMAIL_APP_PASSWORD** - Secret!
4. **Function URL aman untuk di-expose** - No credentials in URL

---

## What's Next

- ✅ Cloud Functions set up
- ✅ EmailOtpService integrated
- ✅ AuthService updated
- ⏳ Email sending works real
- ⏳ Full registration flow tested
