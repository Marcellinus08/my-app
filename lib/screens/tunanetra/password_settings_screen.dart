import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/tunanetra_voice_command_service.dart';
import '../../utils/app_feedback.dart';
import '../../utils/constants.dart';
import '../../widgets/app_dialog.dart';

class PasswordSettingsScreen extends StatefulWidget {
  const PasswordSettingsScreen({super.key, this.enableVoice = true});

  final bool enableVoice;

  @override
  State<PasswordSettingsScreen> createState() => _PasswordSettingsScreenState();
}

class _PasswordSettingsScreenState extends State<PasswordSettingsScreen>
    with TunaNetraHomeVoiceCommandMixin {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    if (widget.enableVoice) {
      startHomeVoiceCommandListener(
        openingAnnouncement: 'Halaman kata sandi dibuka',
        onCommand: _handleVoiceCommand,
      );
    }
  }

  @override
  void dispose() {
    if (widget.enableVoice) stopHomeVoiceCommandListener();
    super.dispose();
  }

  Future<bool> _handleVoiceCommand(String command) async {
    if (TunaNetraVoiceCommands.isSettingsCommand(command)) {
      await stopHomeVoiceCommandListener();
      if (!mounted) return true;
      Navigator.pop(context);
      return true;
    }
    return false;
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
      barrierColor: AppDialogStyle.barrierColor,
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
              try {
                await _authService.updatePasswordWithCurrentPassword(
                  currentPassword: currentPasswordController.text,
                  newPassword: newPasswordController.text,
                );

                if (!mounted) return;
                dialogWasClosed = true;
                navigator.pop();
                AppFeedback.success(
                  this.context,
                  'Kata sandi berhasil diubah.',
                  announce: widget.enableVoice,
                );
              } catch (error) {
                if (!mounted) return;
                AppFeedback.error(
                  this.context,
                  error,
                  fallback:
                      'Kata sandi belum dapat diubah. Periksa sandi lama lalu coba lagi.',
                  announce: widget.enableVoice,
                );
              } finally {
                if (!dialogWasClosed && context.mounted) {
                  setDialogState(() => isSaving = false);
                }
              }
            }

            return AlertDialog(
              scrollable: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              insetPadding: AppDialogStyle.insetPadding,
              titlePadding: AppDialogStyle.titlePadding,
              contentPadding: AppDialogStyle.contentPadding,
              actionsPadding: AppDialogStyle.actionPadding,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppDialogStyle.borderRadius,
                ),
                side: const BorderSide(color: AppDialogStyle.borderColor),
              ),
              title: _buildPasswordDialogTitle(
                icon: Icons.lock_reset_rounded,
                iconColor: AppColors.primaryDark,
                title: 'Ganti Sandi',
              ),
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
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
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
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Batal',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isSaving ? null : submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
                            : Text(
                                'Simpan',
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
            );
          },
        );
      },
    );

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  Widget _buildPasswordDialogTitle({
    required IconData icon,
    required Color iconColor,
    required String title,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showResetPasswordDialog() async {
    final email = _authService.currentUserEmail;

    if (email == null || email.isEmpty) {
      AppFeedback.show(
        context,
        'Email akun tidak ditemukan. Silakan masuk kembali.',
        type: AppFeedbackType.error,
        announce: widget.enableVoice,
      );
      return;
    }

    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Atur ulang sandi?',
      description: 'Kirim tautan atur ulang sandi ke email $email.',
      icon: Icons.email_rounded,
      iconColor: AppColors.primaryDark,
      cancelText: 'Batal',
      confirmText: 'Kirim Tautan',
      confirmButtonColor: AppColors.primaryDark,
    );

    if (confirmed != true) return;

    try {
      await _authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      AppFeedback.success(
        context,
        'Tautan atur ulang kata sandi dikirim ke $email.',
        announce: widget.enableVoice,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        error,
        fallback:
            'Tautan atur ulang belum dapat dikirim. Silakan coba lagi nanti.',
        announce: widget.enableVoice,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  _buildSecurityInfoCard(),
                  const SizedBox(height: 16),
                  _buildSectionTitle('Keamanan Akun'),
                  const SizedBox(height: 12),
                  _buildActionGroup(
                    children: [
                      _buildPasswordAction(
                        icon: Icons.lock_reset_rounded,
                        title: 'Ganti Sandi',
                        subtitle:
                            'Ubah kata sandi menggunakan kata sandi lama.',
                        color: AppColors.primaryDark,
                        onTap: _showChangePasswordDialog,
                      ),
                      const _PasswordDivider(),
                      _buildPasswordAction(
                        icon: Icons.email_rounded,
                        title: 'Atur Ulang Sandi',
                        subtitle: 'Kirim link reset kata sandi melalui email.',
                        color: AppColors.primary,
                        onTap: _showResetPasswordDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Pastikan email akun Anda aktif untuk menerima link reset kata sandi.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
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

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Material(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12),
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 23,
                  semanticLabel: 'Kembali',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kata Sandi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.heading3.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Kelola keamanan akun',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.18,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppColors.textSecondary,
                      size: 14,
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

  Widget _buildSecurityInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E3F4)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.infoLight.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: AppColors.primaryDark,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Jaga keamanan akun Anda dengan memperbarui kata sandi secara berkala.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGroup({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: AppTextStyles.bodyLarge.copyWith(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PasswordDivider extends StatelessWidget {
  const _PasswordDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 66,
      color: Color(0xFFEFF3F7),
    );
  }
}
