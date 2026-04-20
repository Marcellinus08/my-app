import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../models/user_models.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  late AuthService _authService;
  late UserService _userService;
  late FirebaseFirestore _firestore;

  late Stream<List<FamilyContact>> _contactsStream;
  List<FamilyContact> _currentContacts = []; // Track contacts terkini

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _userService = UserService();
    _firestore = FirebaseFirestore.instance;
    _setupStream();
  }

  void _setupStream() {
    final uid = _authService.currentUserId;
    print('🔍 Emergency Contacts - User UID: $uid');
    if (uid != null) {
      _contactsStream = _firestore
          .collection('users')
          .doc(uid)
          .snapshots()
          .map((snapshot) {
            print('📸 Snapshot received - exists: ${snapshot.exists}');
            if (snapshot.exists) {
              final data = snapshot.data() as Map<String, dynamic>?;
              print('📋 Data dari Firestore: ${data?.keys.toList()}');
              final familyContactsList =
                  data?['familyContacts'] as List<dynamic>? ?? [];
              print('👥 Family Contacts Count: ${familyContactsList.length}');
              print('📋 Contacts List: $familyContactsList');
              return familyContactsList
                  .map((contact) => FamilyContact.fromMap(
                      contact as Map<String, dynamic>))
                  .toList();
            }
            print('⚠️ Document does not exist');
            return [];
          });
    } else {
      print('❌ User UID is null');
      _contactsStream = Stream.value([]);
    }
  }

  Future<void> _saveContacts(List<FamilyContact> updatedContacts) async {
    try {
      final uid = _authService.currentUserId;
      if (uid != null) {
        await _userService.updateTunaNetraUser(
          uid,
          familyContacts: updatedContacts,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Kontak berhasil disimpan'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error saving contacts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showAddContactDialog({
    List<FamilyContact>? currentContacts,
    FamilyContact? contact,
    int? index,
  }) {
    currentContacts ??= [];
    final nameController = TextEditingController(text: contact?.name ?? '');
    final phoneController =
        TextEditingController(text: contact?.phoneNumber ?? '');
    final isEditing = contact != null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        title: Text(
          isEditing ? 'Edit Kontak Darurat' : 'Tambah Kontak Darurat',
          style: AppTextStyles.heading2.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(
                controller: nameController,
                label: 'Nama',
                hint: 'Masukkan nama kontak',
                icon: Icons.person_rounded,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: phoneController,
                label: 'No. Telepon',
                hint: 'Masukkan nomor telepon',
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Future.delayed(const Duration(milliseconds: 50), () {
                nameController.dispose();
                phoneController.dispose();
              });
            },
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.isEmpty ||
                  phoneController.text.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Nama dan No. Telepon wajib diisi'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              final newContact = FamilyContact(
                name: nameController.text,
                phoneNumber: phoneController.text,
              );

              // Create updated contacts list
              List<FamilyContact> updatedContacts = [...?currentContacts];
              if (isEditing && index != null) {
                updatedContacts[index] = newContact;
              } else {
                updatedContacts.add(newContact);
              }

              Navigator.pop(dialogContext);
              Future.delayed(const Duration(milliseconds: 50), () {
                nameController.dispose();
                phoneController.dispose();
                if (mounted) {
                  _saveContacts(updatedContacts);
                }
              });
            },
            child: Text(isEditing ? 'Simpan' : 'Tambah'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
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
              borderSide: BorderSide(
                color: AppColors.primary.withOpacity(0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.primary.withOpacity(0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 2,
              ),
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

  void _showDeleteConfirmDialog(
    int index,
    List<FamilyContact> currentContacts,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Kontak?'),
        content: Text(
          'Hapus "${currentContacts[index].name}" dari kontak darurat?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              // Create updated contacts list without the deleted item
              List<FamilyContact> updatedContacts = List.from(currentContacts);
              updatedContacts.removeAt(index);

              Navigator.pop(dialogContext);

              Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted) {
                  _saveContacts(updatedContacts);
                }
              });
            },
            child: const Text(
              'Hapus',
              style: TextStyle(color: Colors.red),
            ),
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
              AppColors.error.withOpacity(0.08),
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
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.error,
                              AppColors.error.withOpacity(0.8),
                            ],
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
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [
                                AppColors.error,
                                AppColors.error.withOpacity(0.7),
                              ],
                            ).createShader(bounds),
                            child: Text(
                              'Kontak Darurat',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 26,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Kelola kontak darurat Anda',
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
                child: StreamBuilder<List<FamilyContact>>(
                  stream: _contactsStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error: ${snapshot.error}',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.red,
                          ),
                        ),
                      );
                    }

                    final contacts = snapshot.data ?? [];
                    
                    // Update state dengan contacts terkini
                    if (_currentContacts != contacts) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _currentContacts = contacts;
                          });
                        }
                      });
                    }

                    if (contacts.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.phone_missed_rounded,
                              size: 64,
                              color: AppColors.error.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Belum ada kontak darurat',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tambahkan kontak darurat untuk memudahkan\npengguna menghubungi Anda saat butuh',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: contacts.length,
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white,
                                  Colors.white.withOpacity(0.95),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.error.withOpacity(0.08),
                                  blurRadius: 15,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(
                                color: AppColors.error.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.error,
                                        AppColors.error.withOpacity(0.7),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      contact.name[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        contact.name,
                                        style:
                                            AppTextStyles.bodyLarge.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.phone_rounded,
                                            size: 14,
                                            color:
                                                AppColors.textSecondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            contact.phoneNumber,
                                            style: AppTextStyles
                                                .bodyMedium
                                                .copyWith(
                                              color:
                                                  AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    GestureDetector(
                                      onTap: () =>
                                          _showAddContactDialog(
                                            currentContacts: contacts,
                                            contact: contact,
                                            index: index,
                                          ),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.edit_rounded,
                                          size: 18,
                                          color: AppColors.accent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: () =>
                                          _showDeleteConfirmDialog(
                                            index,
                                            contacts,
                                          ),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.error
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.delete_rounded,
                                          size: 18,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddContactDialog(
          currentContacts: _currentContacts,
        ),
        backgroundColor: AppColors.error,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah Kontak'),
      ),
    );
  }
}
