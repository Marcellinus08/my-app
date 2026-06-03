import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/pairing_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_dialog.dart';

class FamilyConnectedTunaNetraScreen extends StatefulWidget {
  const FamilyConnectedTunaNetraScreen({super.key});

  @override
  State<FamilyConnectedTunaNetraScreen> createState() =>
      _FamilyConnectedTunaNetraScreenState();
}

class _FamilyConnectedTunaNetraScreenState
    extends State<FamilyConnectedTunaNetraScreen> {
  final PairingService _pairingService = PairingService();

  List<String> _readPairedUids(Map<String, dynamic> data) {
    final pairedUids = <String>[];

    final many = data['pairedUserUids'];
    if (many is List) {
      pairedUids.addAll(
        many.map((uid) => uid.toString()).where((uid) => uid.isNotEmpty),
      );
    }

    final single = data['pairedUserUid'];
    if (single is String &&
        single.trim().isNotEmpty &&
        !pairedUids.contains(single.trim())) {
      pairedUids.add(single.trim());
    }

    return pairedUids;
  }

  Future<List<Map<String, dynamic>>> _loadConnectedUsers(
    List<String> uids,
  ) async {
    final users = <Map<String, dynamic>>[];

    for (final uid in uids) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (doc.exists) {
        final userData = {'uid': doc.id, ...?doc.data()};
        
        // Try to get connectedAt from family_members subcollection
        try {
          final familyMemberDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('family_members')
              .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
              .get();

          if (familyMemberDoc.exists) {
            final memberData = familyMemberDoc.data() ?? {};
            // Use linkedAt from subcollection as connectedAt
            userData['connectedAt'] = memberData['linkedAt'];
          }
        } catch (e) {
          debugPrint('Error fetching family_members data: $e');
        }

        users.add(userData);
      }
    }

    return users;
  }

  @override
  Widget build(BuildContext context) {
    final familyUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: familyUid == null || familyUid.isEmpty
                  ? _buildEmptyState('Akun keluarga belum terdeteksi')
                  : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(familyUid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError) {
                          return _buildEmptyState(
                            'Gagal memuat akun terhubung',
                          );
                        }

                        final data = snapshot.data?.data() ?? {};
                        final pairedUids = _readPairedUids(data);

                        if (pairedUids.isEmpty) {
                          return _buildEmptyState(
                            'Belum ada tunanetra yang terhubung',
                          );
                        }

                        return FutureBuilder<List<Map<String, dynamic>>>(
                          future: _loadConnectedUsers(pairedUids),
                          builder: (context, usersSnapshot) {
                            if (usersSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final users = usersSnapshot.data ?? [];
                            if (users.isEmpty) {
                              return _buildEmptyState(
                                'Data tunanetra terhubung belum tersedia',
                              );
                            }

                            return ListView(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                              children: [
                                _buildFamilyHelpCard(),
                                const SizedBox(height: 16),
                                _buildSectionTitle('Pengguna Terhubung'),
                                const SizedBox(height: 12),
                                ...users.asMap().entries.map((entry) {
                                  return _buildTunaNetraCard(
                                    context,
                                    entry.value,
                                  );
                                }),
                              ],
                            );
                          },
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
                width: 42,
                height: 42,
                child: Icon(
                  Icons.arrow_back_rounded,
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
                  'Pengguna',
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
                  'Kelola pengguna yang terhubung',
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

  Widget _buildTunaNetraCard(BuildContext context, Map<String, dynamic> user) {
    final name = user['name']?.toString().trim();
    final email = user['email']?.toString().trim();
    final phone = user['phoneNumber']?.toString().trim();
    final uid = user['uid']?.toString() ?? '';
    final initial = (name?.isNotEmpty == true ? name! : 'T')[0].toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryDark.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          name?.isNotEmpty == true ? name! : 'Pengguna',
                          maxLines: 1,
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
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
                          email?.isNotEmpty == true ? email! : '-',
                          maxLines: 1,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),
          _buildInfoRow(
            icon: Icons.phone_rounded,
            label: 'Nomor Telepon',
            value: phone?.isNotEmpty == true ? phone! : '-',
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Terhubung sejak',
            value: _formatDate(user['connectedAt'] ?? user['createdAt']),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: uid.isEmpty
                  ? null
                  : () => _showDisconnectDialog(
                      context: context,
                      tunaNetraUid: uid,
                      tunaNetraName: name?.isNotEmpty == true
                          ? name!
                          : 'Pengguna',
                    ),
              icon: const Icon(Icons.link_off_rounded, size: 19),
              label: const Text('Putuskan Koneksi'),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDisconnectDialog({
    required BuildContext context,
    required String tunaNetraUid,
    required String tunaNetraName,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Putuskan Koneksi',
      description: 'Apakah Anda yakin ingin memutuskan koneksi dengan $tunaNetraName?',
      icon: Icons.link_off_rounded,
      iconColor: AppColors.warning,
      cancelText: 'Batal',
      confirmText: 'Putuskan',
      confirmButtonColor: AppColors.error,
      isDangerous: true,
    );

    if (confirmed != true) return;

    final familyUid = FirebaseAuth.instance.currentUser?.uid;
    if (familyUid == null || familyUid.isEmpty) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Akun keluarga belum terdeteksi'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      await _pairingService.removePairedUser(familyUid, tunaNetraUid);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Koneksi berhasil diputuskan'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Gagal memutuskan koneksi: ${e.toString().replaceAll('Exception: ', '')}',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primaryDark.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primaryDark, size: 19),
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
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
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

      return DateFormat('dd-MM-yyyy').format(date);
    } catch (e) {
      return '-';
    }
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
              'Pengguna terhubung dapat membantu memantau lokasi dan menerima notifikasi darurat.',
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

  Widget _buildEmptyState(String message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(24),
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
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.accessibility_new_rounded,
                color: AppColors.primaryDark,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
