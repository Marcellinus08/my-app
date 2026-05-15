import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/constants.dart';
import '../../services/connected_family_service.dart';
import '../../services/pairing_service.dart';

class ConnectedFamilyAccountsScreen extends StatefulWidget {
  const ConnectedFamilyAccountsScreen({super.key});

  @override
  State<ConnectedFamilyAccountsScreen> createState() =>
      _ConnectedFamilyAccountsScreenState();
}

class _ConnectedFamilyAccountsScreenState
    extends State<ConnectedFamilyAccountsScreen> {
  final ConnectedFamilyService _familyService = ConnectedFamilyService();
  final PairingService _pairingService = PairingService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _cleanupDuplicates();
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
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                AppColors.primaryGradient.createShader(bounds),
                            child: Text(
                              'Akun Keluarga',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 26,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Keluarga yang terhubung',
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

              // Family Accounts List
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _familyService.getConnectedFamiliesStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return _buildErrorState(snapshot.error.toString());
                    }

                    var connectedFamilies = snapshot.data ?? [];

                    // If no connected families in main field, try loading from subcollection
                    if (connectedFamilies.isEmpty) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: _firestore
                            .collection('users')
                            .doc(_auth.currentUser?.uid)
                            .collection('family_members')
                            .snapshots(),
                        builder: (context, subSnapshot) {
                          if (subSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            );
                          }

                          if (subSnapshot.hasError) {
                            return _buildErrorState(
                              subSnapshot.error.toString(),
                            );
                          }

                          final familyDocs = subSnapshot.data?.docs ?? [];

                          if (familyDocs.isEmpty) {
                            return _buildEmptyState();
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            itemCount: familyDocs.length,
                            itemBuilder: (context, index) {
                              final familyData =
                                  familyDocs[index].data()
                                      as Map<String, dynamic>;
                              familyData['uid'] = familyDocs[index].id;
                              return _buildFamilyCard(familyData, index);
                            },
                          );
                        },
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: connectedFamilies.length,
                      itemBuilder: (context, index) {
                        final family = connectedFamilies[index];
                        return _buildFamilyCard(family, index);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.white.withOpacity(0.95)],
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Belum ada Akun Keluarga',
              style: AppTextStyles.heading3.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Belum ada anggota keluarga yang terhubung ke akun Anda',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.white.withOpacity(0.95)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.error.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: AppColors.error.withOpacity(0.1), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.error, AppColors.error.withOpacity(0.8)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Terjadi Kesalahan',
              style: AppTextStyles.heading3.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyCard(Map<String, dynamic> family, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with name and email
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        family['name']?.isNotEmpty == true
                            ? family['name']
                            : (family['email']?.split('@')[0] ??
                                  'Nama Keluarga'),
                        style: AppTextStyles.bodyLarge.copyWith(
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
                            family['email'] ?? 'email@example.com',
                            maxLines: 1,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Divider
            Divider(
              color: AppColors.textSecondary.withOpacity(0.1),
              height: 16,
            ),
            const SizedBox(height: 16),

            // Info rows
            _buildInfoRow(
              icon: Icons.phone_rounded,
              label: 'Nomor HP',
              value: family['phone'] ?? '-',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.calendar_today_rounded,
              label: 'Terhubung sejak',
              value: _formatDate(family['connectedAt']),
            ),
            const SizedBox(height: 20),

            // Remove button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showRemoveDialog(family, index),
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('Putuskan Koneksi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: AppColors.error.withOpacity(0.28),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '-';

    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is DateTime) {
        date = timestamp;
      } else {
        return '-';
      }

      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '-';
    }
  }

  void _showRemoveDialog(Map<String, dynamic> family, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppColors.error, AppColors.error.withOpacity(0.8)],
          ).createShader(bounds),
          child: const Text(
            'Hapus Koneksi',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        content: Text(
          'Apakah Anda yakin ingin memutuskan koneksi dengan ${family['name']}?',
          style: AppTextStyles.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
                await _removeConnectedFamily(index);
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
                'HAPUS',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removeConnectedFamily(int index) async {
    try {
      final families = await _familyService.getConnectedFamilies();
      if (index >= 0 && index < families.length) {
        final familyUid = families[index]['uid'];
        final userId = _auth.currentUser?.uid;

        // 1. Remove from tunanetra side
        await _familyService.removeConnectedFamily(familyUid);

        // 2. Also remove from family member's side (pairedUserUids)
        if (userId != null) {
          try {
            await _pairingService.removePairedUser(familyUid, userId);
            print('✅ Removed tunanetra from family member\'s paired users');
          } catch (e) {
            print('⚠️ Could not remove from family side: $e');
          }
        }

        // 3. Also remove from subcollection if exists
        if (userId != null) {
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('family_members')
              .doc(familyUid)
              .delete()
              .catchError((e) {
                print('Note: Could not delete from subcollection: $e');
              });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Koneksi berhasil dihapus'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghapus koneksi: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _cleanupDuplicates() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('family_members')
          .get();

      if (snapshot.docs.length <= 1) return;

      print(
        '🔍 Found ${snapshot.docs.length} family members - checking for duplicates...',
      );

      // Group by email to find duplicates
      final Map<String, List<String>> duplicateMap = {};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final email = data['email'] ?? '';

        if (email.isNotEmpty) {
          if (!duplicateMap.containsKey(email)) {
            duplicateMap[email] = [];
          }
          duplicateMap[email]!.add(doc.id);
        }
      }

      // Delete duplicates (keep the first one)
      int deletedCount = 0;
      for (final entry in duplicateMap.entries) {
        if (entry.value.length > 1) {
          print('⚠️  Found ${entry.value.length} entries for ${entry.key}');

          // Delete all except the first
          for (int i = 1; i < entry.value.length; i++) {
            await _firestore
                .collection('users')
                .doc(userId)
                .collection('family_members')
                .doc(entry.value[i])
                .delete();

            deletedCount++;
            print('   🗑️  Deleted duplicate: ${entry.value[i]}');
          }
        }
      }

      if (deletedCount > 0) {
        print('✅ Cleaned up $deletedCount duplicate entries');
      }
    } catch (e) {
      print('❌ Error cleaning up duplicates: $e');
    }
  }
}
