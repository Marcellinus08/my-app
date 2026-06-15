import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../services/auth_service.dart';
import '../../services/tunanetra_voice_command_service.dart';
import 'tunanetra_profile_screen.dart';
import 'connected_family_accounts_screen.dart';
import 'password_settings_screen.dart';
import '../../widgets/app_dialog.dart';

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
      pageName: 'Pengaturan',
      onCommand: _handleSettingsVoiceCommand,
    );
  }

  Future<bool> _handleSettingsVoiceCommand(String command) async {
    if (command.contains('profil') || command.contains('profile')) {
      await _openSettingsSubPage(
        page: const TunaNetraProfileScreen(),
      );
      return true;
    }

    if (command.contains('kata sandi') ||
        command.contains('password') ||
        command.contains('sandi')) {
      await _openSettingsSubPage(
        page: const PasswordSettingsScreen(),
      );
      return true;
    }

    if (command.contains('keluarga') || command.contains('akun keluarga')) {
      await _openSettingsSubPage(
        page: const ConnectedFamilyAccountsScreen(),
      );
      return true;
    }

    return false;
  }

  Future<void> _openSettingsSubPage({
    required Widget page,
  }) async {
    await stopHomeVoiceCommandListener();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );

    if (!mounted) return;
    startHomeVoiceCommandListener(
      openingAnnouncement: 'Kembali ke pengaturan',
      pageName: 'Pengaturan',
      onCommand: _handleSettingsVoiceCommand,
    );
  }

  @override
  void dispose() {
    stopHomeVoiceCommandListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _authService.currentUser;
    final displayName = currentUser?.displayName?.trim();
    final email = currentUser?.email?.trim();

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
                  _buildAccountSummaryCard(
                    displayName: displayName,
                    email: email,
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle('Akun'),
                  const SizedBox(height: 12),
                  _buildSettingsGroup(
                    children: [
                      _SettingsItem(
                        icon: Icons.person_rounded,
                        title: 'Profil',
                        subtitle: 'Data diri dan informasi akun',
                        onTap: () => _openSettingsSubPage(
                          page: const TunaNetraProfileScreen(),
                        ),
                      ),
                      const _SettingsDivider(),
                      _SettingsItem(
                        icon: Icons.lock_rounded,
                        title: 'Kata Sandi',
                        subtitle: 'Ubah dan kelola keamanan akun',
                        onTap: () => _openSettingsSubPage(
                          page: const PasswordSettingsScreen(),
                        ),
                      ),
                      const _SettingsDivider(),
                      _SettingsItem(
                        icon: Icons.people_rounded,
                        title: 'Keluarga',
                        subtitle: 'Kelola akun pendamping dan relasi keluarga',
                        onTap: () => _openSettingsSubPage(
                          page: const ConnectedFamilyAccountsScreen(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildSectionTitle('Sesi'),
                  const SizedBox(height: 12),
                  _buildSettingsGroup(
                    children: [
                      _SettingsItem(
                        icon: Icons.logout_rounded,
                        title: 'Keluar',
                        subtitle: 'Keluar dari akun Teman Arah',
                        color: AppColors.error,
                        onTap: _showLogoutDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildInfoCard(),
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
                  'Pengaturan',
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
                  'Kelola akun anda',
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

  Widget _buildAccountSummaryCard({String? displayName, String? email}) {
    final visibleName = displayName?.isNotEmpty == true
        ? displayName!
        : 'Pengguna Teman Arah';
    final visibleEmail = email?.isNotEmpty == true
        ? email!
        : 'Akun aktif tersambung';

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.infoLight.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_circle_rounded,
              color: AppColors.primaryDark,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Akun aktif',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      visibleName,
                      maxLines: 1,
                      softWrap: false,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      visibleEmail,
                      maxLines: 1,
                      softWrap: false,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup({required List<Widget> children}) {
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

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Versi ${AppConstants.appVersion} · Pendamping navigasi untuk tunanetra',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLogoutDialog() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Keluar',
      description: 'Apakah Anda yakin ingin keluar dari akun ini?',
      icon: Icons.logout_rounded,
      iconColor: AppColors.error,
      cancelText: 'Batal',
      confirmText: 'Keluar',
      confirmButtonColor: AppColors.error,
      isDangerous: true,
    );

    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context);
    await _authService.logout();

    if (!mounted) return;
    navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color = AppColors.primaryDark,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDanger = color == AppColors.error;

    return Semantics(
      button: true,
      label: title,
      hint: subtitle ?? 'Ketuk dua kali untuk membuka',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDanger ? 0.10 : 0.09),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: isDanger
                          ? AppColors.error
                          : AppColors.textSecondary,
                      size: 18,
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

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 68),
      color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
    );
  }
}
