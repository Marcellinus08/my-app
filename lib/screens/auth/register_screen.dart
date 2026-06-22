import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/pairing_service.dart';
import '../../services/pending_registration_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_feedback.dart';
import '../../utils/constants.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/modern_text_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with WidgetsBindingObserver {
  final _authService = AuthService();
  final _pairingService = PairingService();
  final _pendingRegistrationService = PendingRegistrationService();
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
  late TextEditingController _familyNameController2;
  late TextEditingController _familyPhoneController2;

  // State
  UserType _selectedUserType = UserType.tunanetra;
  bool _isLoading = false;
  bool _isVerificationDialogOpen = false;
  bool _verificationCancelled = false;
  bool _isRestoringRegistration = false;

  void _showVerificationDialog({required String email}) {
    if (!mounted || _isVerificationDialogOpen) return;

    _isVerificationDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierColor: AppDialogStyle.barrierColor,
      barrierDismissible: false,
      builder: (dialogContext) => _EmailVerificationDialog(
        email: email,
        onCancel: () {
          _verificationCancelled = true;
          _isVerificationDialogOpen = false;
          Navigator.of(dialogContext).pop();
        },
        onResend: () => _authService.resendVerificationEmail(maxRetries: 1),
      ),
    ).whenComplete(() {
      _isVerificationDialogOpen = false;
    });
  }

  // TODO: Remove after the verification UI migration is fully released.
  // ignore: unused_element
  void _showLegacyVerificationDialog({
    required String title,
    required String email,
  }) {
    if (!mounted || _isVerificationDialogOpen) return;

    _isVerificationDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
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
    WidgetsBinding.instance.addObserver(this);
    _userEmailController = TextEditingController();
    _userPasswordController = TextEditingController();
    _userNameController = TextEditingController();
    _userPhoneController = TextEditingController();

    _familyEmailController = TextEditingController();
    _familyPasswordController = TextEditingController();
    _familyNameController2 = TextEditingController();
    _familyPhoneController2 = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePendingRegistration();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _userEmailController.dispose();
    _userPasswordController.dispose();
    _userNameController.dispose();
    _userPhoneController.dispose();

    _familyEmailController.dispose();
    _familyPasswordController.dispose();
    _familyNameController2.dispose();
    _familyPhoneController2.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restorePendingRegistration();
    }
  }

  Future<void> _restorePendingRegistration() async {
    if (!mounted ||
        _isRestoringRegistration ||
        _isVerificationDialogOpen ||
        _isLoading) {
      return;
    }

    final pending = await _pendingRegistrationService.load();
    final currentUser = _authService.currentUser;
    if (pending == null ||
        currentUser == null ||
        currentUser.email?.toLowerCase() != pending.email.toLowerCase()) {
      return;
    }

    _isRestoringRegistration = true;
    _verificationCancelled = false;
    if (mounted) setState(() => _isLoading = true);

    try {
      // Solusi 2: pending kadaluarsa (>10 menit) → hapus akun + beri kesempatan daftar ulang
      if (pending.isExpired) {
        await _pendingRegistrationService.clear();
        await _authService.deleteAccount();
        if (mounted) {
          AppFeedback.show(
            context,
            'Waktu verifikasi habis. Silakan daftar kembali.',
            type: AppFeedbackType.warning,
          );
        }
        return;
      }

      var verified = await _authService.isEmailVerified();
      if (!verified && mounted) {
        _showVerificationDialog(email: pending.email);
        verified = await _authService.waitForEmailVerificationWithLongPolling(
          isCancelled: () => _verificationCancelled,
        );
      }

      _closeVerificationDialogIfOpen();

      if (_verificationCancelled) {
        await _pendingRegistrationService.clear();
        await _authService.deleteAccount();
        if (mounted) {
          AppFeedback.show(
            context,
            'Pendaftaran dibatalkan.',
            type: AppFeedbackType.info,
          );
        }
        return;
      }

      if (!verified) return;

      await _completePendingRegistration(pending);
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          error,
          fallback:
              'Pendaftaran belum dapat diselesaikan. Aplikasi akan mencoba lagi saat dibuka kembali.',
        );
      }
    } finally {
      _isRestoringRegistration = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completePendingRegistration(PendingRegistration pending) async {
    final user = _authService.currentUser;
    if (user == null) {
      throw Exception('Sesi pendaftaran tidak ditemukan');
    }

    if (pending.userType == 'tunanetra') {
      await _runFinalizationStep(
        () => _authService.saveUserDataToFirestore(
          uid: user.uid,
          email: pending.email,
          name: pending.name,
          phoneNumber: pending.phoneNumber,
          userType: UserType.tunanetra,
        ),
      );
      await _runFinalizationStep(
        () => _pairingService.savePairingCode(user.uid, pending.pairingCode),
      );
      await _runFinalizationStep(
        () => _userService.saveTunaNetraUser(
          uid: user.uid,
          email: pending.email,
          name: pending.name,
          phoneNumber: pending.phoneNumber,
          pairingCode: pending.pairingCode,
          familyContacts: [],
        ),
      );
      await _pendingRegistrationService.clear();
      if (mounted) {
        await _showRegistrationSuccess();
      }
      return;
    }

    await _runFinalizationStep(
      () => _authService.saveUserDataToFirestore(
        uid: user.uid,
        email: pending.email,
        name: pending.name,
        phoneNumber: pending.phoneNumber,
        userType: UserType.family,
      ),
    );
    await _runFinalizationStep(
      () => _userService.saveFamilyUser(
        uid: user.uid,
        email: pending.email,
        name: pending.name,
        phoneNumber: pending.phoneNumber,
        pairedUserUid: '',
        isEmailVerified: true,
      ),
    );
    await _pendingRegistrationService.clear();
    if (mounted) {
      await _showRegistrationSuccess();
    }
  }

  Future<void> _runFinalizationStep(
    Future<void> Function() operation, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await operation();
        return;
      } catch (error) {
        lastError = error;
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    throw lastError ?? Exception('Penyelesaian pendaftaran gagal');
  }

  Future<void> _showRegistrationSuccess() async {
    if (!mounted) return;

    AppFeedback.success(context, 'Akun berhasil terdaftar. Silakan masuk.');
    await Future.delayed(const Duration(milliseconds: 2500));

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.login);
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
      AppFeedback.show(context, emailValidation, type: AppFeedbackType.error);
      return;
    }

    // Validate password
    final passwordValidation = _validatePassword(_userPasswordController.text);
    if (passwordValidation != null) {
      AppFeedback.show(
        context,
        passwordValidation,
        type: AppFeedbackType.error,
      );
      return;
    }

    // Validate other fields
    if (!_penggunaFormKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    _verificationCancelled = false;
    bool provisionalAccountCreated = false;
    bool emailVerified = false;

    try {
      final email = _userEmailController.text.trim().toLowerCase();
      final password = _userPasswordController.text.trim();
      final name = _userNameController.text.trim();
      final phone = _userPhoneController.text.trim();

      // ===== STEP 1: Create Auth User + Send Verification Email =====
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
      provisionalAccountCreated = true;

      // ===== STEP 2: Generate Pairing Code (before waiting) =====
      String pairingCode = _pairingService.generatePairingCode();

      await _pendingRegistrationService.save(
        PendingRegistration(
          userType: 'tunanetra',
          email: email,
          name: name,
          phoneNumber: phone,
          pairingCode: pairingCode,
        ),
      );

      if (mounted) {
        _showVerificationDialog(email: email);

        setState(() => _isLoading = true);
      }

      // ===== STEP 3: Wait for Email Verification =====
      // Using optimized defaults: 2s polling interval, 300 attempts = 10 minutes
      final verified = await _authService
          .waitForEmailVerificationWithLongPolling(
            isCancelled: () => _verificationCancelled,
          );

      _closeVerificationDialogIfOpen(); // Close waiting dialog immediately

      if (!verified) {
        await _pendingRegistrationService.clear();
        await _authService.deleteAccount();
        provisionalAccountCreated = false;
        if (_verificationCancelled) {
          if (mounted) {
            AppFeedback.show(
              context,
              'Pendaftaran dibatalkan.',
              type: AppFeedbackType.info,
            );
          }
          return;
        }
        throw Exception('Waktu verifikasi habis. Silakan daftar kembali.');
      }
      emailVerified = true;

      // ===== STEP 4: Save Data to Firestore (AFTER verification) =====
      await _runFinalizationStep(
        () => _authService.saveUserDataToFirestore(
          uid: user.uid,
          email: email,
          name: name,
          phoneNumber: phone,
          userType: UserType.tunanetra,
        ),
      );

      await _runFinalizationStep(
        () => _pairingService.savePairingCode(user.uid, pairingCode),
      );

      await _runFinalizationStep(
        () => _userService.saveTunaNetraUser(
          uid: user.uid,
          email: email,
          name: name,
          phoneNumber: phone,
          pairingCode: pairingCode,
          familyContacts: [],
        ),
      );
      await _pendingRegistrationService.clear();

      if (mounted) {
        await _showRegistrationSuccess();
      }
    } on PairingException catch (e) {
      if (mounted) {
        _closeVerificationDialogIfOpen();
        AppFeedback.error(
          context,
          e,
          fallback: 'Kode pairing tidak valid atau sudah tidak tersedia.',
        );
      }
    } catch (e) {
      if (mounted) {
        _closeVerificationDialogIfOpen();
      }

      if (provisionalAccountCreated && !emailVerified) {
        await _pendingRegistrationService.clear();
        try {
          await _authService.deleteAccount();
        } catch (_) {
          await _authService.logout();
        }
      }

      if (mounted) {
        AppFeedback.error(
          context,
          e,
          fallback:
              'Pendaftaran belum dapat diselesaikan. Periksa data lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========== KELUARGA REGISTRATION ==========
  Future<void> _handleKeluargaRegister() async {
    if (!_keluargaFormKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    _verificationCancelled = false;
    bool provisionalAccountCreated = false;
    bool emailVerified = false;

    try {
      final email = _familyEmailController.text.trim();
      final password = _familyPasswordController.text;
      final name = _familyNameController2.text.trim();
      final phone = _familyPhoneController2.text.trim();

      final user = await _authService.registerWithEmailPasswordAndVerification(
        email: email,
        password: password,
        name: name,
        phoneNumber: phone,
        userType: UserType.family,
      );

      if (user == null) {
        throw Exception('Gagal membuat akun keluarga');
      }
      provisionalAccountCreated = true;

      if (mounted) {
        _showVerificationDialog(email: email);
      }

      await _pendingRegistrationService.save(
        PendingRegistration(
          userType: 'family',
          email: email,
          name: name,
          phoneNumber: phone,
        ),
      );

      final verified = await _authService
          .waitForEmailVerificationWithLongPolling(
            isCancelled: () => _verificationCancelled,
          );

      _closeVerificationDialogIfOpen();

      if (!verified) {
        await _pendingRegistrationService.clear();
        await _authService.deleteAccount();
        provisionalAccountCreated = false;
        if (_verificationCancelled) {
          if (mounted) {
            AppFeedback.show(
              context,
              'Pendaftaran dibatalkan.',
              type: AppFeedbackType.info,
            );
          }
          return;
        }
        throw Exception('Waktu verifikasi habis. Silakan daftar kembali.');
      }
      emailVerified = true;

      await _runFinalizationStep(
        () => _authService.saveUserDataToFirestore(
          uid: user.uid,
          email: email,
          name: name,
          phoneNumber: phone,
          userType: UserType.family,
        ),
      );

      await _runFinalizationStep(
        () => _userService.saveFamilyUser(
          uid: user.uid,
          email: email,
          name: name,
          phoneNumber: phone,
          pairedUserUid: '',
          isEmailVerified: true,
        ),
      );

      await _pendingRegistrationService.clear();

      if (mounted) {
        await _showRegistrationSuccess();
      }
    } catch (e) {
      if (mounted) {
        _closeVerificationDialogIfOpen();
      }
      if (provisionalAccountCreated && !emailVerified) {
        await _pendingRegistrationService.clear();
        try {
          await _authService.deleteAccount();
        } catch (_) {
          await _authService.logout();
        }
      }
      if (mounted) {
        AppFeedback.error(
          context,
          e,
          fallback:
              'Pendaftaran keluarga belum dapat diselesaikan. Silakan coba lagi.',
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
                        const SizedBox(height: 24),
                        _AuthSubmitButton(
                          label: 'Daftar',
                          icon: Icons.arrow_forward_rounded,
                          isLoading: _isLoading,
                          onTap: _selectedUserType == UserType.tunanetra
                              ? _handlePenggunaRegister
                              : _handleKeluargaRegister,
                        ),
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
          const SizedBox(height: 16),
        ],
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

class _EmailVerificationDialog extends StatefulWidget {
  final String email;
  final VoidCallback onCancel;
  final Future<void> Function() onResend;

  const _EmailVerificationDialog({
    required this.email,
    required this.onCancel,
    required this.onResend,
  });

  @override
  State<_EmailVerificationDialog> createState() =>
      _EmailVerificationDialogState();
}

class _EmailVerificationDialogState extends State<_EmailVerificationDialog> {
  bool _isResending = false;

  Future<void> _resend() async {
    if (_isResending) return;
    setState(() => _isResending = true);
    try {
      await widget.onResend();
      if (mounted) {
        AppFeedback.success(
          context,
          'Email verifikasi berhasil dikirim ulang.',
        );
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          error,
          fallback:
              'Email verifikasi belum dapat dikirim ulang. Coba beberapa saat lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: AppDialogStyle.insetPadding,
        titlePadding: AppDialogStyle.titlePadding,
        contentPadding: AppDialogStyle.contentPadding,
        actionsPadding: AppDialogStyle.actionPadding,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDialogStyle.borderRadius),
          side: const BorderSide(color: AppDialogStyle.borderColor, width: 1),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.mark_email_unread_outlined,
                color: AppColors.primary,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Verifikasi email',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tautan verifikasi telah dikirim ke alamat berikut.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppDialogStyle.borderColor),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.email_outlined,
                      color: AppColors.primary,
                      size: 19,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        widget.email,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const _VerificationStep(
                number: '1',
                text: 'Buka kotak masuk atau folder spam.',
              ),
              const SizedBox(height: 9),
              const _VerificationStep(
                number: '2',
                text: 'Tekan tautan Verifikasi email.',
              ),
              const SizedBox(height: 9),
              const _VerificationStep(
                number: '3',
                text: 'Kembali ke aplikasi setelah berhasil.',
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppColors.infoLight.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Menunggu konfirmasi verifikasi',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: widget.onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Batalkan',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isResending ? null : _resend,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _isResending ? 'Mengirim...' : 'Kirim ulang',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VerificationStep extends StatelessWidget {
  final String number;
  final String text;

  const _VerificationStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.infoLight,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
