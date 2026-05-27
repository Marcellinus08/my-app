import 'package:flutter/material.dart';
import 'dart:math';
import 'package:intl/intl.dart';
import '../../utils/constants.dart';
import '../../services/auth_service.dart';
import '../../services/pairing_service.dart';
import '../../services/tunanetra_voice_command_service.dart';
import '../../services/user_service.dart';
import '../../models/user_models.dart';

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
      print('❌ Error loading user data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveUserData() async {
    if (_nameController.text.isEmpty || _emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nama dan Email tidak boleh kosong'),
          backgroundColor: Colors.redAccent,
        ),
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

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profil berhasil diperbarui'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error saving user data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan profil: $e'),
            backgroundColor: Colors.redAccent,
          ),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Buat Kode Penghubung Baru?'),
        content: const Text(
          'Kode penghubung yang lama tidak akan bisa digunakan lagi. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
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

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Kode penghubung berhasil dibuat'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              } catch (e) {
                print('❌ Error regenerating pairing code: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal membuat kode penghubung: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text('Lanjutkan', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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
              // Header
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
                      onTap: () {
                        if (_isEditing) {
                          setState(() => _isEditing = false);
                          _loadUserData(); // Reset to original values
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
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                AppColors.primaryGradient.createShader(bounds),
                            child: Text(
                              _isEditing ? 'Ubah Profil' : 'Profil Saya',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 26,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isEditing
                                ? 'Ubah data pribadi'
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
              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _user == null
                    ? Center(
                        child: Text(
                          'Data pengguna tidak ditemukan',
                          style: AppTextStyles.bodyLarge,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        children: [
                          // User Info Card
                          if (!_isEditing)
                            _buildInfoCard()
                          else
                            _buildEditForm(),
                          const SizedBox(height: 20),
                          // Action Button
                          if (!_isEditing)
                            GestureDetector(
                              onTap: () {
                                setState(() => _isEditing = true);
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
                                    const Icon(
                                      Icons.edit_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Ubah Profil',
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: _saveUserData,
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
                                    const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Simpan Perubahan',
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
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

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.1), width: 1),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.person_rounded,
            label: 'Nama',
            value: _user!.name,
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 1),
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: Icons.email_rounded,
            label: 'Email',
            value: _user!.email,
            color: AppColors.accent,
          ),
          const SizedBox(height: 16),
          Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 1),
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: Icons.phone_rounded,
            label: 'No. Telepon',
            value: _user!.phoneNumber.isEmpty
                ? 'Belum diatur'
                : _user!.phoneNumber,
            color: AppColors.success,
          ),
          const SizedBox(height: 16),
          Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 1),
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: Icons.badge_rounded,
            label: 'Tipe',
            value: 'Pengguna',
            color: AppColors.warning,
          ),
          const SizedBox(height: 16),
          Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 1),
          const SizedBox(height: 16),
          _buildInfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Bergabung',
            value: _formatDate(_user!.createdAt),
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 1),
          const SizedBox(height: 16),
          _buildPairingCodeRow(),
        ],
      ),
    );
  }

  Widget _buildPairingCodeRow() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.vpn_key_rounded, color: AppColors.accent, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kode Penghubung',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _user!.pairingCode.isEmpty
                    ? 'Tidak ada kode'
                    : _user!.pairingCode,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Courier',
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _regeneratePairingCode,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.refresh_rounded,
              color: AppColors.accent,
              size: 18,
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
                      fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.1), width: 1),
      ),
      child: Column(
        children: [
          _buildEditField(
            label: 'Nama',
            controller: _nameController,
            icon: Icons.person_rounded,
            hint: 'Masukkan nama lengkap',
          ),
          const SizedBox(height: 20),
          _buildEditField(
            label: 'Email',
            controller: _emailController,
            icon: Icons.email_rounded,
            hint: 'Masukkan email',
            keyboardType: TextInputType.emailAddress,
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
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
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
