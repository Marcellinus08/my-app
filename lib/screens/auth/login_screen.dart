import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../widgets/modern_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  UserType _selectedUserType = UserType.tunanetra;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
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
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        // Simulate login
        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login berhasil!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          // Navigate based on user type
          if (_selectedUserType == UserType.tunanetra) {
            Navigator.pushReplacementNamed(
              context,
              AppRoutes.tunaNetraHome,
            );
          } else {
            Navigator.pushReplacementNamed(
              context,
              AppRoutes.familyHome,
            );
          }
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
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                                BoxShadow(
                                  color: const Color(0xFF0D47A1).withOpacity(0.1),
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
                                    'Login',
                                    style: AppTextStyles.heading3.copyWith(
                                      color: const Color(0xFF0D47A1),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  
                                  // Username Field
                                  ModernTextField(
                                    controller: _usernameController,
                                    label: 'Username',
                                    icon: Icons.person_rounded,
                                    semanticLabel: 'Kolom input username',
                                    validator: _validateUsername,
                                  ),
                                  const SizedBox(height: 18),
                                  
                                  // Password Field
                                  ModernTextField(
                                    controller: _passwordController,
                                    label: 'Password',
                                    icon: Icons.lock_rounded,
                                    obscureText: true,
                                    isPassword: true,
                                    semanticLabel: 'Kolom input password',
                                    validator: _validatePassword,
                                  ),
                                  const SizedBox(height: 28),
                                  
                                  // Login Button with Animation
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
                                                valueColor: AlwaysStoppedAnimation<Color>(
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
                                              borderRadius: BorderRadius.circular(14),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppColors.primary.withOpacity(0.35),
                                                  blurRadius: 16,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: _handleLogin,
                                                borderRadius: BorderRadius.circular(14),
                                                child: Center(
                                                  child: Text(
                                                    'MASUK SEKARANG',
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
                                  
                                  // Register Link
                                  Center(
                                    child: TextButton(
                                      onPressed: () {
                                        Navigator.pushReplacementNamed(
                                          context,
                                          AppRoutes.register,
                                          arguments: _selectedUserType,
                                        );
                                      },
                                      child: Text.rich(
                                        TextSpan(
                                          text: 'Belum punya akun? ',
                                          style: AppTextStyles.bodyMedium.copyWith(
                                            color: AppColors.textSecondary,
                                            fontSize: 14,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: 'Daftar Sekarang',
                                              style: TextStyle(
                                                color: AppColors.primary,
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
}

