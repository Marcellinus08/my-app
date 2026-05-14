import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';
import '../../widgets/modern_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  UserType _selectedUserType = UserType.tunanetra;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email harus diisi';
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
      return 'Format email tidak valid';
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

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('🔐 Attempting login with email: ${_emailController.text}');
      
      final userCredential = await _authService.loginWithEmailPasswordNew(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (userCredential == null || userCredential.user == null) {
        throw Exception('Login gagal - user tidak ditemukan');
      }

      print('✅ Login successful, UID: ${userCredential.user!.uid}');

      // Check if email is verified
      print('\n🔍 Checking email verification status...');
      final isVerified = await _authService.isEmailVerified();
      
      if (!isVerified) {
        print('⚠️ Email not verified yet');
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Email belum diverifikasi. Periksa inbox Anda untuk link verifikasi',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            elevation: 2,
            action: SnackBarAction(
              label: 'Kirim Ulang',
              textColor: Colors.white,
              onPressed: () async {
                try {
                  await _authService.resendVerificationEmail();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Email verifikasi berhasil dikirim ulang',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                        behavior: SnackBarBehavior.floating,
                        margin: EdgeInsets.all(16),
                        elevation: 2,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Gagal mengirim ulang email verifikasi',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 3),
                        behavior: SnackBarBehavior.floating,
                        margin: EdgeInsets.all(16),
                        elevation: 2,
                      ),
                    );
                  }
                }
              },
            ),
          ),
        );
        
        // Keep user logged in but prevent navigation until verified
        // Or optionally allow login and show verification reminder
        // For now, allow login but show the warning above
      } else {
        print('✅ Email verified - proceeding with login');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Anda berhasil masuk',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
            elevation: 2,
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        // Get user data to determine navigation
        final userData = await _authService.getUserByEmail(_emailController.text);
        final userType = userData?['userType'] as String?;

        if (_selectedUserType == UserType.tunanetra ||
            userType?.contains('tunanetra') == true) {
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.tunaNetraHome,
          );
        } else {
          final familyId = _authService.currentUserId ?? '';
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.familyHome,
            arguments: {
              'familyId': familyId,
            },
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Error tidak terduga';

        if (e is Exception) {
          errorMessage = e.toString().replaceAll('Exception: ', '');
        } else {
          errorMessage = e.toString();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            elevation: 2,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
                          // Header Section
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selamat Datang',
                                  style: AppTextStyles.heading2.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 28,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Masuk ke akun Anda dan mulai eksplorasi',
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
                          
                          // Login Form Card
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
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Masuk ke Akun',
                                    style: AppTextStyles.heading3.copyWith(
                                      color: const Color(0xFF0D47A1),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // Email Field
                                  ModernTextField(
                                    controller: _emailController,
                                    label: 'Email',
                                    icon: Icons.email_rounded,
                                    semanticLabel: 'Email untuk login',
                                    validator: _validateEmail,
                                  ),
                                  const SizedBox(height: 18),

                                  // Password Field
                                  ModernTextField(
                                    controller: _passwordController,
                                    label: 'Password',
                                    icon: Icons.lock_rounded,
                                    semanticLabel: 'Password untuk login',
                                    isPassword: true,
                                    validator: _validatePassword,
                                  ),
                                  const SizedBox(height: 28),

                                  // Login Button
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
                                                valueColor:
                                                    AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                      : GestureDetector(
                                          onTap: _handleLogin,
                                          child: Container(
                                            height: 54,
                                            decoration: BoxDecoration(
                                              gradient: AppColors.primaryGradient,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppColors.primary
                                                      .withValues(alpha: 0.35),
                                                  blurRadius: 16,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: _handleLogin,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                child: Center(
                                                  child: Text(
                                                    'Masuk',
                                                    style: AppTextStyles
                                                        .bodyLarge
                                                        .copyWith(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 18,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                  const SizedBox(height: 20),

                                  // Divider
                                  Row(
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
                                  const SizedBox(height: 20),

                                  // Register Link
                                  Center(
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.pushReplacementNamed(
                                          context,
                                          AppRoutes.register,
                                        );
                                      },
                                      child: RichText(
                                        text: TextSpan(
                                          text: 'Belum punya akun? ',
                                          style: AppTextStyles.bodySmall.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: 'Daftar di sini',
                                              style: AppTextStyles.bodySmall
                                                  .copyWith(
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
                          ),
                          const SizedBox(height: 18),
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
}

