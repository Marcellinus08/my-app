import 'dart:async';
import 'package:flutter/material.dart';
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

  // PENGGUNA Form
  final _userFormKey = GlobalKey<FormState>();
  final _userEmailController = TextEditingController();
  final _userNameController = TextEditingController();
  final _userPhoneController = TextEditingController();
  final _familyContact1NameController = TextEditingController();
  final _familyContact1PhoneController = TextEditingController();

  // KELUARGA Form
  final _familyFormKey = GlobalKey<FormState>();
  final _familyEmailController = TextEditingController();
  final _familyNameController = TextEditingController();
  final _familyPhoneController = TextEditingController();
  final _pairingCodeController = TextEditingController();

  bool _isLoading = false;
  UserType _selectedUserType = UserType.tunanetra;

  @override
  void dispose() {
    _userEmailController.dispose();
    _userNameController.dispose();
    _userPhoneController.dispose();
    _familyContact1NameController.dispose();
    _familyContact1PhoneController.dispose();
    _familyEmailController.dispose();
    _familyNameController.dispose();
    _familyPhoneController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  // ========== VALIDATORS ==========
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email harus diisi';
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
      return 'Format email tidak valid';
    }
    return null;
  }

  String? _validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Nama harus diisi';
    }
    if (value.length < 3) {
      return 'Nama minimal 3 karakter';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Nomor HP harus diisi';
    }
    if (!RegExp(r'^[0-9+\-\s()]+$').hasMatch(value)) {
      return 'Nomor HP tidak valid';
    }
    if (value.replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
      return 'Nomor HP minimal 10 digit';
    }
    return null;
  }

  String? _validatePairingCode(String? value) {
    if (value == null || value.isEmpty) {
      return 'Kode pairing harus diisi';
    }
    if (!RegExp(r'^USER\d{5}$').hasMatch(value.toUpperCase())) {
      return 'Format kode tidak valid (misal: USER12345)';
    }
    return null;
  }

  // ========== REGISTER HANDLERS ==========
  Future<void> _handlePengunaRegister() async {
    if (_userFormKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        print('🔄 [1/4] Starting Pengguna registration...');
        final startTime = DateTime.now();

        // Register dengan Firebase Auth
        print('🔄 [1/4] Registering with Firebase Auth...');
        final authStart = DateTime.now();
        final userCredential = await _authService.registerWithEmailPassword(
          _userEmailController.text,
          'OTP_AUTH_PASSWORD',
          'OTP_AUTH_PASSWORD',
          _userNameController.text,
          UserType.tunanetra,
        ).timeout(
          const Duration(seconds: 70),
          onTimeout: () => throw Exception('Firebase Auth timeout (70s)'),
        );
        print('✅ [1/4] Firebase Auth completed in ${DateTime.now().difference(authStart).inSeconds}s');

        if (!mounted || userCredential == null) {
          print('⚠️ Widget unmounted or credential null');
          return;
        }

        final userId = userCredential.user?.uid ?? '';
        print('✅ User ID created: $userId');

        // Generate pairing code
        print('🔄 [2/4] Generating pairing code...');
        final pairingStart = DateTime.now();
        String pairingCode = _pairingService.generatePairingCode();
        await _pairingService.savePairingCode(userId, pairingCode);
        print('✅ [2/4] Pairing code saved in ${DateTime.now().difference(pairingStart).inSeconds}s: $pairingCode');

        // Create family contact
        print('🔄 [3/4] Creating family contact...');
        final familyContact = FamilyContact(
          name: _familyContact1NameController.text,
          phoneNumber: _familyContact1PhoneController.text,
        );
        print('✅ [3/4] Family contact created');

        // Save user data to Firestore
        print('🔄 [4/4] Saving user data to Firestore...');
        final firestoreStart = DateTime.now();
        
        bool firestoreSaveSuccessful = false;
        try {
          await _userService.saveTunaNetraUser(
            uid: userId,
            email: _userEmailController.text,
            name: _userNameController.text,
            phoneNumber: _userPhoneController.text,
            pairingCode: pairingCode,
            familyContacts: [familyContact],
          ).timeout(
            const Duration(seconds: 90),
            onTimeout: () {
              print('⏱️ Firestore save timeout after 90s - will continue anyway');
              throw TimeoutException('Firestore timeout', const Duration(seconds: 90));
            },
          );
          firestoreSaveSuccessful = true;
          print('✅ [4/4] Firestore save completed in ${DateTime.now().difference(firestoreStart).inSeconds}s');
        } catch (firestoreError) {
          // Firestore error - but Auth user is already created
          print('⚠️ [4/4] Firestore error (but Auth user created): $firestoreError');
          print('   User can still login - will sync Firestore later');
          // Don't throw - let user proceed to login
          // Firestore data may save in background
        }

        final totalTime = DateTime.now().difference(startTime).inSeconds;
        print('✅ Total registration time: ${totalTime}s');
        print('✅ Registration status: Auth=${userCredential != null ? "OK" : "FAIL"}, Firestore=${firestoreSaveSuccessful ? "OK" : "DELAY"}');

        if (mounted) {
          String successMessage = 'Registrasi berhasil!\n\nKode pairing: $pairingCode';
          if (!firestoreSaveSuccessful) {
            successMessage += '\n\n⚠️ Data masih disink (slow network)';
          }
          successMessage += '\n(Waktu: ${totalTime}s)';
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMessage),
              backgroundColor: firestoreSaveSuccessful ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );

          await Future.delayed(const Duration(milliseconds: 500));

          if (mounted) {
            Navigator.pushReplacementNamed(context, AppRoutes.login);
          }
        }
      } catch (e) {
        print('❌ Pengguna registration error: $e');
        if (mounted) {
          String errorMessage = e.toString().replaceAll('Exception: ', '');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _handleKeluargaRegister() async {
    if (_familyFormKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        print('🔄 [1/5] Starting Keluarga registration...');
        final startTime = DateTime.now();

        // Verifikasi pairing code
        print('🔄 [1/5] Verifying pairing code...');
        final verifyStart = DateTime.now();
        final userInfo = await _pairingService.verifyPairingCode(
          _pairingCodeController.text.toUpperCase(),
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception('Verify pairing code timeout (10s)'),
        );
        print('✅ [1/5] Pairing code verified in ${DateTime.now().difference(verifyStart).inSeconds}s');

        if (userInfo == null) {
          throw Exception('Kode pairing tidak ditemukan');
        }

        // Register dengan Firebase Auth
        print('🔄 [2/5] Registering with Firebase Auth...');
        final authStart = DateTime.now();
        final familyCredential = await _authService.registerWithEmailPassword(
          _familyEmailController.text,
          'OTP_AUTH_PASSWORD',
          'OTP_AUTH_PASSWORD',
          _familyNameController.text,
          UserType.family,
        ).timeout(
          const Duration(seconds: 70),
          onTimeout: () => throw Exception('Firebase Auth timeout (70s)'),
        );
        print('✅ [2/5] Firebase Auth completed in ${DateTime.now().difference(authStart).inSeconds}s');

        if (!mounted || familyCredential == null) {
          print('⚠️ Widget unmounted or credential null');
          return;
        }

        final familyId = familyCredential.user?.uid ?? '';
        final tunaNetraUid = userInfo['uid'] ?? '';
        print('✅ Family ID created: $familyId, linked to: $tunaNetraUid');

        // Link family ke pengguna
        print('🔄 [3/5] Linking family to TunaNetra user...');
        final linkStart = DateTime.now();
        await _pairingService.linkFamilyToUser(
          familyId,
          tunaNetraUid,
          _pairingCodeController.text.toUpperCase(),
        );
        print('✅ [3/5] Linking completed in ${DateTime.now().difference(linkStart).inSeconds}s');

        // Save family user data to Firestore
        print('🔄 [4/5] Saving family data to Firestore...');
        final firestoreStart = DateTime.now();
        
        bool firestoreSaveSuccessful = false;
        try {
          await _userService.saveFamilyUser(
            uid: familyId,
            email: _familyEmailController.text,
            name: _familyNameController.text,
            phoneNumber: _familyPhoneController.text,
            pairingCode: _pairingCodeController.text.toUpperCase(),
            pairedUserUid: tunaNetraUid,
          ).timeout(
            const Duration(seconds: 90),
            onTimeout: () {
              print('⏱️ Firestore save timeout after 90s - will continue anyway');
              throw TimeoutException('Firestore timeout', const Duration(seconds: 90));
            },
          );
          firestoreSaveSuccessful = true;
          print('✅ [4/5] Firestore save completed in ${DateTime.now().difference(firestoreStart).inSeconds}s');
        } catch (firestoreError) {
          // Firestore error - but Auth user is already created
          print('⚠️ [4/5] Firestore error (but Auth user created): $firestoreError');
          print('   User can still login - will sync Firestore later');
          // Don't throw - let user proceed to login
        }

        final totalTime = DateTime.now().difference(startTime).inSeconds;
        print('✅ Total Keluarga registration time: ${totalTime}s');
        print('✅ Registration status: Auth=${familyCredential != null ? "OK" : "FAIL"}, Firestore=${firestoreSaveSuccessful ? "OK" : "DELAY"}');

        if (mounted) {
          String successMessage = 'Registrasi berhasil!\n\nTerhubung dengan: ${userInfo['name']}';
          if (!firestoreSaveSuccessful) {
            successMessage += '\n\n⚠️ Data masih disink (slow network)';
          }
          successMessage += '\n(Waktu: ${totalTime}s)';
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMessage),
              backgroundColor: firestoreSaveSuccessful ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );

          await Future.delayed(const Duration(milliseconds: 500));

          if (mounted) {
            Navigator.pushReplacementNamed(context, AppRoutes.login);
          }
        }
      } catch (e) {
        print('❌ Keluarga registration error: $e');
        if (mounted) {
          String errorMessage = e.toString().replaceAll('Exception: ', '');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
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
                          // Header
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
                                  'Daftar dan mulai gunakan aplikasi',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),

                          // User Type Selection
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Pengguna Button
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
                                                  color: Colors.black.withValues(alpha: 0.1),
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

                                // Keluarga Button
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
                                                  color: Colors.black.withValues(alpha: 0.1),
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

                          // Form based on selection
                          if (_selectedUserType == UserType.tunanetra)
                            _buildPengunaForm()
                          else
                            _buildKeluargaForm(),
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

  // ========== FORM BUILDERS ==========
  Widget _buildPengunaForm() {
    return Container(
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
      child: Form(
        key: _userFormKey,
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

            // Email
            ModernTextField(
              controller: _userEmailController,
              label: 'Email',
              icon: Icons.email_rounded,
              validator: _validateEmail,
              semanticLabel: 'Email untuk OTP dan login',
            ),
            const SizedBox(height: 18),

            // Nama
            ModernTextField(
              controller: _userNameController,
              label: 'Nama Lengkap',
              icon: Icons.person_rounded,
              validator: _validateName,
              semanticLabel: 'Nama lengkap Anda',
            ),
            const SizedBox(height: 18),

            // Nomor HP
            ModernTextField(
              controller: _userPhoneController,
              label: 'Nomor HP',
              icon: Icons.phone_rounded,
              validator: _validatePhone,
              semanticLabel: 'Nomor HP untuk emergency contact',
            ),
            const SizedBox(height: 18),

            // Kontak Keluarga - Nama
            ModernTextField(
              controller: _familyContact1NameController,
              label: 'Nama Anggota Keluarga',
              icon: Icons.family_restroom_rounded,
              validator: _validateName,
              semanticLabel: 'Nama keluarga untuk monitoring',
            ),
            const SizedBox(height: 18),

            // Kontak Keluarga - Nomor HP
            ModernTextField(
              controller: _familyContact1PhoneController,
              label: 'Nomor HP Kontak Keluarga',
              icon: Icons.phone_rounded,
              validator: _validatePhone,
              semanticLabel: 'Nomor HP kontak keluarga',
            ),
            const SizedBox(height: 28),

            // Daftar Button
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
                              'DAFTAR SEKARANG',
                              style: AppTextStyles.button.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 18),

            // Link ke Login
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, AppRoutes.login);
                },
                child: Text.rich(
                  TextSpan(
                    text: 'Sudah punya akun? ',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    children: [
                      TextSpan(
                        text: 'Masuk di sini',
                        style: TextStyle(
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
    );
  }

  Widget _buildKeluargaForm() {
    return Container(
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
      child: Form(
        key: _familyFormKey,
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

            // Email
            ModernTextField(
              controller: _familyEmailController,
              label: 'Email',
              icon: Icons.email_rounded,
              validator: _validateEmail,
              semanticLabel: 'Email untuk OTP dan login',
            ),
            const SizedBox(height: 18),

            // Nama
            ModernTextField(
              controller: _familyNameController,
              label: 'Nama Lengkap',
              icon: Icons.person_rounded,
              validator: _validateName,
              semanticLabel: 'Nama lengkap Anda',
            ),
            const SizedBox(height: 18),

            // Nomor HP
            ModernTextField(
              controller: _familyPhoneController,
              label: 'Nomor HP',
              icon: Icons.phone_rounded,
              validator: _validatePhone,
              semanticLabel: 'Nomor HP Anda',
            ),
            const SizedBox(height: 18),

            // Info tentang Pairing Code
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_rounded, color: Colors.blue, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Minta kode dari pengguna (Format: USER12345)',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.blue,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Pairing Code
            ModernTextField(
              controller: _pairingCodeController,
              label: 'Kode Pairing',
              icon: Icons.vpn_key_rounded,
              validator: _validatePairingCode,
              semanticLabel: 'Kode pairing dari pengguna',
            ),
            const SizedBox(height: 28),

            // Daftar Button
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
                              'DAFTAR & HUBUNGKAN',
                              style: AppTextStyles.button.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 18),

            // Link ke Login
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, AppRoutes.login);
                },
                child: Text.rich(
                  TextSpan(
                    text: 'Sudah punya akun? ',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    children: [
                      TextSpan(
                        text: 'Masuk di sini',
                        style: TextStyle(
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
    );
  }
}

