import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/tunanetra_voice_command_service.dart';
import '../../utils/constants.dart';

class PasswordSettingsScreen extends StatefulWidget {
  const PasswordSettingsScreen({super.key});

  @override
  State<PasswordSettingsScreen> createState() => _PasswordSettingsScreenState();
}

class _PasswordSettingsScreenState extends State<PasswordSettingsScreen>
    with TunaNetraHomeVoiceCommandMixin {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    startHomeVoiceCommandListener(
      openingAnnouncement: 'Halaman kata sandi dibuka',
    );
  }

  @override
  void dispose() {
    stopHomeVoiceCommandListener();
    super.dispose();
  }

  Future<void> _showChangePasswordDialog() async {
    final formKey = GlobalKey<FormState>();
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    var isSaving = false;
    var obscureCurrentPassword = true;
    var obscureNewPassword = true;
    var obscureConfirmPassword = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSaving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) {
                return;
              }

              setDialogState(() => isSaving = true);
              var dialogWasClosed = false;
              final navigator = Navigator.of(dialogContext);
              final messenger = ScaffoldMessenger.of(this.context);

              try {
                await _authService.updatePasswordWithCurrentPassword(
                  currentPassword: currentPasswordController.text,
                  newPassword: newPasswordController.text,
                );

                if (!mounted) return;
                dialogWasClosed = true;
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Kata sandi berhasil diubah'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!mounted) return;

                final message = e is Exception
                    ? e.toString().replaceAll('Exception: ', '')
                    : e.toString();

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(message),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              } finally {
                if (!dialogWasClosed && context.mounted) {
                  setDialogState(() => isSaving = false);
                }
              }
            }

            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text('Ganti Sandi'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrentPassword,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        labelText: 'Sandi lama',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: isSaving
                              ? null
                              : () {
                                  setDialogState(() {
                                    obscureCurrentPassword =
                                        !obscureCurrentPassword;
                                  });
                                },
                          icon: Icon(
                            obscureCurrentPassword
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Sandi lama harus diisi';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newPasswordController,
                      obscureText: obscureNewPassword,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        labelText: 'Sandi baru',
                        prefixIcon: const Icon(Icons.lock_reset_rounded),
                        suffixIcon: IconButton(
                          onPressed: isSaving
                              ? null
                              : () {
                                  setDialogState(() {
                                    obscureNewPassword = !obscureNewPassword;
                                  });
                                },
                          icon: Icon(
                            obscureNewPassword
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Sandi baru harus diisi';
                        }
                        if (value.length < 6) {
                          return 'Sandi minimal 6 karakter';
                        }
                        if (value == currentPasswordController.text) {
                          return 'Sandi baru harus berbeda';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirmPassword,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        labelText: 'Konfirmasi sandi',
                        prefixIcon: const Icon(Icons.verified_user_rounded),
                        suffixIcon: IconButton(
                          onPressed: isSaving
                              ? null
                              : () {
                                  setDialogState(() {
                                    obscureConfirmPassword =
                                        !obscureConfirmPassword;
                                  });
                                },
                          icon: Icon(
                            obscureConfirmPassword
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Konfirmasi sandi harus diisi';
                        }
                        if (value != newPasswordController.text) {
                          return 'Konfirmasi sandi tidak sama';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          await Future<void>.delayed(
                            const Duration(milliseconds: 50),
                          );
                          if (!context.mounted) return;
                          Navigator.of(
                            dialogContext,
                            rootNavigator: true,
                          ).maybePop();
                        },
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  Future<void> _showResetPasswordDialog() async {
    final email = _authService.currentUserEmail;

    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email akun tidak ditemukan'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    var isSending = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSending,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendResetEmail() async {
              setDialogState(() => isSending = true);
              var dialogWasClosed = false;
              final navigator = Navigator.of(dialogContext);
              final messenger = ScaffoldMessenger.of(this.context);

              try {
                await _authService.sendPasswordResetEmail(email);

                if (!mounted) return;
                dialogWasClosed = true;
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Tautan atur ulang sandi dikirim ke $email'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!mounted) return;

                final message = e is Exception
                    ? e.toString().replaceAll('Exception: ', '')
                    : e.toString();

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(message),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              } finally {
                if (!dialogWasClosed && context.mounted) {
                  setDialogState(() => isSending = false);
                }
              }
            }

            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text('Atur Ulang Sandi'),
              content: Text(
                'Kirim tautan atur ulang sandi ke email: $email?',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          await Future<void>.delayed(
                            const Duration(milliseconds: 50),
                          );
                          if (!context.mounted) return;
                          Navigator.of(
                            dialogContext,
                            rootNavigator: true,
                          ).maybePop();
                        },
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
                          width: 18,
                          height: 18,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFAFBFC),
              AppColors.primaryLight.withOpacity(0.08),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.white, Colors.white.withOpacity(0.95)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textSecondary.withOpacity(0.15),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.textSecondary.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                AppColors.primaryGradient.createShader(bounds),
                            child: Text(
                              'Kata Sandi',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 26,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Kelola keamanan akses akun',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white,
                            Colors.white.withOpacity(0.95),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildPasswordAction(
                            icon: Icons.lock_reset_rounded,
                            title: 'Ganti Sandi',
                            color: AppColors.primary,
                            onTap: _showChangePasswordDialog,
                          ),
                          Divider(
                            height: 1,
                            indent: 20,
                            endIndent: 20,
                            color: AppColors.textSecondary.withOpacity(0.1),
                          ),
                          _buildPasswordAction(
                            icon: Icons.email_rounded,
                            title: 'Atur Ulang Sandi',
                            color: AppColors.accent,
                            onTap: _showResetPasswordDialog,
                          ),
                        ],
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

  Widget _buildPasswordAction({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.all(20),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
      title: Text(
        title,
        style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700),
      ),
      trailing: Icon(Icons.arrow_forward_ios_rounded, color: color, size: 20),
      onTap: onTap,
    );
  }
}
