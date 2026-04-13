import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_models.dart';
import '../../services/auth_service.dart';
import '../../services/otp_service.dart';
import '../../services/pairing_service.dart';
import '../../services/user_service.dart';
import '../../utils/constants.dart';
import '../../widgets/modern_text_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _authService = AuthService();
  final _otpService = OtpService();
  final _pairingService = PairingService();
  final _userService = UserService();

  // Form Keys
  final _pengunaFormKey = GlobalKey<FormState>();
  final _keluargaFormKey = GlobalKey<FormState>();

  // Controllers - Pengguna
  late TextEditingController _userEmailController;
  late TextEditingController _userPasswordController;
  late TextEditingController _userNameController;
  late TextEditingController _userPhoneController;
  late TextEditingController _familyNameController;
  late TextEditingController _familyPhoneController;

  // Controllers - Keluarga
  late TextEditingController _familyEmailController;
  late TextEditingController _familyPairingCodeController;
  late TextEditingController _familyNameController2;
  late TextEditingController _familyPhoneController2;
  late TextEditingController _familyOtpController;

  // State
  UserType _selectedUserType = UserType.tunanetra;
  bool _isLoading = false;
  bool _keluargaOtpSent = false;

  @override
  void initState() {
    super.initState();
    _userEmailController = TextEditingController();
    _userPasswordController = TextEditingController();
    _userNameController = TextEditingController();
    _userPhoneController = TextEditingController();
    _familyNameController = TextEditingController();
    _familyPhoneController = TextEditingController();
    
    _familyEmailController = TextEditingController();
    _familyPairingCodeController = TextEditingController();
    _familyNameController2 = TextEditingController();
    _familyPhoneController2 = TextEditingController();
    _familyOtpController = TextEditingController();
  }

  @override
  void dispose() {
    _userEmailController.dispose();
    _userPasswordController.dispose();
    _userNameController.dispose();
    _userPhoneController.dispose();
    _familyNameController.dispose();
    _familyPhoneController.dispose();
    
    _familyEmailController.dispose();
    _familyPairingCodeController.dispose();
    _familyNameController2.dispose();
    _familyPhoneController2.dispose();
    _familyOtpController.dispose();
    super.dispose();
  }

  // ========== VALIDATORS ==========
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Email harus diisi';
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
      return 'Format email tidak valid';
    }
    return null;
  }

  String? _validateName(String? value) {
    if (value == null || value.isEmpty) return 'Nama harus diisi';
    if (value.length < 3) return 'Nama minimal 3 karakter';
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return 'Nomor HP harus diisi';
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length < 10) return 'Nomor HP minimal 10 digit';
    return null;
  }

  String? _validateOtp(String? value) {
    if (value == null || value.isEmpty) return 'OTP harus diisi';
    if (value.length != 6) return 'OTP harus 6 digit';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password harus diisi';
    if (value.length < 6) return 'Password minimal 6 karakter';
    return null;
  }

  // ========== PENGGUNA REGISTRATION ==========
  Future<void> _handlePengunaRegister() async {
    // Validate email format
    final emailValidation = _validateEmail(_userEmailController.text);
    if (emailValidation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emailValidation), backgroundColor: Colors.red),
      );
      return;
    }

    // Validate password
    final passwordValidation = _validatePassword(_userPasswordController.text);
    if (passwordValidation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(passwordValidation), backgroundColor: Colors.red),
      );
      return;
    }

    // Validate other fields
    if (!_pengunaFormKey.currentState!.validate()) {
      print('❌ [UI] Form validation failed - fields are empty or invalid');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final email = _userEmailController.text.trim().toLowerCase();
      final password = _userPasswordController.text.trim();
      final name = _userNameController.text.trim();
      final phone = _userPhoneController.text.trim();
      
      print('\n╔═══════════════════════════════════════════════════════╗');
      print('║ [PENGGUNA REGISTRATION] NEW FLOW                     ║');
      print('║ Step 1: Create Auth                                  ║');
      print('║ Step 2: Wait for Email Verification                  ║');
      print('║ Step 3: Save Data to Firestore                       ║');
      print('╚═══════════════════════════════════════════════════════╝');
      
      // ===== STEP 1: Create Auth User + Send Verification Email =====
      print('\n[UI] STEP 1: Creating Firebase account...');
      print('   Email: $email');
      print('   Name: $name');
      print('   Phone: $phone');
      
      final user = await _authService.registerWithEmailPasswordAndVerification(
        email: email,
        password: password,
        name: name,
        phoneNumber: phone,
        userType: UserType.tunanetra,
      );

      if (user == null) {
        throw Exception('Gagal membuat akun');
      }

      print('\n✅ [UI] Firebase account created');
      print('   UID: ${user.uid}');
      print('   Email: ${user.email}');
      print('   ⏳ Verification email sent - waiting for user to verify...');

      // ===== STEP 2: Generate Pairing Code (before waiting) =====
      print('\n[UI] Generating pairing code (will be saved after verification)...');
      String pairingCode = _pairingService.generatePairingCode();
      print('   Pairing code: $pairingCode');

      if (mounted) {
        // Show waiting dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext ctx) {
            return WillPopScope(
              onWillPop: () async => false,
              child: AlertDialog(
                title: const Text('📧 Verifikasi Email'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Email verifikasi telah dikirim ke:\n$email'),
                      const SizedBox(height: 16),
                      const Text('📋 Instruksi:'),
                      const SizedBox(height: 8),
                      const Text('1. Buka email Anda'),
                      const SizedBox(height: 4),
                      const Text('2. Cari email dari Firebase'),
                      const SizedBox(height: 4),
                      const Text('3. Klik link verifikasi'),
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text(
                        '⏳ Menunggu verifikasi...',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );

        setState(() => _isLoading = true);
      }

      // ===== STEP 3: Wait for Email Verification =====
      print('\n[UI] STEP 2: Waiting for email verification (max 10 minutes)...');
      
      // Using optimized defaults: 2s polling interval, 300 attempts = 10 minutes
      final verified = await _authService.waitForEmailVerificationWithLongPolling();

      if (mounted) {
        Navigator.pop(context); // Close waiting dialog immediately
      }

      if (!verified) {
        throw Exception('Verifikasi email timeout. Silakan login dan verify email kemudian.');
      }

      print('\n✅ [UI] Email verification confirmed!');

      // ===== STEP 4: Save Data to Firestore (AFTER verification) =====
      print('\n[UI] STEP 3: Saving user data to Firestore...');
      
      await _authService.saveUserDataToFirestore(
        uid: user.uid,
        email: email,
        name: name,
        phoneNumber: phone,
        userType: UserType.tunanetra,
      );

      print('\n[UI] Saving pairing code to Firestore...');
      await _pairingService.savePairingCode(user.uid, pairingCode);
      print('✅ Pairing code saved');

      print('\n[UI] Saving family contact information...');
      final familyContact = FamilyContact(
        name: _familyNameController.text.trim(),
        phoneNumber: _familyPhoneController.text.trim(),
      );
      
      await _userService.saveTunaNetraUser(
        uid: user.uid,
        email: email,
        name: name,
        phoneNumber: phone,
        pairingCode: pairingCode,
        familyContacts: [familyContact],
      );
      print('✅ Family contact saved');

      if (mounted) {
        // Show success notification with pairing code
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Registrasi Berhasil!\n',
              style: const TextStyle(height: 1.4, fontSize: 12),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        print('\n[UI] Registration complete, redirecting to login immediately...');
        // Immediate navigation tanpa delay
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          // Clear notification sebelum navigate
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          Navigator.pushReplacementNamed(context, AppRoutes.login);
        }
      }
      
      print('\n✅ [PENGGUNA REGISTRATION] COMPLETE\n');
    } catch (e) {
      print('\n❌ [UI] REGISTRATION FAILED');
      print('Error: $e\n');
      
      if (mounted) {
        // Try to close dialog if still open
        try {
          Navigator.pop(context, false);
        } catch (e) {
          print('[UI] Dialog already closed');
        }
      }

      if (mounted) {
        String errorMsg = e.toString().replaceAll("Exception: ", "");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $errorMsg'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========== KELUARGA REGISTRATION ==========
  Future<void> _handleKeluargaRegister() async {
    if (!_keluargaFormKey.currentState!.validate()) {
      print('❌ Form validation failed');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final pairingCode = _familyPairingCodeController.text.toUpperCase().trim();
      print('🔄 [Keluarga] Verifying pairing code: $pairingCode');
      
      // Verify pairing code first
      final userInfo = await _pairingService.verifyPairingCode(pairingCode);
      if (userInfo == null) {
        throw Exception('Kode pairing tidak valid atau sudah digunakan');
      }

      print('✅ [Keluarga] Pairing code verified');

      final email = _familyEmailController.text.trim();
      print('📧 [Keluarga] Sending OTP to: $email');
      
      // Send OTP
      final success = await _authService.requestRegistrationOtp(email);

      if (!success) {
        throw Exception('Gagal mengirim OTP ke email');
      }

      print('✅ [Keluarga] OTP sent successfully to: $email');

      if (mounted) {
        setState(() => _keluargaOtpSent = true);
        print('📌 Showing OTP input field for Keluarga');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ OTP telah dikirim!\n'
              'Masukkan kode 6-digit dari email: $email',
              style: const TextStyle(height: 1.4),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('❌ [Keluarga] Error: $e');
      
      if (mounted) {
        String errorMsg = e.toString().replaceAll("Exception: ", "");
        print('📢 Showing error to user: $errorMsg');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $errorMsg'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleKeluargaVerifyOtp() async {
    if (!_keluargaFormKey.currentState!.validate()) return;
    if (_validateOtp(_familyOtpController.text) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP harus 6 digit'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('🔐 Verifying OTP for Keluarga...');
      
      // Verify OTP again
      final verifiedEmail = await _otpService.verifyOtp(
        _familyEmailController.text.trim(),
        _familyOtpController.text.trim(),
      );

      if (verifiedEmail == null) {
        throw Exception('OTP verification gagal');
      }

      // Verify pairing code again
      final userInfo = await _pairingService.verifyPairingCode(
        _familyPairingCodeController.text.toUpperCase().trim(),
      );
      if (userInfo == null) {
        throw Exception('Kode pairing tidak valid');
      }

      print('✅ OTP verified, creating account...');

      // Register with OTP
      await _authService.registerWithOtp(
        _familyEmailController.text.trim(),
        _familyOtpController.text.trim(),
        _familyNameController2.text.trim(),
        UserType.family,
      );

      // Get family ID
      final familyDoc = await _authService.getUserByEmail(
        _familyEmailController.text.trim(),
      );
      if (familyDoc == null) throw Exception('Keluarga tidak ditemukan');
      final familyId = familyDoc['uid'] as String;

      // Link family to user
      print('🔄 Linking family to Pengguna...');
      final tunaNetraUid = userInfo['uid'] as String;
      await _pairingService.linkFamilyToUser(
        familyId,
        tunaNetraUid,
        _familyPairingCodeController.text.toUpperCase().trim(),
      );

      // Save to Firestore
      print('🔄 Saving Keluarga data...');
      await _userService.saveFamilyUser(
        uid: familyId,
        email: _familyEmailController.text.trim(),
        name: _familyNameController2.text.trim(),
        phoneNumber: _familyPhoneController2.text.trim(),
        pairingCode: _familyPairingCodeController.text.toUpperCase().trim(),
        pairedUserUid: tunaNetraUid,
      );

      print('✅ Registration complete!');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Registrasi berhasil!\nTerhubung dengan: ${userInfo['name']}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header Section
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Buat Akun Baru',
                                  style: AppTextStyles.heading2.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 28,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Daftar dan mulai gunakan SmartCane',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          
                          // User Type Selection with Animation
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedUserType = UserType.tunanetra;
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color: _selectedUserType == UserType.tunanetra
                                            ? Colors.white
                                            : Colors.transparent,
                                        boxShadow: _selectedUserType == UserType.tunanetra
                                            ? [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.1),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                )
                                              ]
                                            : [],
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.person_rounded,
                                            size: 24,
                                            color: _selectedUserType == UserType.tunanetra
                                                ? AppColors.primary
                                                : Colors.white,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Pengguna',
                                            style: AppTextStyles.bodyMedium.copyWith(
                                              color: _selectedUserType == UserType.tunanetra
                                                  ? AppColors.primary
                                                  : Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedUserType = UserType.family;
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color: _selectedUserType == UserType.family
                                            ? Colors.white
                                            : Colors.transparent,
                                        boxShadow: _selectedUserType == UserType.family
                                            ? [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.1),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                )
                                              ]
                                            : [],
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.family_restroom_rounded,
                                            size: 24,
                                            color: _selectedUserType == UserType.family
                                                ? AppColors.primary
                                                : Colors.white,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Keluarga',
                                            style: AppTextStyles.bodyMedium.copyWith(
                                              color: _selectedUserType == UserType.family
                                                  ? AppColors.primary
                                                  : Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          
                          // Register Form Card
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                                BoxShadow(
                                  color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Form
                                _selectedUserType == UserType.tunanetra
                                    ? _buildPengunaFormSimplified()
                                    : _buildKeluargaFormSimplified(),
                                
                                // Divider
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 1,
                                          color: AppColors.textTertiary
                                              .withOpacity(0.3),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text(
                                          'atau',
                                          style: AppTextStyles.bodySmall.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          height: 1,
                                          color: AppColors.textTertiary
                                              .withOpacity(0.3),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Link to Login
                                Center(
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.pushReplacementNamed(context, AppRoutes.login);
                                    },
                                    child: RichText(
                                      text: TextSpan(
                                        text: 'Sudah punya akun? ',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: 'Login di sini',
                                            style: AppTextStyles.bodySmall.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPengunaFormSimplified() {
    return Form(
      key: _pengunaFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Daftar sebagai Pengguna',
            style: AppTextStyles.heading3.copyWith(
              color: const Color(0xFF0D47A1),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 20),

          // Email Field
          ModernTextField(
            controller: _userEmailController,
            label: 'Email',
            icon: Icons.email_rounded,
            validator: _validateEmail,
            semanticLabel: 'Email untuk login',
          ),
          const SizedBox(height: 16),

          // Password Field
          ModernTextField(
            controller: _userPasswordController,
            label: 'Password',
            icon: Icons.lock_rounded,
            validator: _validatePassword,
            isPassword: true,
            semanticLabel: 'Password untuk login',
          ),
          const SizedBox(height: 16),

          // Name Field
          ModernTextField(
            controller: _userNameController,
            label: 'Nama Lengkap',
            icon: Icons.person_rounded,
            validator: _validateName,
            semanticLabel: 'Nama lengkap Anda',
          ),
          const SizedBox(height: 16),

          // Phone Field
          ModernTextField(
            controller: _userPhoneController,
            label: 'Nomor HP',
            icon: Icons.phone_rounded,
            validator: _validatePhone,
            semanticLabel: 'Nomor HP Anda',
          ),
          const SizedBox(height: 16),

          // Family Contact Name
          ModernTextField(
            controller: _familyNameController,
            label: 'Nama Kontak Keluarga',
            icon: Icons.family_restroom_rounded,
            validator: _validateName,
            semanticLabel: 'Nama kontak keluarga untuk monitoring',
          ),
          const SizedBox(height: 16),

          // Family Contact Phone
          ModernTextField(
            controller: _familyPhoneController,
            label: 'Nomor HP Keluarga',
            icon: Icons.phone_rounded,
            validator: _validatePhone,
            semanticLabel: 'Nomor HP kontak keluarga',
          ),
          const SizedBox(height: 28),

          // DAFTAR Button
          _isLoading
              ? Container(
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: _handlePengunaRegister,
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _handlePengunaRegister,
                        borderRadius: BorderRadius.circular(14),
                        child: Center(
                          child: Text(
                            'DAFTAR',
                            style: AppTextStyles.button.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildKeluargaFormSimplified() {
    return Form(
      key: _keluargaFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Daftar sebagai Keluarga',
            style: AppTextStyles.heading3.copyWith(
              color: const Color(0xFF0D47A1),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 20),

          // Pairing Code
          ModernTextField(
            controller: _familyPairingCodeController,
            label: 'Kode Pairing (dari Pengguna)',
            icon: Icons.vpn_key_rounded,
            semanticLabel: 'Kode pairing dari pengguna TunaNetra',
            validator: (value) {
              if (value == null || value.isEmpty) return 'Kode pairing harus diisi';
              if (!RegExp(r'^USER\d{5}$').hasMatch(value.toUpperCase())) {
                return 'Format tidak valid (misal: USER12345)';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Email
          ModernTextField(
            controller: _familyEmailController,
            label: 'Email',
            icon: Icons.email_rounded,
            validator: _validateEmail,
            semanticLabel: 'Email untuk login',
          ),
          const SizedBox(height: 16),

          // Name
          ModernTextField(
            controller: _familyNameController2,
            label: 'Nama Lengkap',
            icon: Icons.person_rounded,
            validator: _validateName,
            semanticLabel: 'Nama lengkap Anda',
          ),
          const SizedBox(height: 16),

          // Phone
          ModernTextField(
            controller: _familyPhoneController2,
            label: 'Nomor HP',
            icon: Icons.phone_rounded,
            validator: _validatePhone,
            semanticLabel: 'Nomor HP Anda',
          ),
          const SizedBox(height: 28),

          // DAFTAR Button
          _isLoading
              ? Container(
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: _handleKeluargaRegister,
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _handleKeluargaRegister,
                        borderRadius: BorderRadius.circular(14),
                        child: Center(
                          child: Text(
                            'DAFTAR',
                            style: AppTextStyles.button.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildKeluargaForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _keluargaFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Daftar sebagai Keluarga',
              style: AppTextStyles.heading3.copyWith(
                color: const Color(0xFF0D47A1),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),

            // All fields first
            ModernTextField(
              controller: _familyPairingCodeController,
              label: 'Kode Pairing (dari Pengguna)',
              icon: Icons.vpn_key_rounded,
              semanticLabel: 'Kode pairing dari pengguna TunaNetra',
              validator: (value) {
                if (value == null || value.isEmpty) return 'Kode pairing harus diisi';
                if (!RegExp(r'^USER\d{5}$').hasMatch(value.toUpperCase())) {
                  return 'Format tidak valid (misal: USER12345)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            ModernTextField(
              controller: _familyEmailController,
              label: 'Email',
              icon: Icons.email_rounded,
              validator: _validateEmail,
              semanticLabel: 'Email untuk login',
            ),
            const SizedBox(height: 16),
            ModernTextField(
              controller: _familyNameController2,
              label: 'Nama Lengkap',
              icon: Icons.person_rounded,
              validator: _validateName,
              semanticLabel: 'Nama lengkap Anda',
            ),
            const SizedBox(height: 16),
            ModernTextField(
              controller: _familyPhoneController2,
              label: 'Nomor HP',
              icon: Icons.phone_rounded,
              validator: _validatePhone,
              semanticLabel: 'Nomor HP Anda',
            ),
            const SizedBox(height: 24),

            // DAFTAR Button - sends OTP
            if (!_keluargaOtpSent)
              GestureDetector(
                onTap: _isLoading ? null : _handleKeluargaRegister,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'DAFTAR & KIRIM OTP',
                            style: AppTextStyles.button.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: 0.8,
                            ),
                          ),
                  ),
                ),
              )
            else ...[
              // OTP input after DAFTAR clicked
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '📧 OTP telah dikirim ke email Anda',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ModernTextField(
                      controller: _familyOtpController,
                      label: 'Masukkan Kode OTP (6 digit)',
                      icon: Icons.pin_rounded,
                      validator: _validateOtp,
                      semanticLabel: 'Kode OTP 6 digit dari email',
                    ),
                    const SizedBox(height: 14),
                    // VERIFIKASI Button
                    GestureDetector(
                      onTap: _isLoading ? null : _handleKeluargaVerifyOtp,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  'VERIFIKASI & SIMPAN',
                                  style: AppTextStyles.button.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
