const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

// Initialize Firebase Admin
admin.initializeApp();

/**
 * Cloud Function: sendOtpEmail
 * 
 * Mengirim OTP code ke email user via HTTP trigger
 * 
 * Request body:
 * {
 *   "email": "user@example.com",
 *   "otp": "123456",
 *   "appName": "Smart Cane Assistant"
 * }
 * 
 * Response:
 * {
 *   "success": true,
 *   "message": "OTP email sent successfully",
 *   "email": "user@example.com"
 * }
 */
exports.sendOtpEmail = functions.https.onRequest(async (req, res) => {
  // Enable CORS
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    res.status(200).send();
    return;
  }

  // Only accept POST requests
  if (req.method !== "POST") {
    res.status(400).json({
      success: false,
      message: "Only POST requests are allowed",
    });
    return;
  }

  try {
    const { email, otp, appName = "Smart Cane Assistant" } = req.body;

    console.log(`📧 [CLOUD FUNCTION] Received OTP email request`);
    console.log(`   Email: ${email}`);
    console.log(`   OTP: ${otp.replace(/./g, "*")}`);

    // Validate input
    if (!email || !otp) {
      return res.status(400).json({
        success: false,
        message: "Email dan OTP harus diisi",
      });
    }

    if (otp.length !== 6 || isNaN(otp)) {
      return res.status(400).json({
        success: false,
        message: "OTP harus 6 digit",
      });
    }

    if (!email.includes("@")) {
      return res.status(400).json({
        success: false,
        message: "Format email tidak valid",
      });
    }

    console.log(`✅ Validation passed`);

    // Get email credentials from Firebase Functions config or environment
    const emailProvider = process.env.EMAIL_PROVIDER || "gmail";
    
    console.log(`📮 Using email provider: ${emailProvider}`);

    let transporter;

    // Configure Nodemailer based on provider
    if (emailProvider === "gmail") {
      const gmailEmail = process.env.GMAIL_EMAIL;
      const gmailPassword = process.env.GMAIL_APP_PASSWORD;

      if (!gmailEmail || !gmailPassword) {
        throw new Error(
          "Gmail credentials not configured. Set GMAIL_EMAIL and GMAIL_APP_PASSWORD in .env"
        );
      }

      transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: gmailEmail,
          pass: gmailPassword,
        },
      });

      console.log(`✅ Gmail transporter configured`);
    } else if (emailProvider === "sendgrid") {
      const sgApiKey = process.env.SENDGRID_API_KEY;
      if (!sgApiKey) {
        throw new Error("SendGrid API key not configured. Set SENDGRID_API_KEY in .env");
      }

      const sgMail = require("@sendgrid/mail");
      sgMail.setApiKey(sgApiKey);

      transporter = {
        send: async (mailOptions) => {
          try {
            await sgMail.send({
              to: mailOptions.to,
              from: mailOptions.from,
              subject: mailOptions.subject,
              html: mailOptions.html,
            });
            return { success: true };
          } catch (error) {
            throw error;
          }
        },
      };

      console.log(`✅ SendGrid transporter configured`);
    } else {
      throw new Error(`Unknown email provider: ${emailProvider}`);
    }

    // Prepare email content
    const emailSubject = `Kode Verifikasi ${appName}`;
    const emailHtml = generateEmailHtml(otp, appName);

    const mailOptions = {
      from: process.env.EMAIL_FROM_ADDRESS || "noreply@smartcane.app",
      to: email,
      subject: emailSubject,
      html: emailHtml,
    };

    console.log(`📧 Preparing email...`);
    console.log(`   To: ${email}`);
    console.log(`   Subject: ${emailSubject}`);

    // Send email
    console.log(`⏱️  [SENDING] Starting email transmission...`);
    const sendResult = await new Promise((resolve, reject) => {
      transporter.sendMail(mailOptions, (error, info) => {
        if (error) {
          reject(error);
        } else {
          resolve(info);
        }
      });
    });

    console.log(`✅ Email sent successfully!`);
    console.log(`   Message ID: ${sendResult.messageId || sendResult.id}`);

    // Log to Firestore for tracking
    await admin
      .firestore()
      .collection("email_logs")
      .add({
        email: email,
        type: "otp",
        status: "sent",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        provider: emailProvider,
      });

    console.log(`✅ Email log saved to Firestore`);

    return res.status(200).json({
      success: true,
      message: "✅ OTP email sent successfully",
      email: email,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error(`❌ [CLOUD FUNCTION] ERROR:`, error);

    // Log error to Firestore
    try {
      await admin
        .firestore()
        .collection("email_logs")
        .add({
          type: "otp",
          status: "failed",
          error: error.message,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (logError) {
      console.error("Failed to log error:", logError);
    }

    return res.status(500).json({
      success: false,
      message: `❌ Gagal mengirim email: ${error.message}`,
      error: error.message,
    });
  }
});

/**
 * Generate HTML email template untuk OTP
 */
function generateEmailHtml(otp, appName) {
  return `
    <!DOCTYPE html>
    <html lang="id">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        * {
          margin: 0;
          padding: 0;
          box-sizing: border-box;
        }
        body {
          font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
          line-height: 1.6;
          color: #333;
          background: #f5f5f5;
        }
        .container {
          max-width: 600px;
          margin: 0 auto;
          background: white;
          border-radius: 12px;
          overflow: hidden;
          box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        .header {
          background: linear-gradient(135deg, #1E88E5 0%, #42A5F5 100%);
          color: white;
          padding: 40px 20px;
          text-align: center;
        }
        .header h1 {
          font-size: 28px;
          font-weight: 700;
          margin-bottom: 8px;
        }
        .header p {
          font-size: 16px;
          opacity: 0.9;
        }
        .content {
          padding: 40px 20px;
          text-align: center;
        }
        .content h2 {
          color: #1E88E5;
          font-size: 20px;
          margin-bottom: 20px;
        }
        .content p {
          color: #666;
          margin-bottom: 16px;
          font-size: 14px;
        }
        .otp-box {
          background: linear-gradient(135deg, #1E88E5 0%, #42A5F5 100%);
          border-radius: 8px;
          padding: 30px 20px;
          margin: 30px 0;
          display: inline-block;
          min-width: 200px;
        }
        .otp-label {
          color: rgba(255, 255, 255, 0.9);
          font-size: 13px;
          text-transform: uppercase;
          letter-spacing: 1px;
          margin-bottom: 12px;
        }
        .otp-code {
          color: white;
          font-size: 48px;
          font-weight: 700;
          letter-spacing: 8px;
          font-family: 'Courier New', monospace;
        }
        .validity {
          background: #f0f0f0;
          border-left: 4px solid #1E88E5;
          padding: 15px;
          margin: 20px 0;
          border-radius: 4px;
          color: #666;
          font-size: 13px;
        }
        .warning {
          background: #fff3cd;
          border-left: 4px solid #ffc107;
          padding: 15px;
          margin: 20px 0;
          border-radius: 4px;
          color: #856404;
          font-size: 13px;
        }
        .footer {
          background: #f9f9f9;
          padding: 20px;
          text-align: center;
          border-top: 1px solid #e0e0e0;
          color: #999;
          font-size: 12px;
        }
        .footer a {
          color: #1E88E5;
          text-decoration: none;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>🔐 ${appName}</h1>
          <p>Verifikasi Email Anda</p>
        </div>

        <div class="content">
          <h2>Kode Verifikasi Anda</h2>
          
          <p>Gunakan kode berikut untuk memverifikasi akun Anda:</p>

          <div class="otp-box">
            <div class="otp-label">Masukkan kode ini:</div>
            <div class="otp-code">${otp}</div>
          </div>

          <div class="validity">
            ⏱️ Kode ini berlaku selama <strong>10 menit</strong><br>
            Jangan bagikan kode ini kepada siapapun
          </div>

          <div class="warning">
            ⚠️ Jika Anda tidak merasa melakukan permintaan ini, abaikan email ini atau hubungi bantuan kami
          </div>

          <p style="margin-top: 30px; color: #999; font-size: 12px;">
            Pertanyaan? Hubungi kami di <a href="mailto:support@smartcane.app">support@smartcane.app</a>
          </p>
        </div>

        <div class="footer">
          <p>© 2024 ${appName}. Semua hak dilindungi.</p>
          <p>Email ini dikirim ke <strong>${getEmailMask()}</strong></p>
        </div>
      </div>
    </body>
    </html>
  `;
}

/**
 * Utility: Mask email untuk privacy
 */
function getEmailMask() {
  return "***@***.***";
}

console.log(`🚀 Cloud Functions initialized`);
console.log(`   Available functions: sendOtpEmail`);
