import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/pairing_service.dart';
import '../../utils/constants.dart';

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
        users.add({'uid': doc.id, ...?doc.data()});
      }
    }

    return users;
  }

  @override
  Widget build(BuildContext context) {
    final familyUid = FirebaseAuth.instance.currentUser?.uid;

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
              _buildHeader(context),
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

                              return ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  20,
                                ),
                                itemCount: users.length,
                                itemBuilder: (context, index) {
                                  return _buildTunaNetraCard(
                                    context,
                                    users[index],
                                  );
                                },
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
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
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
                    'Akun Pengguna',
                    style: AppTextStyles.heading2.copyWith(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pengguna yang terhubung',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
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
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
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
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: AppTextStyles.heading3.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
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
                          name?.isNotEmpty == true
                              ? name!
                              : 'Pengguna',
                          maxLines: 1,
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          email?.isNotEmpty == true ? email! : '-',
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
          const SizedBox(height: 18),
          Divider(color: AppColors.textSecondary.withOpacity(0.1), height: 1),
          const SizedBox(height: 18),
          _buildInfoRow(
            icon: Icons.phone_rounded,
            label: 'Nomor Telepon',
            value: phone?.isNotEmpty == true ? phone! : '-',
          ),
          const SizedBox(height: 20),
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
    );
  }

  Future<void> _showDisconnectDialog({
    required BuildContext context,
    required String tunaNetraUid,
    required String tunaNetraName,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Putuskan Koneksi'),
        content: Text(
          'Apakah Anda yakin ingin memutuskan koneksi dengan $tunaNetraName?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Putuskan'),
          ),
        ],
      ),
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
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
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(32),
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
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.accessibility_new_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
            const SizedBox(height: 18),
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
