import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/auth_service.dart';
import '../../services/user_service.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nama tidak boleh kosong'),
          backgroundColor: Colors.redAccent,
        ),
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil berhasil diperbarui'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memperbarui profil: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
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
                      onTap: () {
                        if (_isEditing) {
                          setState(() {
                            _isEditing = false;
                            _syncControllers(_familyProfile);
                          });
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _isEditing
                              ? Icons.close_rounded
                              : Icons.arrow_back_rounded,
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
                              _isEditing ? 'Edit Profil' : 'Profil Saya',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isEditing
                                ? 'Ubah data keluarga'
                                : 'Kelola informasi akun',
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
                    if (_isLoading) ...[
                      const SizedBox(height: 24),
                      const Center(child: CircularProgressIndicator()),
                    ] else if (_familyProfile == null) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Text(
                          _loadError ?? 'Data profil keluarga tidak tersedia.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ] else ...[
                      if (_isEditing) _buildEditForm() else _buildProfileCard(),
                      const SizedBox(height: 20),
                      _buildActionButton(),
                    ],
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

  Widget _buildProfileCard() {
    final profile = _familyProfile!;
    final createdAtLabel = _formatDate(profile['createdAt']);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(
            icon: Icons.family_restroom_rounded,
            label: 'Nama',
            value: profile['name']?.toString() ?? 'Keluarga',
            color: AppColors.primary,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.email_rounded,
            label: 'Email',
            value: profile['email']?.toString() ?? '-',
            color: AppColors.accent,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.phone_rounded,
            label: 'No. Telepon',
            value: profile['phoneNumber']?.toString().isEmpty ?? true
                ? 'Belum diatur'
                : profile['phoneNumber'].toString(),
            color: AppColors.success,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.badge_rounded,
            label: 'Tipe',
            value: _formatUserType(profile['userType']),
            color: AppColors.warning,
          ),
          _buildDivider(),
          _buildInfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Bergabung',
            value: createdAtLabel,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Divider(
        color: AppColors.textSecondary.withOpacity(0.1),
        height: 1,
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
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
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildEditField(
            label: 'Nama',
            controller: _nameController,
            icon: Icons.family_restroom_rounded,
            hint: 'Masukkan nama keluarga',
          ),
          const SizedBox(height: 20),
          _buildEditField(
            label: 'Email',
            controller: _emailController,
            icon: Icons.email_rounded,
            hint: 'Email akun',
            keyboardType: TextInputType.emailAddress,
            readOnly: true,
          ),
          const SizedBox(height: 20),
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
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppColors.primary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            filled: true,
            fillColor: readOnly
                ? AppColors.textSecondary.withOpacity(0.05)
                : Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    return GestureDetector(
      onTap: _isSaving
          ? null
          : () {
              if (_isEditing) {
                _saveFamilyProfile();
              } else {
                setState(() => _isEditing = true);
              }
            },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isSaving)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              Icon(
                _isEditing ? Icons.check_rounded : Icons.edit_rounded,
                color: Colors.white,
                size: 20,
              ),
            const SizedBox(width: 8),
            Text(
              _isEditing
                  ? (_isSaving ? 'Menyimpan...' : 'Simpan Perubahan')
                  : 'Edit Profil',
              style: AppTextStyles.bodyLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
