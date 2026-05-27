import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../services/auth_service.dart';
import '../../services/tts_service.dart';
import '../../services/tunanetra_voice_command_service.dart';
import 'tunanetra_profile_screen.dart';
import 'connected_family_accounts_screen.dart';
import 'password_settings_screen.dart';

class TunaNetraSettingsScreen extends StatefulWidget {
  const TunaNetraSettingsScreen({super.key});

  @override
  State<TunaNetraSettingsScreen> createState() =>
      _TunaNetraSettingsScreenState();
}

class _TunaNetraSettingsScreenState extends State<TunaNetraSettingsScreen>
    with TunaNetraHomeVoiceCommandMixin {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    startHomeVoiceCommandListener(
      openingAnnouncement: 'Halaman pengaturan dibuka',
      onCommand: _handleSettingsVoiceCommand,
    );
  }

  Future<bool> _handleSettingsVoiceCommand(String command) async {
    if (command.contains('profil') || command.contains('profile')) {
      await _openSettingsSubPage(
        announcement: 'Membuka profil',
        page: const TunaNetraProfileScreen(),
      );
      return true;
    }

    if (command.contains('kata sandi') ||
        command.contains('password') ||
        command.contains('sandi')) {
      await _openSettingsSubPage(
        announcement: 'Membuka kata sandi',
        page: const PasswordSettingsScreen(),
      );
      return true;
    }

    if (command.contains('keluarga') || command.contains('akun keluarga')) {
      await _openSettingsSubPage(
        announcement: 'Membuka akun keluarga',
        page: const ConnectedFamilyAccountsScreen(),
      );
      return true;
    }

    return false;
  }

  Future<void> _openSettingsSubPage({
    required String announcement,
    required Widget page,
  }) async {
    await stopHomeVoiceCommandListener();
    await TTSService().speak(announcement);
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );

    if (!mounted) return;
    startHomeVoiceCommandListener(onCommand: _handleSettingsVoiceCommand);
  }

  @override
  void dispose() {
    stopHomeVoiceCommandListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFAFBFC),
              const Color(0xFF64748B).withOpacity(0.08),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Elegant Header
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF64748B), Color(0xFF475569)],
                          ),
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
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF64748B), Color(0xFF475569)],
                            ).createShader(bounds),
                            child: Text(
                              'Pengaturan',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 26,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Kelola akun anda',
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
                    _buildSectionTitle('Akun'),
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
                          ListTile(
                            contentPadding: const EdgeInsets.all(20),
                            leading: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                size: 28,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              'Profil',
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: ShaderMask(
                              shaderCallback: (bounds) => AppColors
                                  .primaryGradient
                                  .createShader(bounds),
                              child: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            onTap: () async {
                              await stopHomeVoiceCommandListener();
                              if (!context.mounted) return;
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const TunaNetraProfileScreen(),
                                ),
                              );
                              if (!context.mounted) return;
                              startHomeVoiceCommandListener(
                                onCommand: _handleSettingsVoiceCommand,
                              );
                            },
                          ),
                          Divider(
                            height: 1,
                            indent: 20,
                            endIndent: 20,
                            color: AppColors.textSecondary.withOpacity(0.1),
                          ),
                          ListTile(
                            contentPadding: const EdgeInsets.all(20),
                            leading: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary,
                                    AppColors.primary.withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.lock_rounded,
                                size: 28,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              'Kata Sandi',
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: ShaderMask(
                              shaderCallback: (bounds) => AppColors
                                  .primaryGradient
                                  .createShader(bounds),
                              child: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            onTap: () async {
                              await stopHomeVoiceCommandListener();
                              if (!context.mounted) return;
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const PasswordSettingsScreen(),
                                ),
                              );
                              if (!context.mounted) return;
                              startHomeVoiceCommandListener(
                                onCommand: _handleSettingsVoiceCommand,
                              );
                            },
                          ),
                          Divider(
                            height: 1,
                            indent: 20,
                            endIndent: 20,
                            color: AppColors.textSecondary.withOpacity(0.1),
                          ),
                          ListTile(
                            contentPadding: const EdgeInsets.all(20),
                            leading: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary,
                                    AppColors.primary.withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.people_rounded,
                                size: 28,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              'Keluarga',
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: ShaderMask(
                              shaderCallback: (bounds) => AppColors
                                  .primaryGradient
                                  .createShader(bounds),
                              child: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            onTap: () async {
                              await stopHomeVoiceCommandListener();
                              if (!context.mounted) return;
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ConnectedFamilyAccountsScreen(),
                                ),
                              );
                              if (!context.mounted) return;
                              startHomeVoiceCommandListener(
                                onCommand: _handleSettingsVoiceCommand,
                              );
                            },
                          ),
                          Divider(
                            height: 1,
                            indent: 20,
                            endIndent: 20,
                            color: AppColors.textSecondary.withOpacity(0.1),
                          ),
                          ListTile(
                            contentPadding: const EdgeInsets.all(20),
                            leading: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.error,
                                    AppColors.error.withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.logout_rounded,
                                size: 28,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              'Keluar',
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [
                                  AppColors.error,
                                  AppColors.error.withOpacity(0.7),
                                ],
                              ).createShader(bounds),
                              child: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            onTap: () {
                              _showLogoutDialog();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, left: 5),
      child: ShaderMask(
        shaderCallback: (bounds) =>
            AppColors.primaryGradient.createShader(bounds),
        child: Text(
          title,
          style: AppTextStyles.heading3.copyWith(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppColors.error, AppColors.error.withOpacity(0.8)],
          ).createShader(bounds),
          child: const Text(
            'Keluar',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        content: const Text(
          'Apakah Anda yakin ingin keluar?',
          style: AppTextStyles.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: Text(
              'BATAL',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.error, AppColors.error.withOpacity(0.8)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final navigator = Navigator.of(this.context);

                await _authService.logout();

                if (!mounted) return;
                navigator.pushNamedAndRemoveUntil(
                  AppRoutes.login,
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'KELUAR',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
