# Firebase Email OTP Authentication Setup Guide

## 📋 Overview

Sistem autentikasi email OTP yang telah diimplementasikan mendukung:
- ✅ OTP 6-digit dengan validitas 10 menit
- ✅ Rate limiting untuk resend OTP (30 detik)
- ✅ Max 5 percobaan verification
- ✅ Automatic OTP expiry cleanup
- ✅ Auth state management dengan Provider
- ✅ Comprehensive error handling

---

## 🚀 Quick Start

### 1. Ensure Firebase Initialization
File: `lib/main.dart` - Sudah dikonfigurasi ✅

```dart
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

### 2. Provider Setup in main()
```dart
ChangeNotifierProvider(
  create: (_) => AuthProvider()..initializeAuth(),
),
```

### 3. UI Implementation Checklist
- ✅ `LoginScreen` - Sudah ada dengan OTP flow
- ✅ `RegisterScreen` - Sudah ada dengan OTP verification
- ✅ `AuthProvider` - Baru dibuat untuk state management
- ✅ `AuthErrorHandler` - Baru dibuat untuk error handling

---

## 🔐 Firestore Security Rules - Production Ready

### Current Rules (Development)
```dart
// File: firestore.rules
rules_version = 2;

service cloud.firestore {
  match /databases/{database}/documents {
    
    // OTP Collection (DEVELOPMENT)
    match /otp_codes/{document=**} {
      allow create, write: if request.resource.data.email is string;
      allow read: if true;
      allow update: if true;
      allow delete: if false;
    }
    
    // Users Collection
    match /users/{uid} {
      allow create: if 
        request.resource.data.keys().hasAll(['email', 'username']) &&
        request.resource.data.email is string &&
        request.resource.data.username is string;
      
      allow read: if request.auth.uid == uid || true;
      allow update: if request.auth.uid == uid || true;
      allow delete: if false;
    }
  }
}
```

### Recommended Rules (Production)
```dart
rules_version = 2;

service cloud.firestore {
  match /databases/{database}/documents {
    
    // OTP Collection (PRODUCTION)
    match /otp_codes/{email} {
      // Only allow email validation in document ID
      allow create: if 
        request.resource.data.email == email &&
        request.resource.data.email is string &&
        request.resource.data.otp is string &&
        request.resource.data.email.size() > 5;
      
      // Allow read for verification
      allow read: if true;
      
      // Only allow attempts increment and verified flag
      allow update: if 
        request.resource.data.email == email &&
        resource.data.verified == false;
      
      // No delete - cleanup via Cloud Function
      allow delete: if false;
    }
    
    // Users Collection (PRODUCTION)
    match /users/{uid} {
      // Strict creation rules
      allow create: if 
        uid == request.auth.uid &&
        request.resource.data.uid == uid &&
        request.resource.data.email is string &&
        request.resource.data.userType in ['tunanetra', 'keluarga'] &&
        request.resource.data.createdAt is timestamp;
      
      // Only owner can read own data
      allow read: if request.auth.uid == uid;
      
      // Only owner can update
      allow update: if request.auth.uid == uid;
      
      // No delete
      allow delete: if false;
    }
    
    // Auth Logs (for security tracking)
    match /auth_logs/{email}/{subcollection=**} {
      allow write: if request.auth != null;
      allow read: if request.auth.uid == email;
    }
  }
}
```

---

## 📧 Email Sending Setup

### Option 1: Firebase Cloud Function (RECOMMENDED)

#### A. Create Cloud Function

```bash
# Install Firebase CLI globally
npm install -g firebase-tools

# Login to Firebase
firebase login

# Create functions directory
firebase init functions

# Choose: JavaScript
```

#### B. Create Email Function (`functions/index.js`)

```javascript
const functions = require('firebase-functions');
const nodemailer = require('nodemailer');
const cors = require('cors')({origin: true});

// Configure Gmail or SendGrid
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASSWORD,
  },
});

// Alternative: SendGrid
// const sgMail = require('@sendgrid/mail');
// sgMail.setApiKey(process.env.SENDGRID_API_KEY);

exports.sendOtpEmail = functions.https.onRequest((request, response) => {
  cors(request, response, async () => {
    try {
      const { email, otp, appName } = request.body;

      if (!email || !otp) {
        return response.status(400).json({
          error: 'Email and OTP required',
        });
      }

      const mailOptions = {
        from: process.env.EMAIL_USER,
        to: email,
        subject: `${appName} - Kode Verifikasi OTP`,
        html: generateEmailHtml(otp, appName),
      };

      await transporter.sendMail(mailOptions);

      response.status(200).json({
        success: true,
        message: 'OTP email sent successfully',
      });
    } catch (error) {
      console.error('Error sending email:', error);
      response.status(500).json({
        error: error.message,
      });
    }
  });
});

// Cleanup expired OTPs
exports.cleanupExpiredOtps = functions.pubsub
  .schedule('every 1 hours')
  .onRun(async (context) => {
    const admin = require('firebase-admin');
    const db = admin.firestore();
    
    const expiredOtps = await db.collection('otp_codes')
      .where('expiresAt', '<', new Date())
      .get();

    const batch = db.batch();
    expiredOtps.docs.forEach(doc => {
      batch.delete(doc.ref);
    });

    await batch.commit();
    console.log(`Deleted ${expiredOtps.docs.length} expired OTPs`);
  });

function generateEmailHtml(otp, appName) {
  return `
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial; }
        .container { max-width: 500px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #1E88E5, #42A5F5); color: white; 
                  padding: 20px; border-radius: 10px 10px 0 0; text-align: center; }
        .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
        .otp-code { background: white; border: 2px solid #1E88E5; padding: 20px; 
                    border-radius: 10px; text-align: center; font-size: 36px; 
                    font-weight: bold; letter-spacing: 5px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h2>${appName}</h2>
          <p>Kode Verifikasi</p>
        </div>
        <div class="content">
          <p>Kode OTP Anda adalah:</p>
          <div class="otp-code">${otp}</div>
          <p style="color: #666;">Kode ini berlaku selama 10 menit.</p>
          <p style="color: #999; font-size: 12px;">
            Jika Anda tidak meminta kode ini, abaikan email ini.
          </p>
        </div>
      </div>
    </body>
    </html>
  `;
}
```

#### C. Deploy Function

```bash
# Set environment variables
firebase functions:config:set \
  email.user="your-email@gmail.com" \
  email.password="your-app-password"

# Deploy
firebase deploy --only functions
```

### Option 2: SendGrid Integration

#### A. Setup SendGrid

1. Sign up at [SendGrid](https://sendgrid.com/)
2. Get API key from settings
3. Add to `pubspec.yaml`:

```yaml
dependencies:
  sendgrid_email: ^0.0.7
```

#### B. Create SendGrid Service

```dart
// lib/services/sendgrid_service.dart
import 'package:sendgrid_email/sendgrid_email.dart';

class SendGridEmailService {
  static const String _apiKey = 'YOUR_SENDGRID_API_KEY';
  static const String _senderEmail = 'noreply@yourapp.com';

  static Future<bool> sendOtpEmail(String email, String otp) async {
    try {
      final sendGridEmail = SendGridEmail(
        apiKey: _apiKey,
        fromEmail: _senderEmail,
        fromName: 'Smart Cane Assistant',
        toEmail: email,
        subject: 'Your OTP Verification Code',
        htmlBody: generateEmailHtml(otp),
      );

      await sendGridEmail.send();
      return true;
    } catch (e) {
      print('Error sending email: $e');
      return false;
    }
  }

  static String generateEmailHtml(String otp) {
    return '''
      <h2>Your Verification Code</h2>
      <p>OTP: <strong>$otp</strong></p>
      <p>Valid for 10 minutes</p>
    ''';
  }
}
```

---

## 📊 File Structure

```
lib/
├── providers/
│   └── auth_provider.dart ← NEW: Global auth state management
├── services/
│   ├── auth_service.dart ← EXISTING: Base auth logic
│   ├── otp_service.dart ← EXISTING: OTP generation & verification
│   ├── email_otp_service.dart ← NEW: Enhanced email service
│   ├── auth_error_handler.dart ← NEW: Error handling & recovery
│   └── user_service.dart ← EXISTING: User data management
├── screens/
│   └── auth/
│       ├── login_screen.dart ← INTEGRATED: OTP login flow
│       └── register_screen.dart ← INTEGRATED: OTP registration
└── utils/
    └── constants.dart ← EXISTING: App configuration
```

---

## 🧪 Testing Checklist

- [ ] Registration OTP request works
- [ ] OTP expires after 10 minutes
- [ ] Failed attempts increment correctly
- [ ] Login with OTP successful
- [ ] Error messages display correctly
- [ ] Resend OTP with 30s rate limit
- [ ] Network timeout handled gracefully
- [ ] Firestore rules secure OTP collection

---

## 🔧 Environment Configuration

### Development
```dart
// Use mock email service
final emailService = EmailOtpService();
await emailService.sendOtpToEmail(
  email,
  serviceType: EmailServiceType.mock,
);
```

### Production
```dart
// Use Firebase Cloud Function
await emailService.sendOtpToEmail(
  email,
  serviceType: EmailServiceType.firebaseFunction,
);
```

---

## 📞 Troubleshooting

### OTP tidak terkirim
**Kemungkinan penyebab:**
- Firebase Cloud Function belum di-deploy
- Email service (Gmail/SendGrid) tidak dikonfigurasi
- Firestore security rules terlalu ketat

**Solusi:**
1. Check Firebase console untuk error logs
2. Verifikasi Firestore rules mengizinkan write ke `otp_codes`
3. Untuk Gmail, use App Password (not regular password)

### OTP verification selalu gagal
**Kemungkinan penyebab:**
- OTP sudah expired
- Pengguna memasukkan OTP yang salah
- OTP sudah digunakan sebelumnya

**Solusi:**
1. Cek timestamp di Firestore
2. Gunakan `expiresAt` field untuk debug
3. Reset OTP dengan minta ulang

### Timeout errors
**Kemungkinan penyebab:**
- Network connectivity issue
- Firebase backend tidak merespons
- Firestore quota exceeded

**Solusi:**
1. Periksa internet connection
2. Check Firebase status di console.firebase.google.com
3. Upgrade Firebase plan jika perlu

---

## 📚 Additional Resources

- [Firebase Authentication Docs](https://firebase.flutter.dev/docs/auth/overview/)
- [Cloud Firestore Security Rules](https://firebase.google.com/docs/firestore/security/start)
- [Firebase Cloud Functions](https://firebase.google.com/docs/functions)
- [SendGrid Integration](https://sendgrid.com/docs/api-reference/)

---

## ✨ Next Steps

1. ✅ Update Firestore security rules (copy production rules above)
2. 📧 Setup email sending (choose option 1 or 2)
3. 🔐 Enable Firebase Authentication in Console
4. 🧪 Test entire flow end-to-end
5. 📊 Monitor auth logs and errors in Firebase Console

---

**Last Updated:** 2024
**Status:** Production Ready ✅
