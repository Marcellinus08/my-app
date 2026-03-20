import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../models/register_model.dart';
import '../../widgets/modern_text_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // Form keys
  final _userFormKey = GlobalKey<FormState>();
  final _familyFormKey = GlobalKey<FormState>();

  // User Form Controllers
  final _userNameController = TextEditingController();
  final _userPhoneController = TextEditingController();
  final _familyPhoneController = TextEditingController();
  final _userUsernameController = TextEditingController();
  final _userPasswordController = TextEditingController();

  // Family Form Controllers
  final _familyNameController = TextEditingController();
  final _familyPhoneNumberController = TextEditingController();
  final _familyUsernameController = TextEditingController();
  final _familyPasswordController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userNameController.dispose();
    _userPhoneController.dispose();
    _familyPhoneController.dispose();
    _userUsernameController.dispose();
    _userPasswordController.dispose();
    _familyNameController.dispose();
    _familyPhoneNumberController.dispose();
    _familyUsernameController.dispose();
    _familyPasswordController.dispose();
    super.dispose();
  }

  String? _validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Nomor telepon harus diisi';
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
      return 'Nomor telepon hanya boleh berisi angka';
    }
    if (value.length < 10) {
      return 'Nomor telepon minimal 10 digit';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password harus diisi';
    }
    if (value.length < 6) {
      return 'Password minimal 6 karakter';
    }
    return null;
  }

  String? _validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return 'Username harus diisi';
    }
    if (value.length < 3) {
      return 'Username minimal 3 karakter';
    }
    return null;
  }

  String? _validateFullName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Nama lengkap harus diisi';
    }
    return null;
  }

  Future<void> _handleUserRegister() async {
    if (_userFormKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final _registerData = RegisterUserModel(
          fullName: _userNameController.text,
          phoneNumber: _userPhoneController.text,
          familyPhoneNumber: _familyPhoneController.text,
          username: _userUsernameController.text,
          password: _userPasswordController.text,
        );

        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pendaftaran berhasil!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.login,
            arguments: UserType.tunanetra,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
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

  Future<void> _handleFamilyRegister() async {
    if (_familyFormKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final _registerData = RegisterFamilyModel(
          fullName: _familyNameController.text,
          phoneNumber: _familyPhoneNumberController.text,
          username: _familyUsernameController.text,
          password: _familyPasswordController.text,
        );

        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pendaftaran berhasil!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.login,
            arguments: UserType.family,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
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
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pilih tipe akun untuk melanjutkan',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              dividerColor: Colors.transparent,
                              dividerHeight: 0,
                              indicator: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white,
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              labelColor: AppColors.primary,
                              unselectedLabelColor: Colors.white,
                              labelStyle: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              unselectedLabelStyle: AppTextStyles.bodyMedium,
                              tabs: [
                                Tab(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.person_rounded, size: 20),
                                      const SizedBox(width: 8),
                                      const Text('Pengguna'),
                                    ],
                                  ),
                                ),
                                Tab(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.family_restroom_rounded, size: 20),
                                      const SizedBox(width: 8),
                                      const Text('Keluarga'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 550,
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _buildUserRegisterForm(),
                                _buildFamilyRegisterForm(),
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

  Widget _buildUserRegisterForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Form(
        key: _userFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ModernTextField(
                    controller: _userNameController,
                    label: 'Nama Lengkap',
                    icon: Icons.person_rounded,
                    semanticLabel: 'Kolom input nama lengkap',
                    validator: _validateFullName,
                  ),
                  const SizedBox(height: 12),
                  ModernTextField(
                    controller: _userPhoneController,
                    label: 'Nomor Telepon Anda',
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                    semanticLabel: 'Kolom input nomor telepon anda',
                    validator: _validatePhoneNumber,
                  ),
                  const SizedBox(height: 12),
                  ModernTextField(
                    controller: _familyPhoneController,
                    label: 'Nomor Telepon Keluarga',
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                    semanticLabel: 'Kolom input nomor telepon keluarga',
                    validator: _validatePhoneNumber,
                  ),
                  const SizedBox(height: 12),
                  ModernTextField(
                    controller: _userUsernameController,
                    label: 'Username',
                    icon: Icons.alternate_email_rounded,
                    semanticLabel: 'Kolom input username',
                    validator: _validateUsername,
                  ),
                  const SizedBox(height: 12),
                  ModernTextField(
                    controller: _userPasswordController,
                    label: 'Password',
                    icon: Icons.lock_rounded,
                    obscureText: true,
                    isPassword: true,
                    semanticLabel: 'Kolom input password',
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _handleUserRegister,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'DAFTAR',
                              style: AppTextStyles.button.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(
                        context,
                        AppRoutes.login,
                        arguments: UserType.tunanetra,
                      );
                    },
                    child: Text.rich(
                      TextSpan(
                        text: 'Sudah punya akun? ',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: 'Login',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyRegisterForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Form(
        key: _familyFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ModernTextField(
                    controller: _familyNameController,
                    label: 'Nama Lengkap',
                    icon: Icons.person_rounded,
                    semanticLabel: 'Kolom input nama lengkap',
                    validator: _validateFullName,
                  ),
                  const SizedBox(height: 12),
                  ModernTextField(
                    controller: _familyPhoneNumberController,
                    label: 'Nomor Telepon',
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                    semanticLabel: 'Kolom input nomor telepon',
                    validator: _validatePhoneNumber,
                  ),
                  const SizedBox(height: 12),
                  ModernTextField(
                    controller: _familyUsernameController,
                    label: 'Username',
                    icon: Icons.alternate_email_rounded,
                    semanticLabel: 'Kolom input username',
                    validator: _validateUsername,
                  ),
                  const SizedBox(height: 12),
                  ModernTextField(
                    controller: _familyPasswordController,
                    label: 'Password',
                    icon: Icons.lock_rounded,
                    obscureText: true,
                    isPassword: true,
                    semanticLabel: 'Kolom input password',
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.accentGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _handleFamilyRegister,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'DAFTAR',
                              style: AppTextStyles.button.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(
                        context,
                        AppRoutes.login,
                        arguments: UserType.family,
                      );
                    },
                    child: Text.rich(
                      TextSpan(
                        text: 'Sudah punya akun? ',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: 'Login',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
