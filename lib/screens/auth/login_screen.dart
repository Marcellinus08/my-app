import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../utils/app_feedback.dart';
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
      return 'Kata sandi harus diisi';
    }
    if (value.length < 6) {
      return 'Kata sandi minimal 6 karakter';
    }
    return null;
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await _authService.loginWithEmailPasswordNew(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (userCredential == null || userCredential.user == null) {
        throw Exception('Login gagal - user tidak ditemukan');
      }

      // Check if email is verified
      final isVerified = await _authService.isEmailVerified();

      if (!isVerified) {
        if (!mounted) return;

        AppFeedback.warning(
          context,
          'Email belum diverifikasi. Periksa kotak masuk atau folder spam.',
          actionLabel: 'Kirim Ulang',
          onAction: () async {
            try {
              await _authService.resendVerificationEmail();
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
                      'Email verifikasi belum dapat dikirim. Coba kembali beberapa saat lagi.',
                );
              }
            }
          },
        );

        return;
      }

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      final registeredUserType = await _authService.getUserType();

      if (registeredUserType == null) {
        await _authService.logout();
        throw Exception('Tipe akun tidak ditemukan. Silakan hubungi admin.');
      }

      if (registeredUserType != _selectedUserType) {
        await _authService.logout();
        throw Exception('Email atau kata sandi tidak sesuai.');
      }

      if (!mounted) return;
      AppFeedback.success(context, 'Anda berhasil masuk.');

      if (registeredUserType == UserType.tunanetra) {
        Navigator.pushReplacementNamed(context, AppRoutes.tunaNetraHome);
      } else {
        final familyId = _authService.currentUserId ?? '';
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.familyHome,
          arguments: {'familyId': familyId},
        );
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          error,
          fallback: 'Tidak dapat masuk. Periksa data akun lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetFormKey = GlobalKey<FormState>();
    final resetEmailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    var isSending = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSending,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendResetEmail() async {
              if (!resetFormKey.currentState!.validate()) {
                return;
              }

              setDialogState(() => isSending = true);
              var dialogWasClosed = false;
              final navigator = Navigator.of(dialogContext);
              try {
                await _authService.sendPasswordResetEmail(
                  resetEmailController.text.trim(),
                );

                if (!mounted) return;
                dialogWasClosed = true;
                navigator.pop();
                AppFeedback.success(
                  this.context,
                  'Tautan atur ulang kata sandi sudah dikirim ke email Anda.',
                );
              } catch (error) {
                if (!mounted) return;
                AppFeedback.error(
                  this.context,
                  error,
                  fallback:
                      'Tautan atur ulang belum dapat dikirim. Coba kembali beberapa saat lagi.',
                );
              } finally {
                if (!dialogWasClosed && context.mounted) {
                  setDialogState(() => isSending = false);
                }
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text('Lupa Kata Sandi'),
              content: Form(
                key: resetFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Masukkan email akun Anda. Kami akan mengirim tautan untuk membuat kata sandi baru.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: resetEmailController,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !isSending,
                      validator: _validateEmail,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: isSending ? null : sendResetEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: isSending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Kirim Tautan'),
                ),
              ],
            );
          },
        );
      },
    );

    resetEmailController.dispose();
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
                    title: 'Masuk',
                    subtitle: 'Pilih tipe akun Anda',
                    icon: Icons.login_rounded,
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Masuk ke Akun',
                            style: AppTextStyles.heading3.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ModernTextField(
                            controller: _emailController,
                            label: 'Email',
                            icon: Icons.email_rounded,
                            semanticLabel: 'Email untuk login',
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 18),
                          ModernTextField(
                            controller: _passwordController,
                            label: 'Kata Sandi',
                            icon: Icons.lock_rounded,
                            semanticLabel: 'Kata sandi untuk masuk',
                            isPassword: true,
                            validator: _validatePassword,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : _showForgotPasswordDialog,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Lupa Kata Sandi?',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _AuthSubmitButton(
                            label: 'Masuk',
                            icon: Icons.arrow_forward_rounded,
                            isLoading: _isLoading,
                            onTap: _handleLogin,
                          ),
                          const SizedBox(height: 20),
                          Row(
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
                          const SizedBox(height: 20),
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
                  ),
                ],
              ),
            ),
          ),
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
                      Text(
                        label,
                        style: AppTextStyles.button.copyWith(
                          fontSize: 17,
                          letterSpacing: 0,
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
