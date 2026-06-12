import 'package:flutter/material.dart';
import 'dart:math';
import 'package:intl/intl.dart';
import '../../utils/app_feedback.dart';
import '../../utils/constants.dart';
import '../../services/auth_service.dart';
import '../../services/pairing_service.dart';
import '../../services/tunanetra_voice_command_service.dart';
import '../../services/user_service.dart';
import '../../models/user_models.dart';
import '../../widgets/app_dialog.dart';

class TunaNetraProfileScreen extends StatefulWidget {
  const TunaNetraProfileScreen({super.key});

  @override
  State<TunaNetraProfileScreen> createState() => _TunaNetraProfileScreenState();
}

class _TunaNetraProfileScreenState extends State<TunaNetraProfileScreen>
    with TunaNetraHomeVoiceCommandMixin {
  late AuthService _authService;
  late UserService _userService;
  final PairingService _pairingService = PairingService();

  TunaNetraUser? _user;
  bool _isLoading = true;
  bool _isEditing = false;

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _userService = UserService();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _loadUserData();
    startHomeVoiceCommandListener(openingAnnouncement: 'Halaman profil dibuka');
  }

  Future<void> _loadUserData() async {
    try {
      final uid = _authService.currentUserId;
      if (uid != null) {
        final user = await _userService.getTunaNetraUser(uid);
        if (mounted) {
          setState(() {
            _user = user;
            _isLoading = false;
            // Populate controllers
            if (user != null) {
              _nameController.text = user.name;
              _emailController.text = user.email;
              _phoneController.text = user.phoneNumber;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[TunaNetraProfile] Error loading user data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveUserData() async {
    if (_nameController.text.isEmpty || _emailController.text.isEmpty) {
      AppFeedback.show(
        context,
        'Nama dan email harus diisi.',
        type: AppFeedbackType.error,
        announce: true,
      );
      return;
    }

    try {
      final uid = _authService.currentUserId;
      if (uid != null) {
        // Update user data
        await _userService.updateTunaNetraUser(
          uid,
          name: _nameController.text,
          phoneNumber: _phoneController.text,
        );

        if (mounted) {
          setState(() {
            _isEditing = false;
            _user = TunaNetraUser(
              uid: _user!.uid,
              email: _emailController.text,
              name: _nameController.text,
              phoneNumber: _phoneController.text,
              familyContacts: _user!.familyContacts,
              pairingCode: _user!.pairingCode,
              createdAt: _user!.createdAt,
              isEmailVerified: _user!.isEmailVerified,
            );
          });

          AppFeedback.success(
            context,
            'Profil berhasil diperbarui.',
            announce: true,
          );
        }
      }
    } catch (error) {
      debugPrint('[TunaNetraProfile] Error saving user data: $error');
      if (mounted) {
        AppFeedback.error(
          context,
          error,
          fallback: 'Profil belum dapat disimpan. Silakan coba lagi.',
          announce: true,
        );
      }
    }
  }

  /// Generate random pairing code
  String _generatePairingCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(
      8,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  String _formatDate(DateTime value) {
    return DateFormat('dd-MM-yyyy').format(value);
  }

  /// Regenerate pairing code
  Future<void> _regeneratePairingCode() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Buat kode baru?',
      description:
          'Kode penghubung lama tidak bisa digunakan lagi setelah diganti.',
      icon: Icons.refresh_rounded,
      iconColor: AppColors.primaryDark,
      cancelText: 'Batal',
      confirmText: 'Buat Kode',
      confirmButtonColor: AppColors.primaryDark,
    );

    if (confirmed != true) return;

    try {
      final uid = _authService.currentUserId;
      if (uid != null) {
        final newCode = _generatePairingCode();
        await _pairingService.savePairingCode(uid, newCode);

        if (mounted) {
          setState(() {
            _user = TunaNetraUser(
              uid: _user!.uid,
              email: _user!.email,
              name: _user!.name,
              phoneNumber: _user!.phoneNumber,
              familyContacts: _user!.familyContacts,
              pairingCode: newCode,
              createdAt: _user!.createdAt,
              isEmailVerified: _user!.isEmailVerified,
            );
          });

          AppFeedback.success(
            this.context,
            'Kode penghubung berhasil dibuat.',
            announce: true,
          );
        }
      }
    } catch (error) {
      debugPrint('[TunaNetraProfile] Error regenerating pairing code: $error');
      if (mounted) {
        AppFeedback.error(
          this.context,
          error,
          fallback: 'Kode penghubung belum dapat dibuat. Silakan coba lagi.',
          announce: true,
        );
      }
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
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _user == null
                  ? _buildEmptyState()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: [
                        _buildSectionTitle('Informasi Profil'),
                        const SizedBox(height: 12),
                        if (_isEditing) _buildEditForm() else _buildInfoCard(),
                        const SizedBox(height: 16),
                        _buildActionButton(),
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
              onTap: () {
                if (_isEditing) {
                  setState(() => _isEditing = false);
                  _loadUserData();
                  return;
                }
                Navigator.pop(context);
              },
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  _isEditing ? Icons.close_rounded : Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 23,
                  semanticLabel: _isEditing
                      ? 'Batal mengubah profil'
                      : 'Kembali',
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
                  _isEditing ? 'Ubah Profil' : 'Profil Saya',
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
                  _isEditing ? 'Ubah data pribadi' : 'Kelola informasi akun',
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

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        'Data pengguna tidak ditemukan',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    final label = _isEditing ? 'Simpan Perubahan' : 'Ubah Profil';
    final icon = _isEditing ? Icons.check_rounded : Icons.edit_rounded;
    final onTap = _isEditing
        ? _saveUserData
        : () => setState(() => _isEditing = true);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle: AppTextStyles.bodySmall.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.person_rounded,
            label: 'Nama',
            value: _user!.name,
            color: AppColors.primaryDark,
          ),
          const _ProfileDivider(),
          _buildInfoRow(
            icon: Icons.email_rounded,
            label: 'Email',
            value: _user!.email,
            color: AppColors.accent,
          ),
          const _ProfileDivider(),
          _buildInfoRow(
            icon: Icons.phone_rounded,
            label: 'No. Telepon',
            value: _user!.phoneNumber.isEmpty
                ? 'Belum diatur'
                : _user!.phoneNumber,
            color: AppColors.success,
          ),
          const _ProfileDivider(),
          _buildInfoRow(
            icon: Icons.badge_rounded,
            label: 'Tipe',
            value: 'Pengguna',
            color: AppColors.warning,
          ),
          const _ProfileDivider(),
          _buildInfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Bergabung',
            value: _formatDate(_user!.createdAt),
            color: AppColors.primaryDark,
          ),
          const _ProfileDivider(),
          _buildPairingCodeRow(),
        ],
      ),
    );
  }

  Widget _buildPairingCodeRow() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.infoLight.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.vpn_key_rounded,
            color: AppColors.primaryDark,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kode Penghubung',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      _user!.pairingCode.isEmpty
                          ? 'Tidak ada kode'
                          : _user!.pairingCode,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _regeneratePairingCode,
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.infoLight.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: AppColors.primaryDark,
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
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
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 12.5,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      child: Column(
        children: [
          _buildEditField(
            label: 'Nama',
            controller: _nameController,
            icon: Icons.person_rounded,
            hint: 'Masukkan nama lengkap',
          ),
          const SizedBox(height: 14),
          _buildEditField(
            label: 'Email',
            controller: _emailController,
            icon: Icons.email_rounded,
            hint: 'Masukkan email',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _buildEditField(
            label: 'No. Telepon',
            controller: _phoneController,
            icon: Icons.phone_rounded,
            hint: 'Masukkan nomor telepon',
            keyboardType: TextInputType.phone,
          ),
        ],
      ),
    );
  }

  Widget _buildEditField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppColors.primaryDark, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primaryDark,
                width: 1.4,
              ),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    stopHomeVoiceCommandListener();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}

class _ProfileDivider extends StatelessWidget {
  const _ProfileDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 12),
      color: const Color(0xFFE2E8F0).withValues(alpha: 0.78),
    );
  }
}
