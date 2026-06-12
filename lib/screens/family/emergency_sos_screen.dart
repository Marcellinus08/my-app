import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/notification_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_dialog.dart';

class EmergencySosScreen extends StatelessWidget {
  final Map<String, dynamic> sosData;

  const EmergencySosScreen({super.key, required this.sosData});

  @override
  Widget build(BuildContext context) {
    debugPrint('SOS full-screen opened');

    final userName = _readString('userName') ?? 'Pengguna';
    final lat = _compactCoordinate(_readString('lat'));
    final lng = _compactCoordinate(_readString('lng'));
    final batteryLevel = _readString('batteryLevel');
    final smartCaneBatteryLevel = _readString('smartCaneBatteryLevel');
    final sentAtTextFuture = _sentAtText();

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: sentAtTextFuture,
          initialData: _sentAtTextFromPayload() ?? 'Memuat waktu...',
          builder: (context, snapshot) {
            final sentAtText = snapshot.data ?? 'Belum tersedia';

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _EmergencyHeader(userName: userName, sentAtText: sentAtText),
                  const SizedBox(height: 12),
                  _EmergencyInfoPanel(
                    rows: [
                      _InfoRow(label: 'Lat', value: lat ?? '-'),
                      _InfoRow(label: 'Lng', value: lng ?? '-'),
                      _InfoRow(
                        label: 'Baterai HP',
                        value: _batteryText(batteryLevel),
                      ),
                      _InfoRow(
                        label: 'Baterai Tongkat',
                        value: _batteryText(smartCaneBatteryLevel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _EmergencyActions(
                    onOpenLocation: () => _openMonitoring(context),
                    onCopyCoordinates: () => _copyCoordinates(context),
                    onSilence: () => _silenceAlarm(context),
                    onResolve: () => _confirmResolve(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String? _readString(String key) {
    final value = sosData[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  Future<String> _sentAtText() async {
    final payloadText = _sentAtTextFromPayload();
    if (payloadText != null) return payloadText;

    final sosId = _readString('sosId');
    if (sosId == null) return 'Belum tersedia';

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('sos_alerts')
          .doc(sosId)
          .get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      return _formatSentAt(data?['createdAt'] ?? data?['timestamp']);
    } catch (error) {
      debugPrint('[EmergencySosScreen] gagal mengambil waktu SOS: $error');
      return 'Belum tersedia';
    }
  }

  String? _sentAtTextFromPayload() {
    final text = _formatSentAt(sosData['createdAt'] ?? sosData['timestamp']);
    return text == 'Belum tersedia' ? null : text;
  }

  String _formatSentAt(dynamic value) {
    DateTime? dateTime;

    if (value is Timestamp) {
      dateTime = value.toDate();
    } else if (value is DateTime) {
      dateTime = value;
    } else if (value is int) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is double) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    } else if (value != null) {
      dateTime = DateTime.tryParse(value.toString());
    }

    if (dateTime == null) return 'Belum tersedia';

    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    final isToday =
        dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;

    if (isToday) return '$hour:$minute';

    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    return '$day/$month/${dateTime.year} $hour:$minute';
  }

  static String? _compactCoordinate(String? value) {
    if (value == null || value == '-') return value;
    final parsed = double.tryParse(value);
    if (parsed == null) return value;
    return parsed.toStringAsFixed(6);
  }

  static String _batteryText(String? value) {
    if (value == null || value == '-') return '-';
    return value.endsWith('%') ? value : '$value%';
  }

  Map<String, dynamic> _monitoringArgs() {
    final userId = _readString('userId') ?? '';
    final familyUid =
        _readString('familyUid') ??
        FirebaseAuth.instance.currentUser?.uid ??
        '';

    return {
      'fromSos': true,
      'userId': userId,
      'targetUid': userId,
      'familyUid': familyUid,
      'familyId': familyUid,
      'lat': _readString('lat'),
      'lng': _readString('lng'),
      'batteryLevel': _readString('batteryLevel'),
      'smartCaneBatteryLevel': _readString('smartCaneBatteryLevel'),
      'currentTripId': _readString('currentTripId'),
      'userName': _readString('userName') ?? 'Pengguna',
      'sosId': _readString('sosId'),
      'sosData': sosData,
    };
  }

  void _openMonitoring(BuildContext context) {
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.familyMonitoring,
      arguments: _monitoringArgs(),
    );
  }

  Future<void> _copyCoordinates(BuildContext context) async {
    final lat = _readString('lat');
    final lng = _readString('lng');
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Koordinat belum tersedia')));
      return;
    }

    await Clipboard.setData(ClipboardData(text: '$lat, $lng'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Koordinat berhasil disalin',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.green,
        elevation: 2,
      ),
    );
  }

  Future<void> _silenceAlarm(BuildContext context) async {
    final hasActiveSos = await _hasActiveMatchingSos();
    await NotificationService.instance.silenceSosNotification(
      sosData,
      sosResolved: !hasActiveSos,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'SOS berhasil dimatikan',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.blue,
        elevation: 2,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    SystemNavigator.pop();
  }

  Future<void> _confirmResolve(BuildContext context) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Tandai SOS ditangani?',
      description: 'Pastikan keluarga sudah merespons kondisi pengguna.',
      icon: Icons.check_circle_rounded,
      iconColor: AppColors.success,
      cancelText: 'Batal',
      confirmText: 'Ya, Tandai',
      confirmButtonColor: AppColors.primaryDark,
    );

    if (confirmed != true || !context.mounted) return;
    await _resolveSos(context);
  }

  Future<void> _resolveSos(BuildContext context) async {
    final currentFamilyUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final resolvedIds = await _resolveMatchingSosAlerts(currentFamilyUid);
    if (resolvedIds.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tidak ada SOS aktif yang ditemukan',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Colors.orange,
          elevation: 2,
        ),
      );
      return;
    }

    debugPrint('SOS resolved');
    NotificationService.instance.stopSosAlarmLoop();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'SOS ditandai sebagai ditangani',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.green,
        elevation: 2,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    SystemNavigator.pop();
  }

  Future<bool> _hasActiveMatchingSos() async {
    final firestore = FirebaseFirestore.instance;
    final directSosId = _readString('sosId');

    if (directSosId != null) {
      final snapshot = await firestore
          .collection('sos_alerts')
          .doc(directSosId)
          .get();
      final status = snapshot.data()?['status']?.toString();
      return status == 'active';
    }

    final currentFamilyUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final familyUid = _readString('familyUid') ?? currentFamilyUid;
    if (familyUid.isEmpty) return false;

    final userId = _readString('userId');
    final snapshot = await firestore
        .collection('sos_alerts')
        .where('familyUids', arrayContains: familyUid)
        .where('status', isEqualTo: 'active')
        .limit(50)
        .get();

    return snapshot.docs.any((doc) {
      if (userId == null) return true;
      return doc.data()['userId']?.toString() == userId;
    });
  }

  Future<List<String>> _resolveMatchingSosAlerts(
    String currentFamilyUid,
  ) async {
    final firestore = FirebaseFirestore.instance;
    final idsToResolve = <String>{};
    final directSosId = _readString('sosId');

    if (directSosId != null) {
      idsToResolve.add(directSosId);
    }

    final familyUid = _readString('familyUid') ?? currentFamilyUid;
    final userId = _readString('userId');

    if (familyUid.isNotEmpty) {
      final snapshot = await firestore
          .collection('sos_alerts')
          .where('familyUids', arrayContains: familyUid)
          .where('status', isEqualTo: 'active')
          .limit(50)
          .get();

      final matchingDocs = snapshot.docs.where((doc) {
        if (userId == null) return true;
        return doc.data()['userId']?.toString() == userId;
      });

      idsToResolve.addAll(matchingDocs.map((doc) => doc.id));
    }

    if (idsToResolve.isEmpty) return const [];

    final batch = firestore.batch();
    for (final sosId in idsToResolve) {
      batch.update(firestore.collection('sos_alerts').doc(sosId), {
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': currentFamilyUid,
      });
    }
    await batch.commit();

    return idsToResolve.toList();
  }
}

class _EmergencyHeader extends StatelessWidget {
  final String userName;
  final String sentAtText;

  const _EmergencyHeader({required this.userName, required this.sentAtText});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(
              color: Color(0xFFDC2626),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'SOS Darurat Aktif',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.error,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.heading3.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Membutuhkan bantuan segera',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color(0xFF991B1B),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            color: AppColors.textTertiary,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              sentAtText == 'Belum tersedia'
                                  ? 'Waktu belum tersedia'
                                  : sentAtText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyInfoPanel extends StatelessWidget {
  final List<_InfoRow> rows;

  const _EmergencyInfoPanel({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.my_location_rounded,
                  color: AppColors.primaryDark,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Informasi Lokasi',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      row.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      row.value,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyActions extends StatelessWidget {
  final VoidCallback onOpenLocation;
  final VoidCallback onCopyCoordinates;
  final VoidCallback onSilence;
  final VoidCallback onResolve;

  const _EmergencyActions({
    required this.onOpenLocation,
    required this.onCopyCoordinates,
    required this.onSilence,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tindakan Cepat',
            style: AppTextStyles.bodyLarge.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Prioritaskan pengecekan lokasi pengguna.',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _EmergencyButton(
            icon: Icons.location_on_rounded,
            label: 'Lihat Lokasi',
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            borderColor: AppColors.error,
            onPressed: onOpenLocation,
          ),
          const SizedBox(height: 9),
          _EmergencyButton(
            icon: Icons.copy_rounded,
            label: 'Salin Koordinat',
            backgroundColor: AppColors.infoLight.withValues(alpha: 0.45),
            foregroundColor: AppColors.primaryDark,
            borderColor: AppColors.primaryDark.withValues(alpha: 0.12),
            onPressed: onCopyCoordinates,
          ),
          const SizedBox(height: 12),
          Text(
            'Aksi Lanjutan',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _EmergencyButton(
                  icon: Icons.volume_off_rounded,
                  label: 'Senyapkan',
                  backgroundColor: const Color(0xFFF8FAFC),
                  foregroundColor: const Color(0xFF334155),
                  borderColor: const Color(0xFFE2E8F0),
                  onPressed: onSilence,
                  compact: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EmergencyButton(
                  icon: Icons.check_circle_rounded,
                  label: 'Ditangani',
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  borderColor: AppColors.primaryDark,
                  onPressed: onResolve,
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmergencyButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final VoidCallback onPressed;
  final bool compact;

  const _EmergencyButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: compact ? 44 : 48,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: compact ? 17 : 19, color: foregroundColor),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: foregroundColor,
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});
}
