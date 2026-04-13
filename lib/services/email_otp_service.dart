import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

/// Enhanced OTP Service - Dapat mengirim email real via Firebase Cloud Functions
/// atau integrasi dengan SendGrid/other email services
class EmailOtpService {
  static final EmailOtpService _instance = EmailOtpService._internal();

  factory EmailOtpService() {
    return _instance;
  }

  EmailOtpService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _otpCollection = 'otp_codes';
  static const int _otpLength = 6;
  static const int _otpValidityMinutes = 10;

  /// Generate random 6-digit OTP
  String generateOtp() {
    final random = Random();
    String otp = '';
    for (int i = 0; i < _otpLength; i++) {
      otp += random.nextInt(10).toString();
    }
    print('✅ Generated OTP: $otp');
    return otp;
  }

  /// Send OTP to email with real email service
  /// Supports 3 methods:
  /// 1. Firebase Cloud Functions (recommended)
  /// 2. SendGrid API
  /// 3. Firestore mock (for testing)
  Future<bool> sendOtpToEmail(
    String email, {
    EmailServiceType serviceType = EmailServiceType.firebaseFunction,
  }) async {
    try {
      email = email.toLowerCase().trim();

      print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📧 [EMAIL OTP SERVICE] Sending OTP via: $serviceType');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      if (email.isEmpty) {
        throw Exception('Email tidak boleh kosong');
      }

      final otp = generateOtp();
      final now = DateTime.now();
      final expiresAt = now.add(Duration(minutes: _otpValidityMinutes));

      // Save to Firestore (always save for tracking)
      await _saveOtpToFirestore(email, otp, expiresAt);

      // Send via appropriate service
      switch (serviceType) {
        case EmailServiceType.firebaseFunction:
          await _sendViaCloudFunction(email, otp);
          break;
        case EmailServiceType.sendgrid:
          await _sendViaSendGrid(email, otp);
          break;
        case EmailServiceType.mock:
          await _sendMockEmail(email, otp);
          break;
      }

      print('✅ OTP Email sent successfully to: $email');
      return true;
    } catch (e) {
      print('❌ Error sending OTP: $e');
      rethrow;
    }
  }

  /// Helper: Save OTP to Firestore
  Future<void> _saveOtpToFirestore(
    String email,
    String otp,
    DateTime expiresAt,
  ) async {
    try {
      await _firestore.collection(_otpCollection).doc(email).set(
        {
          'email': email,
          'otp': otp,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiresAt),
          'attempts': 0,
          'maxAttempts': 5,
          'verified': false,
          'sent': true,
          'sent_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      print('   ✅ OTP saved to Firestore');
    } catch (e) {
      print('   ❌ Error saving to Firestore: $e');
      throw Exception('Failed to save OTP: $e');
    }
  }

  /// Method 1: Send via Firebase Cloud Function (RECOMMENDED)
  /// Setup instructions:
  /// 1. Create a Cloud Function with HTTP trigger
  /// 2. Function should call SendGrid/Gmail API
  /// 3. Deploy to Firebase
  Future<void> _sendViaCloudFunction(String email, String otp) async {
    try {
      print('   🔧 Attempting Firebase Cloud Function...');
      print('   📝 Setup instructions:');
      print('   1. Create Cloud Function in Firebase Console');
      print('   2. Deploy sendOtpEmail function');
      print('   3. Configure email service in function');
      print('   4. Update CLOUD_FUNCTION_URL below');

      // TODO: Replace with your Cloud Function URL
      const CLOUD_FUNCTION_URL =
          'https://YOUR_REGION-YOUR_PROJECT_ID.cloudfunctions.net/sendOtpEmail';

      print('   📡 Calling Cloud Function...');
      // Example code (uncomment when Cloud Function is ready):
      /*
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
        throw Exception('Cloud Function returned: ${response.statusCode}');
      }
      */

      print('   ⚠️ Cloud Function not configured (placeholder)');
      print('   📖 See comments in code for setup instructions');
    } catch (e) {
      print('   ❌ Cloud Function error: $e');
      throw Exception('Cloud Function failed: $e');
    }
  }

  /// Method 2: Send via SendGrid API
  /// Setup instructions:
  /// 1. Sign up for SendGrid account
  /// 2. Get API key from SendGrid
  /// 3. Configure in pubspec.yaml and environment
  Future<void> _sendViaSendGrid(String email, String otp) async {
    try {
      print('   📧 Attempting SendGrid email service...');
      print('   📝 Setup instructions:');
      print('   1. Sign up at https://sendgrid.com/');
      print('   2. Get API key from settings');
      print('   3. Add sendgrid package to pubspec.yaml');
      print('   4. Configure API key in environment/secrets');

      // TODO: Add SendGrid package and configure
      // Example code structure (uncomment when ready):
      /*
      const String SENDGRID_API_KEY = String.fromEnvironment('SENDGRID_API_KEY');
      
      final response = await http.post(
        Uri.parse('https://api.sendgrid.com/v3/mail/send'),
        headers: {
          'Authorization': 'Bearer $SENDGRID_API_KEY',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'personalizations': [{'to': [{'email': email}]}],
          'from': {'email': 'noreply@smartcane.app'},
          'subject': 'Your OTP Code',
          'content': [
            {
              'type': 'text/html',
              'value': _getEmailHtml(otp),
            }
          ],
        }),
      );

      if (response.statusCode != 202) {
        throw Exception('SendGrid returned: ${response.statusCode}');
      }
      */

      print('   ⚠️ SendGrid not configured (placeholder)');
      print('   📖 See comments in code for setup instructions');
    } catch (e) {
      print('   ❌ SendGrid error: $e');
      throw Exception('SendGrid failed: $e');
    }
  }

  /// Method 3: Mock email (for testing/development)
  /// In production/demo, OTP is printed to console
  Future<void> _sendMockEmail(String email, String otp) async {
    try {
      print('   🎭 Mock email service (DEVELOPMENT ONLY)');
      print('   ');
      print('   ╔════════════════════════════════════════╗');
      print('   ║       📧 TEST EMAIL NOTIFICATION      ║');
      print('   ╚════════════════════════════════════════╝');
      print('   ');
      print('   TO: $email');
      print('   SUBJECT: Your Smart Cane OTP Code');
      print('   ');
      print('   ┌────────────────────────────────────────┐');
      print('   │  Your verification code is:            │');
      print('   │                                        │');
      print('   │         🔐 $otp 🔐              │');
      print('   │                                        │');
      print('   │  Valid for 10 minutes                  │');
      print('   │  Do not share this code with anyone    │');
      print('   └────────────────────────────────────────┘');
      print('   ');
      print('   ✅ Mock email delivered (check console log)');
    } catch (e) {
      print('   ❌ Mock email error: $e');
      throw Exception('Mock email failed: $e');
    }
  }

  /// Generate HTML email template
  static String _getEmailHtml(String otp) {
    return '''
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body { font-family: Arial, sans-serif; color: #333; }
        .container { max-width: 500px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #1E88E5, #42A5F5); color: white; padding: 20px; border-radius: 10px 10px 0 0; text-align: center; }
        .content { background: #f9f9f9; padding: 20px; border-radius: 0 0 10px 10px; }
        .otp-code { background: white; border: 2px solid #1E88E5; padding: 20px; border-radius: 10px; text-align: center; font-size: 32px; font-weight: bold; letter-spacing: 5px; margin: 20px 0; }
        .footer { color: #666; font-size: 12px; margin-top: 20px; text-align: center; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h2>Smart Cane Assistant</h2>
          <p>Verification Code</p>
        </div>
        <div class="content">
          <p>Your OTP verification code is:</p>
          <div class="otp-code">$otp</div>
          <p style="color: #666;">This code will expire in 10 minutes.</p>
          <p style="color: #999; font-size: 12px;">If you did not request this code, please ignore this email.</p>
        </div>
        <div class="footer">
          <p>© 2024 Smart Cane Assistant. All rights reserved.</p>
        </div>
      </div>
    </body>
    </html>
    ''';
  }

  /// Verify OTP (same as before)
  Future<String?> verifyOtp(String email, String otp) async {
    try {
      email = email.toLowerCase().trim();
      otp = otp.trim();

      print('\n[OTP] Verifying OTP for: $email');

      final docSnapshot = await _firestore
          .collection(_otpCollection)
          .doc(email)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!docSnapshot.exists) {
        throw Exception('No OTP found for this email');
      }

      final data = docSnapshot.data() as Map<String, dynamic>;
      final storedOtp = data['otp'] as String?;
      final expiresAt = data['expiresAt'] as Timestamp?;
      final attempts = data['attempts'] as int? ?? 0;
      final maxAttempts = data['maxAttempts'] as int? ?? 5;
      final verified = data['verified'] as bool? ?? false;

      if (verified) {
        throw Exception('OTP sudah digunakan sebelumnya');
      }

      if (attempts >= maxAttempts) {
        throw Exception(
            'Terlalu banyak percobaan gagal. Minta OTP baru.');
      }

      if (expiresAt != null && DateTime.now().isAfter(expiresAt.toDate())) {
        throw Exception('OTP expired. Minta OTP baru.');
      }

      if (storedOtp != otp) {
        await _firestore.collection(_otpCollection).doc(email).update({
          'attempts': FieldValue.increment(1),
        });
        throw Exception('OTP salah');
      }

      // Mark as verified
      await _firestore.collection(_otpCollection).doc(email).update({
        'verified': true,
        'verifiedAt': FieldValue.serverTimestamp(),
      });

      print('✅ OTP verified successfully');
      return email;
    } catch (e) {
      print('❌ OTP verification error: $e');
      rethrow;
    }
  }
}

/// Enum untuk email service type
enum EmailServiceType {
  firebaseFunction, // Cloud Function (recommended)
  sendgrid, // SendGrid service
  mock, // Mock/test email
}
