import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/constants.dart';
import '../tunanetra/password_settings_screen.dart';
import 'family_connected_tunanetra_screen.dart';
import 'family_profile_screen.dart';

class FamilySettingsScreen extends StatefulWidget {
  const FamilySettingsScreen({super.key});

  @override
  State<FamilySettingsScreen> createState() => _FamilySettingsScreenState();
}

class _FamilySettingsScreenState extends State<FamilySettingsScreen> {
  final AuthService _authService = AuthService();

  Future<void> _showLogoutDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Apakah Anda yakin ingin keluar dari akun ini?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Keluar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    try {
      await _authService.logout();
    } catch (_) {
      // ignore logout errors, still navigate to login
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (route) => false,
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
                              'Pengaturan',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Kelola akses akun',
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
                          _buildAccountTile(
                            icon: Icons.person_rounded,
                            title: 'Profil Saya',
                            gradient: AppColors.primaryGradient,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const FamilyProfileScreen(),
                                ),
                              );
                            },
                          ),
                          _buildDivider(),
                          _buildAccountTile(
                            icon: Icons.lock_rounded,
                            title: 'Kata Sandi',
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primary.withOpacity(0.8),
                              ],
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const PasswordSettingsScreen(),
                                ),
                              );
                            },
                          ),
                          _buildDivider(),
                          _buildAccountTile(
                            icon: Icons.accessibility_new_rounded,
                            title: 'Pengguna',
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primary.withOpacity(0.8),
                              ],
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const FamilyConnectedTunaNetraScreen(),
                                ),
                              );
                            },
                          ),
                          _buildDivider(),
                          _buildAccountTile(
                            icon: Icons.logout_rounded,
                            title: 'Keluar',
                            gradient: LinearGradient(
                              colors: [
                                AppColors.error,
                                AppColors.error.withOpacity(0.8),
                              ],
                            ),
                            trailingColor: AppColors.error,
                            onTap: _showLogoutDialog,
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

  Widget _buildDivider() {
    return Divider(
      height: 1,
      indent: 20,
      endIndent: 20,
      color: AppColors.textSecondary.withOpacity(0.1),
    );
  }

  Widget _buildAccountTile({
    required IconData icon,
    required String title,
    required Gradient gradient,
    required VoidCallback onTap,
    Color? trailingColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.all(20),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 28, color: Colors.white),
      ),
      title: Text(
        title,
        style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
      ),
      trailing: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            trailingColor ?? AppColors.primary,
            (trailingColor ?? AppColors.primary).withOpacity(0.7),
          ],
        ).createShader(bounds),
        child: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 20,
          color: Colors.white,
        ),
      ),
      onTap: onTap,
    );
  }
}
