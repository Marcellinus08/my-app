import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/constants.dart';
import 'family_profile_screen.dart';

class FamilySettingsScreen extends StatefulWidget {
  const FamilySettingsScreen({super.key});

  @override
  State<FamilySettingsScreen> createState() => _FamilySettingsScreenState();
}

class _FamilySettingsScreenState extends State<FamilySettingsScreen> {
  final AuthService _authService = AuthService();

  bool _notificationsEnabled = true;
  bool _shareLocation = false;

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
                              'Pengaturan Keluarga',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Kelola preferensi dan tampilan family',
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                  children: [
                    const SizedBox(height: 10),
                    _buildSectionTitle('Profil Keluarga'),
                    const SizedBox(height: 16),
                    _buildOptionTile(
                      icon: Icons.person_rounded,
                      title: 'Lihat Profil',
                      subtitle: 'Buka halaman profil keluarga',
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FamilyProfileScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Akun dan Privasi'),
                    const SizedBox(height: 12),
                    _buildOptionTile(
                      icon: Icons.notifications_rounded,
                      title: 'Notifikasi keluarga',
                      subtitle: 'Terima peringatan perjalanan terbaru',
                      trailing: Switch(
                        value: _notificationsEnabled,
                        activeColor: AppColors.primary,
                        onChanged: (value) {
                          setState(() => _notificationsEnabled = value);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildOptionTile(
                      icon: Icons.location_on_rounded,
                      title: 'Bagikan lokasi',
                      subtitle: 'Kontrol kemampuan berbagi lokasi',
                      trailing: Switch(
                        value: _shareLocation,
                        activeColor: AppColors.primary,
                        onChanged: (value) {
                          setState(() => _shareLocation = value);
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Informasi Tambahan'),
                    const SizedBox(height: 12),
                    _buildOptionTile(
                      icon: Icons.info_rounded,
                      title: 'Tentang aplikasi',
                      subtitle: 'Versi dan detail penggunaan',
                    ),
                    const SizedBox(height: 12),
                    _buildOptionTile(
                      icon: Icons.help_outline_rounded,
                      title: 'Bantuan & dukungan',
                      subtitle: 'Cara menggunakan monitoring keluarga',
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Keluar'),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _showLogoutDialog,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.error.withOpacity(0.12)),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.error.withOpacity(0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.logout,
                                color: AppColors.error,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Keluar Akun',
                                    style: AppTextStyles.bodyLarge.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Keluar dari akun keluarga saat ini',
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
    return Text(
      title,
      style: AppTextStyles.bodyLarge.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
