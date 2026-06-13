import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_feedback.dart';
import '../../utils/constants.dart';

class FamilyProfileScreen extends StatefulWidget {
  const FamilyProfileScreen({super.key});

  @override
  State<FamilyProfileScreen> createState() => _FamilyProfileScreenState();
}

class _FamilyProfileScreenState extends State<FamilyProfileScreen> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();

  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  Map<String, dynamic>? _familyProfile;
  String? _loadError;
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _loadFamilyProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadFamilyProfile() async {
    try {
      final uid = _authService.currentUserId;
      if (uid == null) {
        setState(() {
          _loadError = 'Tidak dapat memuat profil keluarga.';
          _isLoading = false;
        });
        return;
      }

      final profile = await _userService.getUserData(uid);
      setState(() {
        _familyProfile = profile;
        _syncControllers(profile);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = 'Gagal memuat profil keluarga.';
        _isLoading = false;
      });
    }
  }

  String _formatDate(dynamic value) {
    const pattern = 'dd-MM-yyyy';
    if (value is DateTime) {
      return DateFormat(pattern).format(value);
    }
    if (value is Timestamp) {
      return DateFormat(pattern).format(value.toDate());
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return DateFormat(pattern).format(parsed);
      }
    }
    return value?.toString() ?? '-';
  }

  String _formatUserType(dynamic value) {
    final type = value?.toString().toLowerCase();
    if (type == 'family' || type == 'usertype.family') {
      return 'Keluarga';
    }
    if (type == 'tunanetra' || type == 'usertype.tunanetra') {
      return 'Pengguna';
    }
    return value?.toString() ?? '-';
  }

  void _syncControllers(Map<String, dynamic>? profile) {
    _nameController.text = profile?['name']?.toString() ?? '';
    _emailController.text = profile?['email']?.toString() ?? '';
    _phoneController.text = profile?['phoneNumber']?.toString() ?? '';
  }

  Future<void> _saveFamilyProfile() async {
    final name = _nameController.text.trim();
    final phoneNumber = _phoneController.text.trim();

    if (name.isEmpty) {
      AppFeedback.show(
        context,
        'Nama harus diisi.',
        type: AppFeedbackType.error,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final uid = _authService.currentUserId;
      if (uid == null) {
        throw Exception('User tidak ditemukan');
      }

      await _userService.updateFamilyUser(
        uid,
        name: name,
        phoneNumber: phoneNumber,
      );

      if (!mounted) return;

      setState(() {
        _familyProfile = {
          ...?_familyProfile,
          'name': name,
          'phoneNumber': phoneNumber,
        };
        _isEditing = false;
        _isSaving = false;
      });

      AppFeedback.success(context, 'Profil berhasil diperbarui.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppFeedback.error(
        context,
        error,
        fallback: 'Profil belum dapat diperbarui. Silakan coba lagi.',
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
                  _buildSectionTitle('Informasi Profil'),
                  const SizedBox(height: 12),
                  if (_isLoading) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ] else if (_familyProfile == null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        _loadError ?? 'Data profil keluarga tidak tersedia.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ] else ...[
                    if (_isEditing) _buildEditForm() else _buildProfileCard(),
                    const SizedBox(height: 16),
                    _buildActionButton(),
                  ],
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
                  setState(() {
                    _isEditing = false;
                    _syncControllers(_familyProfile);
                  });
                  return;
                }
                Navigator.pop(context);
              },
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  _isEditing ? Icons.close_rounded : Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 23,
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
                  _isEditing ? 'Ubah data keluarga' : 'Kelola informasi akun',
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

  Widget _buildProfileCard() {
    final profile = _familyProfile!;
    final createdAtLabel = _formatDate(profile['createdAt']);

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
            value: profile['name']?.toString() ?? 'Keluarga',
            color: AppColors.primaryDark,
          ),
          const _ProfileDivider(),
          _buildInfoRow(
            icon: Icons.email_rounded,
            label: 'Email',
            value: profile['email']?.toString() ?? '-',
            color: AppColors.primaryDark,
          ),
          const _ProfileDivider(),
          _buildInfoRow(
            icon: Icons.phone_rounded,
            label: 'No. Telepon',
            value: profile['phoneNumber']?.toString().isEmpty ?? true
                ? 'Belum diatur'
                : profile['phoneNumber'].toString(),
            color: AppColors.primaryDark,
          ),
          const _ProfileDivider(),
          _buildInfoRow(
            icon: Icons.badge_rounded,
            label: 'Tipe',
            value: _formatUserType(profile['userType']),
            color: AppColors.primaryDark,
          ),
          const _ProfileDivider(),
          _buildInfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Bergabung',
            value: createdAtLabel,
            color: AppColors.primaryDark,
          ),
        ],
      ),
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
          width: 42,
          height: 42,
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
            hint: 'Masukkan nama keluarga',
          ),
          const SizedBox(height: 14),
          _buildEditField(
            label: 'Email',
            controller: _emailController,
            icon: Icons.email_rounded,
            hint: 'Masukkan email',
            keyboardType: TextInputType.emailAddress,
            readOnly: true,
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
    bool readOnly = false,
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
          readOnly: readOnly,
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
            fillColor: readOnly
                ? const Color(0xFFF1F5F9)
                : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    final label = _isEditing ? 'Simpan Perubahan' : 'Ubah Profil';
    final icon = _isEditing ? Icons.check_rounded : Icons.edit_rounded;
    final onTap = _isEditing
        ? _saveFamilyProfile
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
