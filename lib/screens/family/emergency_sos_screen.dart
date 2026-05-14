import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/notification_service.dart';
import '../../utils/constants.dart';

class EmergencySosScreen extends StatelessWidget {
  final Map<String, dynamic> sosData;

  const EmergencySosScreen({super.key, required this.sosData});

  @override
  Widget build(BuildContext context) {
    debugPrint('SOS full-screen opened');

    final userName = _readString('userName') ?? 'Pengguna';
    final lat = _readString('lat');
    final lng = _readString('lng');
    final batteryLevel = _readString('batteryLevel');
    final createdAt = _readString('createdAt');

    return Scaffold(
      backgroundColor: const Color(0xFF7F1D1D),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF450A0A), Color(0xFF991B1B), Color(0xFFDC2626)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              children: [
                const Spacer(),
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 112,
                ),
                const SizedBox(height: 18),
                const Text(
                  'SOS DARURAT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$userName membutuhkan bantuan segera',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                _EmergencyInfoPanel(
                  rows: [
                    _InfoRow(label: 'Waktu', value: createdAt ?? '-'),
                    _InfoRow(label: 'Lat', value: lat ?? '-'),
                    _InfoRow(label: 'Lng', value: lng ?? '-'),
                    _InfoRow(
                      label: 'Baterai',
                      value: _batteryText(batteryLevel),
                    ),
                  ],
                ),
                const Spacer(),
                _EmergencyButton(
                  icon: Icons.location_on_rounded,
                  label: 'Lihat Lokasi',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF991B1B),
                  onPressed: () => _openMonitoring(context),
                ),
                const SizedBox(height: 10),
                _EmergencyButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy Koordinat',
                  backgroundColor: const Color(0xFFFFEDD5),
                  foregroundColor: const Color(0xFF9A3412),
                  onPressed: () => _copyCoordinates(context),
                ),
                const SizedBox(height: 10),
                _EmergencyButton(
                  icon: Icons.volume_off_rounded,
                  label: 'Senyapkan SOS',
                  backgroundColor: const Color(0xFF334155),
                  foregroundColor: Colors.white,
                  onPressed: () => _silenceAlarm(context),
                ),
                const SizedBox(height: 10),
                _EmergencyButton(
                  icon: Icons.check_circle_rounded,
                  label: 'Tandai Ditangani',
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  onPressed: () => _confirmResolve(context),
                ),
              ],
            ),
          ),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
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
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
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
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        elevation: 2,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    SystemNavigator.pop();
  }

  Future<void> _confirmResolve(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tandai SOS ditangani?'),
        content: const Text('Status SOS akan diubah menjadi ditangani.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ya, Tandai'),
          ),
        ],
      ),
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
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
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
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
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

class _EmergencyInfoPanel extends StatelessWidget {
  final List<_InfoRow> rows;

  const _EmergencyInfoPanel({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: rows
            .map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 78,
                      child: Text(
                        row.label,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});
}

class _EmergencyButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  const _EmergencyButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
