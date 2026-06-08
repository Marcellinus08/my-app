import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_models.dart';
import '../../services/auth_service.dart';
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
  final _pairingService = PairingService();
  final _userService = UserService();

  // Form Keys
  final _penggunaFormKey = GlobalKey<FormState>();
  final _keluargaFormKey = GlobalKey<FormState>();

  // Controllers - Pengguna
  late TextEditingController _userEmailController;
  late TextEditingController _userPasswordController;
  late TextEditingController _userNameController;
  late TextEditingController _userPhoneController;

  // Controllers - Keluarga
  late TextEditingController _familyEmailController;
  late TextEditingController _familyPasswordController;
  late TextEditingController _familyPairingCodeController;
  late TextEditingController _familyNameController2;
  late TextEditingController _familyPhoneController2;

  // State
  UserType _selectedUserType = UserType.tunanetra;
  bool _isLoading = false;
  bool _isVerificationDialogOpen = false;

  void _showVerificationDialog({required String title, required String email}) {
    if (!mounted || _isVerificationDialogOpen) return;

    _isVerificationDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(title),
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
    ).whenComplete(() {
      _isVerificationDialogOpen = false;
    });
  }

  void _closeVerificationDialogIfOpen() {
    if (!mounted || !_isVerificationDialogOpen) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop();
    _isVerificationDialogOpen = false;
  }

  @override
  void initState() {
    super.initState();
    _userEmailController = TextEditingController();
    _userPasswordController = TextEditingController();
    _userNameController = TextEditingController();
    _userPhoneController = TextEditingController();

    _familyEmailController = TextEditingController();
    _familyPasswordController = TextEditingController();
    _familyPairingCodeController = TextEditingController();
    _familyNameController2 = TextEditingController();
    _familyPhoneController2 = TextEditingController();
  }

  @override
  void dispose() {
    _userEmailController.dispose();
    _userPasswordController.dispose();
    _userNameController.dispose();
    _userPhoneController.dispose();

    _familyEmailController.dispose();
    _familyPasswordController.dispose();
    _familyPairingCodeController.dispose();
    _familyNameController2.dispose();
    _familyPhoneController2.dispose();
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

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password harus diisi';
    if (value.length < 6) return 'Password minimal 6 karakter';
    return null;
  }

  // ========== PENGGUNA REGISTRATION ==========
  Future<void> _handlePenggunaRegister() async {
    // Validate email format
    final emailValidation = _validateEmail(_userEmailController.text);
    if (emailValidation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(emailValidation),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.fixed,
        ),
      );
      return;
    }

    // Validate password
    final passwordValidation = _validatePassword(_userPasswordController.text);
    if (passwordValidation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(passwordValidation),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.fixed,
        ),
      );
      return;
    }

    // Validate other fields
    if (!_penggunaFormKey.currentState!.validate()) {
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
      print(
        '\n[UI] Generating pairing code (will be saved after verification)...',
      );
      String pairingCode = _pairingService.generatePairingCode();
      print('   Pairing code: $pairingCode');

      if (mounted) {
        _showVerificationDialog(title: '📧 Verifikasi Email', email: email);

        setState(() => _isLoading = true);
      }

      // ===== STEP 3: Wait for Email Verification =====
      print(
        '\n[UI] STEP 2: Waiting for email verification (max 10 minutes)...',
      );

      // Using optimized defaults: 2s polling interval, 300 attempts = 10 minutes
      final verified = await _authService
          .waitForEmailVerificationWithLongPolling();

      _closeVerificationDialogIfOpen(); // Close waiting dialog immediately

      if (!verified) {
        throw Exception(
          'Verifikasi email timeout. Silakan login dan verify email kemudian.',
        );
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

      print('\n[UI] Saving Pengguna data...');
      await _userService.saveTunaNetraUser(
        uid: user.uid,
        email: email,
        name: name,
        phoneNumber: phone,
        pairingCode: pairingCode,
        familyContacts: [],
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
            behavior: SnackBarBehavior.fixed,
            duration: const Duration(seconds: 3),
          ),
        );

        print(
          '\n[UI] Registration complete, redirecting to login immediately...',
        );
        // Immediate navigation tanpa delay
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          // Clear notification sebelum navigate
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          Navigator.pushReplacementNamed(context, AppRoutes.login);
        }
      }

      print('\n✅ [PENGGUNA REGISTRATION] COMPLETE\n');
    } on PairingException catch (e) {
      if (mounted) {
        _closeVerificationDialogIfOpen();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.message}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }
    } catch (e) {
      print('\n❌ [UI] REGISTRATION FAILED');
      print('Error: $e\n');

      if (mounted) {
        // Try to close dialog if still open
        _closeVerificationDialogIfOpen();
      }

      if (mounted) {
        String errorMsg = e.toString().replaceAll("Exception: ", "");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $errorMsg'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.fixed,
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
      final pairingCode = _familyPairingCodeController.text
          .toUpperCase()
          .trim();
      print('🔄 [Keluarga] Verifying pairing code: $pairingCode');

      // Verify pairing code first
      final pairedUserInfo = await _pairingService.verifyPairingCode(
        pairingCode,
      );
      if (pairedUserInfo == null) {
        throw Exception('Kode pairing tidak valid atau sudah digunakan');
      }

      print('✅ [Keluarga] Pairing code verified');

      final email = _familyEmailController.text.trim();
      final password = _familyPasswordController.text;
      print(
        '📧 [Keluarga] Creating account and sending verification email to: $email',
      );

      _showVerificationDialog(title: 'Verifikasi Email Keluarga', email: email);

      final user = await _authService.registerWithEmailPasswordAndVerification(
        email: email,
        password: password,
        name: _familyNameController2.text.trim(),
        phoneNumber: _familyPhoneController2.text.trim(),
        userType: UserType.family,
      );

      if (user == null) {
        throw Exception('Gagal membuat akun keluarga');
      }

      print('✅ [Keluarga] Account created: ${user.uid}');

      print('⏳ [Keluarga] Waiting for email verification...');
      final verified = await _authService
          .waitForEmailVerificationWithLongPolling();

      _closeVerificationDialogIfOpen();

      if (!verified) {
        throw Exception(
          'Verifikasi email timeout. Silakan login dan verifikasi email kemudian.',
        );
      }

      // Re-check pairing code after verification to ensure target user still exists.
      final verifiedPairingInfo = await _pairingService.verifyPairingCode(
        pairingCode,
      );
      if (verifiedPairingInfo == null) {
        throw Exception('Kode pairing tidak valid atau sudah tidak tersedia');
      }

      final targetName =
          verifiedPairingInfo['name'] ??
          pairedUserInfo['name'] ??
          'pengguna TunaNetra';

      print('🔄 [Keluarga] Saving Keluarga data...');
      final familyName = _familyNameController2.text.trim();
      final familyPhone = _familyPhoneController2.text.trim();

      await _userService.saveFamilyUser(
        uid: user.uid,
        email: email,
        name: familyName,
        phoneNumber: familyPhone,
        pairingCode: pairingCode,
        pairedUserUid: '',
        isEmailVerified: true,
      );

      print('🔄 [Keluarga] Sending pairing request to Pengguna...');
      await _pairingService.createPairingRequest(
        familyUid: user.uid,
        pairingCode: pairingCode,
      );

      print('✅ Registration complete!');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Registrasi berhasil. Permintaan koneksi terkirim ke $targetName.',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.fixed,
            duration: const Duration(seconds: 4),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    } on PairingException catch (e) {
      if (mounted) {
        _closeVerificationDialogIfOpen();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.message}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _closeVerificationDialogIfOpen();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.fixed,
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
      backgroundColor: const Color(0xFFF7FAFD),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AuthHeader(
                    title: 'Buat Akun',
                    subtitle: 'Lengkapi data sesuai tipe akun Anda',
                    icon: Icons.person_add_rounded,
                  ),
                  const SizedBox(height: 18),
                  _AuthRoleSelector(
                    selectedUserType: _selectedUserType,
                    onChanged: (type) => setState(() {
                      _selectedUserType = type;
                    }),
                  ),
                  const SizedBox(height: 14),
                  _AuthCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _selectedUserType == UserType.tunanetra
                            ? _buildPenggunaFormSimplified()
                            : _buildKeluargaFormSimplified(),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: const Color(0xFFE2E8F0),
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
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Center(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pushReplacementNamed(
                                context,
                                AppRoutes.login,
                              );
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
                                      color: AppColors.primaryDark,
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
    );
  }

  Widget _buildPenggunaFormSimplified() {
    return Form(
      key: _penggunaFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Daftar sebagai Pengguna',
            style: AppTextStyles.heading3.copyWith(
              color: AppColors.textPrimary,
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

          // DAFTAR Button
          _AuthSubmitButton(
            label: 'Daftar',
            icon: Icons.arrow_forward_rounded,
            isLoading: _isLoading,
            onTap: _handlePenggunaRegister,
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
              color: AppColors.textPrimary,
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
              if (value == null || value.isEmpty)
                return 'Kode pairing harus diisi';
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

          // Password
          ModernTextField(
            controller: _familyPasswordController,
            label: 'Password',
            icon: Icons.lock_rounded,
            isPassword: true,
            validator: (value) {
              if (value == null || value.isEmpty) return 'Password harus diisi';
              if (value.length < 8) return 'Password minimal 8 karakter';
              return null;
            },
            semanticLabel: 'Password untuk akun keluarga',
          ),
          const SizedBox(height: 16),

          // Nama Lengkap
          ModernTextField(
            controller: _familyNameController2,
            label: 'Nama Lengkap',
            icon: Icons.person_rounded,
            validator: (value) {
              if (value == null || value.isEmpty) return 'Nama harus diisi';
              return null;
            },
            semanticLabel: 'Nama lengkap keluarga',
          ),
          const SizedBox(height: 16),

          // Nomor HP
          ModernTextField(
            controller: _familyPhoneController2,
            label: 'Nomor HP',
            icon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) return 'Nomor HP harus diisi';
              if (!RegExp(r'^(\+62|0)[0-9]{9,12}$').hasMatch(value)) {
                return 'Format nomor HP tidak valid';
              }
              return null;
            },
            semanticLabel: 'Nomor HP keluarga',
          ),
          const SizedBox(height: 28),
          _AuthSubmitButton(
            label: 'Daftar',
            icon: Icons.send_rounded,
            isLoading: _isLoading,
            onTap: _handleKeluargaRegister,
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
                if (value == null || value.isEmpty)
                  return 'Kode pairing harus diisi';
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
              controller: _familyPasswordController,
              label: 'Password',
              icon: Icons.lock_rounded,
              validator: _validatePassword,
              isPassword: true,
              semanticLabel: 'Password untuk login keluarga',
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          'DAFTAR & KIRIM LINK VERIFIKASI',
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
          ],
        ),
      ),
    );
  }
}

class _AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _AuthHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppConstants.appName,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: AppTextStyles.heading3.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Icon(icon, color: AppColors.primaryDark, size: 22),
        ),
      ],
    );
  }
}

class _AuthRoleSelector extends StatelessWidget {
  final UserType selectedUserType;
  final ValueChanged<UserType> onChanged;

  const _AuthRoleSelector({
    required this.selectedUserType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AuthRoleTile(
            icon: Icons.person_rounded,
            title: 'Pengguna',
            subtitle: 'Navigasi',
            isSelected: selectedUserType == UserType.tunanetra,
            onTap: () => onChanged(UserType.tunanetra),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _AuthRoleTile(
            icon: Icons.family_restroom_rounded,
            title: 'Keluarga',
            subtitle: 'Pemantau',
            isSelected: selectedUserType == UserType.family,
            onTap: () => onChanged(UserType.family),
          ),
        ),
      ],
    );
  }
}

class _AuthRoleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _AuthRoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isSelected ? Colors.white : AppColors.primaryDark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryDark : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryDark
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.16)
                      : AppColors.primaryDark.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.78)
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  final Widget child;

  const _AuthCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AuthSubmitButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback onTap;

  const _AuthSubmitButton({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.button.copyWith(
                            fontSize: 17,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(icon, color: Colors.white, size: 20),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
