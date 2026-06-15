import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/constants.dart';
import '../../services/connected_family_service.dart';
import '../../services/pairing_service.dart';
import '../../services/tunanetra_voice_command_service.dart';
import '../../utils/app_feedback.dart';
import '../../widgets/app_dialog.dart';

class ConnectedFamilyAccountsScreen extends StatefulWidget {
  const ConnectedFamilyAccountsScreen({super.key});

  @override
  State<ConnectedFamilyAccountsScreen> createState() =>
      _ConnectedFamilyAccountsScreenState();
}

class _ConnectedFamilyAccountsScreenState
    extends State<ConnectedFamilyAccountsScreen>
    with TunaNetraHomeVoiceCommandMixin {
  final ConnectedFamilyService _familyService = ConnectedFamilyService();
  final PairingService _pairingService = PairingService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _cleanupDuplicates();
    startHomeVoiceCommandListener(
      openingAnnouncement: 'Halaman akun keluarga dibuka',
      pageName: 'Akun Keluarga',
      onCommand: _handleVoiceCommand,
    );
  }

  @override
  void dispose() {
    stopHomeVoiceCommandListener();
    super.dispose();
  }

  Future<bool> _handleVoiceCommand(String command) async {
    if (TunaNetraVoiceCommands.isSettingsCommand(command)) {
      await stopHomeVoiceCommandListener();
      if (!mounted) return true;
      Navigator.pop(context);
      return true;
    }
    return false;
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
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _familyService.getConnectedFamiliesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildLoadingState();
                  }

                  if (snapshot.hasError) {
                    return _buildErrorState(
                      'Data keluarga belum dapat dimuat. Periksa koneksi lalu coba lagi.',
                    );
                  }

                  final connectedFamilies = snapshot.data ?? [];

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
                          return _buildLoadingState();
                        }

                        if (subSnapshot.hasError) {
                          return _buildErrorState(
                            'Data keluarga belum dapat dimuat. Periksa koneksi lalu coba lagi.',
                          );
                        }

                        final familyDocs = subSnapshot.data?.docs ?? [];

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          children: [
                            _buildFamilyHelpCard(),
                            const SizedBox(height: 16),
                            _buildSectionTitle('Keluarga Terhubung'),
                            const SizedBox(height: 12),
                            if (familyDocs.isEmpty)
                              _buildEmptyState()
                            else
                              ...familyDocs.asMap().entries.map((entry) {
                                final familyData =
                                    entry.value.data() as Map<String, dynamic>;
                                familyData['uid'] = entry.value.id;
                                return _buildFamilyCard(familyData, entry.key);
                              }),
                          ],
                        );
                      },
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      _buildFamilyHelpCard(),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Keluarga Terhubung'),
                      const SizedBox(height: 12),
                      ...connectedFamilies.asMap().entries.map((entry) {
                        return _buildFamilyCard(entry.value, entry.key);
                      }),
                    ],
                  );
                },
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
                  'Akun Keluarga',
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
                  'Keluarga yang terhubung',
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

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(color: AppColors.primaryDark),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 2),
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.people_outline_rounded,
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
                  'Belum ada keluarga terhubung',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Bagikan kode penghubung agar keluarga dapat terhubung.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
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

  Widget _buildErrorState(String error) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Terjadi Kesalahan',
              style: AppTextStyles.heading3.copyWith(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyCard(Map<String, dynamic> family, int index) {
    final name = _familyName(family);
    final email = _familyEmail(family);
    final phone = _readableText(family['phone'], fallback: 'Belum tersedia');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.people_alt_rounded,
                  color: AppColors.primaryDark,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AutoScaleLine(
                      text: name,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 3),
                    _AutoScaleLine(
                      text: email,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _FamilyDivider(),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.phone_rounded,
            label: 'Nomor HP',
            value: phone,
          ),
          const SizedBox(height: 9),
          _buildInfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Terhubung sejak',
            value: _formatDate(family['connectedAt']),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showRemoveDialog(family, index),
              icon: const Icon(Icons.link_off_rounded, size: 16),
              label: const Text('Putuskan Koneksi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ],
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
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: AppColors.primaryDark),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: valueColor ?? AppColors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFamilyHelpCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE8F7)),
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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.infoLight.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: AppColors.primaryDark,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Keluarga terhubung dapat membantu memantau lokasi dan menerima notifikasi darurat.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
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

  String _familyName(Map<String, dynamic> family) {
    final name = _readableText(family['name'], fallback: '');
    if (name.isNotEmpty) return name;

    final email = _familyEmail(family);
    if (email.contains('@')) return email.split('@').first;

    return 'Akun keluarga';
  }

  String _familyEmail(Map<String, dynamic> family) {
    return _readableText(family['email'], fallback: 'Email belum tersedia');
  }

  String _readableText(dynamic value, {required String fallback}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
    return text;
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

      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      return '$day-$month-${date.year}';
    } catch (e) {
      return '-';
    }
  }

  Future<void> _showRemoveDialog(Map<String, dynamic> family, int index) async {
    final name = _familyName(family);

    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Putuskan Koneksi',
      description: 'Anda yakin ingin memutuskan koneksi dengan $name?',
      icon: Icons.link_off_rounded,
      iconColor: AppColors.warning,
      cancelText: 'Batal',
      confirmText: 'Putuskan',
      confirmButtonColor: AppColors.error,
      isDangerous: true,
    );

    if (confirmed == true) {
      await _removeConnectedFamily(index);
    }
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
            debugPrint('Removed tunanetra from family member paired users');
          } catch (e) {
            debugPrint('Could not remove from family side: $e');
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
                debugPrint('Could not delete from subcollection: $e');
              });
        }

        if (mounted) {
          AppFeedback.success(
            context,
            'Koneksi berhasil dihapus.',
            announce: true,
          );
        }
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          error,
          fallback: 'Koneksi keluarga belum dapat dihapus. Silakan coba lagi.',
          announce: true,
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

      debugPrint(
        'Found ${snapshot.docs.length} family members - checking for duplicates',
      );

      // Group by email to find duplicates
      final Map<String, List<String>> duplicateMap = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
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
          debugPrint('Found ${entry.value.length} entries for ${entry.key}');

          // Delete all except the first
          for (int i = 1; i < entry.value.length; i++) {
            await _firestore
                .collection('users')
                .doc(userId)
                .collection('family_members')
                .doc(entry.value[i])
                .delete();

            deletedCount++;
            debugPrint('Deleted duplicate: ${entry.value[i]}');
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint('Cleaned up $deletedCount duplicate entries');
      }
    } catch (e) {
      debugPrint('Error cleaning up duplicates: $e');
    }
  }
}

class _FamilyDivider extends StatelessWidget {
  const _FamilyDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: Color(0xFFEFF3F7));
  }
}

class _AutoScaleLine extends StatelessWidget {
  const _AutoScaleLine({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, style: style),
      ),
    );
  }
}
