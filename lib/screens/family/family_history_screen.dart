import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../services/analytics_service.dart';
import '../../services/navigation_history_service.dart';
import '../../services/notification_service.dart';
import '../../services/realtime_live_tracking_service.dart';
import '../../utils/app_feedback.dart';
import '../../utils/constants.dart';
import '../../widgets/app_dialog.dart';

const Color _historyPrimaryText = Color(0xFF475569);

class FamilyHistoryScreen extends StatefulWidget {
  final String targetUid;
  final String familyId;
  final Map<String, dynamic>? initialSosData;

  const FamilyHistoryScreen({
    super.key,
    required this.targetUid,
    required this.familyId,
    this.initialSosData,
  });

  @override
  State<FamilyHistoryScreen> createState() => _FamilyHistoryScreenState();
}

class _FamilyHistoryScreenState extends State<FamilyHistoryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NavigationHistoryService _navigationHistoryService =
      NavigationHistoryService();
  final Set<String> _offlineCancellationRequests = {};
  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  StateSetter? _modalSetState;
  late final Future<String?> _pairedUserUidFuture;
  bool _hasCenteredMap = false;
  bool _hasFocusedInitialSos = false;
  bool _hideInitialSosFallback = false;
  bool _hideSosCardAfterResolve = false;
  bool _isSheetExpanded = false;
  Timer? _realtimeUpdateTimer;
  Map<String, dynamic>? _latestLiveDataForSos;
  String? _lastLoggedActiveSosId;
  final Set<String> _hiddenResolvedSosIds = {};
  static const double _liveZoom = 16.5;
  static const LatLng _fallbackCenter = LatLng(-6.9147, 107.6098);
  static const double _sheetMin = 0.40;
  static const double _sheetMax = 0.75;
  static const double _sheetExpanded = 0.6;

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreenView(screenName: 'FamilyHistory');
    _sheetController.addListener(_handleSheetSize);
    _pairedUserUidFuture = getPairedUserUid();

    // Timer untuk update status offline/online dan last update setiap 1 detik
    _realtimeUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          // Trigger rebuild untuk update status dan time-based UI
        });
        _modalSetState?.call(() {
          // Trigger rebuild bottom sheet untuk status offline dan last update
        });
      }
    });
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _realtimeUpdateTimer?.cancel();
    _modalSetState = null;
    super.dispose();
  }

  void _handleSheetSize() {
    final isExpanded = _sheetController.size >= _sheetMin + 0.1;
    if (isExpanded != _isSheetExpanded) {
      setState(() {
        _isSheetExpanded = isExpanded;
      });
    }
  }

  void _toggleSheet() {
    final size = _sheetController.size;
    final target = size <= _sheetMin + 0.02 ? _sheetExpanded : _sheetMin;
    setState(() {
      _isSheetExpanded = target > _sheetMin;
    });
    _animateSheetTo(target);
  }

  void _animateSheetTo(double target) {
    if (!_sheetController.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _animateSheetTo(target);
        }
      });
      return;
    }

    _sheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  String get _currentFamilyUid {
    final familyId = widget.familyId.trim();
    if (familyId.isNotEmpty) return familyId;
    return _auth.currentUser?.uid ?? '';
  }

  Map<String, dynamic>? get _initialSosFallbackData {
    if (_hideInitialSosFallback) return null;
    final data = widget.initialSosData;
    if (data == null) return null;

    final userId = _readSosString(data['userId']) ?? widget.targetUid;
    return {
      ...data,
      'userId': userId,
      'userName': _readSosString(data['userName']) ?? 'Pengguna',
      'lat': data['lat'],
      'lng': data['lng'],
      'batteryLevel': data['batteryLevel'],
      'currentTripId': data['currentTripId'],
      'status': data['status'] ?? 'active',
    };
  }

  String get _initialSosFallbackId {
    final data = widget.initialSosData;
    if (data == null) return '';
    return _readSosString(data['sosId']) ??
        _readSosString(data['alertId']) ??
        _readSosString(data['id']) ??
        '';
  }

  String? _readSosString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  void _handleBackNavigation() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(_hideSosCardAfterResolve);
      return;
    }

    debugPrint('[FamilyHistory] Back fallback to family home');
    navigator.pushReplacementNamed(
      AppRoutes.familyHome,
      arguments: {'targetUid': widget.targetUid, 'familyId': _currentFamilyUid},
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getActiveSosStream(
    String familyUid,
  ) {
    return _firestore
        .collection('sos_alerts')
        .where('familyUids', arrayContains: familyUid)
        .snapshots();
  }

  Widget _buildCollapsedSheetCard(Map<String, dynamic>? liveData) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.radar_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Info Realtime',
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pantau kondisi pengguna',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary,
            size: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildMapPlaceholder(String label) {
    return Container(
      color: AppColors.primary.withOpacity(0.06),
      child: Center(
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
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

  Widget _buildPlaceholderStatusTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return _buildStatusTile(
      icon: icon,
      label: label,
      value: value,
      color: Colors.grey,
    );
  }

  Widget _buildStatusTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniTag(
    String label, {
    IconData? icon,
    Color color = AppColors.primary,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTextStyles.bodyLarge.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildDetailCard({
    required String title,
    required List<String> items,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '• $item',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    String label,
    String value, {
    Color color = AppColors.primary,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTunaNetraInfoCard(
    String pairedUid,
    Map<String, dynamic>? liveData,
  ) {
    return GestureDetector(
      onTap: () => _showTunaNetraInfo(pairedUid),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primary.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.person_rounded,
                color: AppColors.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Info Tuna Netra',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    liveData != null
                        ? 'Ketuk untuk melihat detail lokasi terbaru'
                        : 'Belum ada data lokasi terbaru',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  void _showTunaNetraInfo(String pairedUid) {
    // Fetch user name from Firestore
    _firestore.collection('users').doc(pairedUid).get().then((doc) {
      if (!mounted) return;
      final userName = doc.data()?['name'] as String? ?? '-';

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: AppDialogStyle.barrierColor,
        isScrollControlled: true,
        builder: (context) {
          // Use StatefulBuilder to allow realtime updates in modal
          return StatefulBuilder(
            builder: (context, setModalState) {
              _modalSetState = setModalState;
              return StreamBuilder<Map<String, dynamic>?>(
                stream: getLiveTrackingStream(pairedUid),
                builder: (context, snapshot) {
                  final liveData = snapshot.data;

                  final isNavigating =
                      liveData?['isNavigating'] as bool? ?? false;
                  final batteryLevel =
                      liveData?['batteryLevel']?.toString() ?? '-';
                  final smartCaneBatteryLevel =
                      liveData?['smartCaneBatteryLevel']?.toString() ?? '-';
                  final destinationName =
                      (liveData?['destinationName'] as String?)?.isNotEmpty ==
                          true
                      ? liveData!['destinationName'] as String
                      : '-';
                  final lat = _parseDouble(liveData?['lat']);
                  final lng = _parseDouble(liveData?['lng']);
                  final locationText = lat != null && lng != null
                      ? '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'
                      : '-';
                  final isGpsActive = isGpsActiveTracking(liveData);
                  final isNavigationActive = isGpsActive && isNavigating;
                  final gpsStatusText = buildGpsStatusText(isGpsActive);
                  final navigationText = buildNavigationText(
                    isGpsActive,
                    isNavigating,
                  );
                  final canCopyLocation =
                      isGpsActive && locationText.trim() != '-';

                  return Padding(
                    padding: MediaQuery.of(context).viewInsets,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppDialogStyle.borderRadius),
                        ),
                        border: const Border(
                          top: BorderSide(color: AppDialogStyle.borderColor),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.textPrimary.withValues(
                              alpha: 0.045,
                            ),
                            blurRadius: 14,
                            offset: const Offset(0, -5),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 48,
                              height: 5,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryDark.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.person_pin_circle_rounded,
                                  color: AppColors.primaryDark,
                                  size: 23,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Detail Pengguna',
                                      style: AppTextStyles.heading3.copyWith(
                                        color: AppColors.textPrimary,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Data aktivitas saat ini',
                                      style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (isGpsActive
                                              ? AppColors.success
                                              : AppColors.warning)
                                          .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  isGpsActive ? 'Aktif' : 'Tidak aktif',
                                  style: AppTextStyles.caption.copyWith(
                                    color: isGpsActive
                                        ? AppColors.success
                                        : AppColors.warning,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildDetailRow('Nama', userName),
                                _buildDetailDivider(),
                                _buildDetailRow('GPS', gpsStatusText),
                                _buildDetailDivider(),
                                _buildDetailRow(
                                  'Lokasi',
                                  isGpsActive ? locationText : '-',
                                  copyValue: canCopyLocation
                                      ? locationText
                                      : null,
                                ),
                                _buildDetailDivider(),
                                _buildDetailRow(
                                  'Baterai HP',
                                  isGpsActive
                                      ? (batteryLevel != '-'
                                            ? '$batteryLevel%'
                                            : '-')
                                      : '-',
                                ),
                                _buildDetailDivider(),
                                _buildDetailRow(
                                  'Baterai Tongkat',
                                  isGpsActive
                                      ? (smartCaneBatteryLevel != '-'
                                            ? '$smartCaneBatteryLevel%'
                                            : '-')
                                      : '-',
                                ),
                                _buildDetailDivider(),
                                _buildDetailRow('Navigasi', navigationText),
                                _buildDetailDivider(),
                                _buildDetailRow(
                                  'Tujuan',
                                  isNavigationActive ? destinationName : '-',
                                ),
                              ],
                            ),
                          ),
                          if (canCopyLocation) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Ketuk ikon salin pada baris lokasi untuk menyalin koordinat pengguna.',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: AppColors.primaryDark,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: const Text('Tutup'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ).whenComplete(() {
        _modalSetState = null;
      });
    });
  }

  Widget _buildDetailDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Divider(height: 1, color: Color(0xFFE2E8F0)),
    );
  }

  Future<void> _copyDetailValue(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Lokasi berhasil disalin'),
        backgroundColor: AppColors.primaryDark,
      ),
    );
  }

  Widget _buildDetailRow(String title, String value, {String? copyValue}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Text(
            title,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: title == 'Lokasi' || title == 'Tujuan' ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
              if (copyValue != null) ...[
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _copyDetailValue(copyValue),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.copy_rounded,
                        color: AppColors.primaryDark,
                        size: 17,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  double? _parseDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  Timestamp? _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value;
    if (value is num) {
      return Timestamp.fromMillisecondsSinceEpoch(value.round());
    }
    return null;
  }

  Future<String?> getPairedUserUid() async {
    final targetUid = widget.targetUid.trim();
    if (targetUid.isNotEmpty) {
      return targetUid;
    }

    final initialSosUserId = _readSosString(widget.initialSosData?['userId']);
    if (initialSosUserId != null) {
      return initialSosUserId;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) return null;

    final doc = await _firestore.collection('users').doc(currentUser.uid).get();
    if (!doc.exists) return null;

    final data = doc.data();
    if (data == null) return null;

    final pairedUid = data['pairedUserUid'];
    if (pairedUid is String && pairedUid.isNotEmpty) {
      return pairedUid;
    }

    final pairedUids = data['pairedUserUids'];
    if (pairedUids is List) {
      for (final uid in pairedUids) {
        if (uid is String && uid.trim().isNotEmpty) {
          return uid.trim();
        }
      }
    }

    return null;
  }

  Stream<Map<String, dynamic>?> getLiveTrackingStream(String tunaNetraUid) {
    return RealtimeLiveTrackingService.instance.watch(tunaNetraUid);
  }

  bool isTrackingFresh(Timestamp? updatedAt) {
    if (updatedAt == null) return false;
    final age = DateTime.now().difference(updatedAt.toDate());
    return age.inSeconds <= 60;
  }

  void _cancelNavigationIfUserOffline({
    required String userId,
    required Map<String, dynamic>? liveData,
  }) {
    final isNavigating = liveData?['isNavigating'] as bool? ?? false;
    final tripId = (liveData?['currentTripId'] as String?)?.trim() ?? '';
    final updatedAt = _parseTimestamp(liveData?['updatedAt']);
    final requestKey = userId.trim();

    if (requestKey.isEmpty ||
        updatedAt == null ||
        isTrackingFresh(updatedAt) ||
        !_offlineCancellationRequests.add(requestKey)) {
      return;
    }

    unawaited(
      _navigationHistoryService.cancelOngoingTripsBecauseUserOffline(
        userId: userId,
        preferredTripId: isNavigating ? tripId : null,
      ),
    );
  }

  bool isGpsActiveTracking(Map<String, dynamic>? liveData) {
    if (liveData == null) return false;
    final lat = _parseDouble(liveData['lat']);
    final lng = _parseDouble(liveData['lng']);
    final updatedAt = _parseTimestamp(liveData['updatedAt']);
    return lat != null && lng != null && isTrackingFresh(updatedAt);
  }

  LatLng? _parseLatLng(dynamic lat, dynamic lng) {
    final parsedLat = _parseDouble(lat);
    final parsedLng = _parseDouble(lng);
    if (parsedLat == null || parsedLng == null) return null;
    return LatLng(parsedLat, parsedLng);
  }

  List<LatLng> _parsePolyline(dynamic value) {
    if (value is! List) return [];

    return value
        .map((point) {
          if (point is Map) {
            return _parseLatLng(point['lat'], point['lng']);
          }
          return null;
        })
        .whereType<LatLng>()
        .toList();
  }

  String formatLastUpdate(Timestamp? updatedAt) {
    if (updatedAt == null) return '-';
    final duration = DateTime.now().difference(updatedAt.toDate());
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds} detik lalu';
    }
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} menit lalu';
    }
    if (duration.inHours < 24) {
      return '${duration.inHours} jam lalu';
    }
    return '${duration.inDays} hari lalu';
  }

  String formatSosSentTime(Timestamp? createdAt) {
    if (createdAt == null) return 'Dikirim: -';

    final sentAt = createdAt.toDate();
    final duration = DateTime.now().difference(sentAt);
    if (duration.inSeconds < 60) return 'Dikirim baru saja';
    if (duration.inMinutes < 60) {
      return 'Dikirim ${duration.inMinutes} menit lalu';
    }
    if (duration.inHours < 24) {
      return 'Dikirim ${duration.inHours} jam lalu';
    }

    return 'Dikirim: ${DateFormat('d MMM yyyy, HH:mm').format(sentAt)}';
  }

  String formatSosCoordinate(dynamic value) {
    final coordinate = _parseDouble(value);
    if (coordinate == null) return '-';
    return coordinate.toStringAsFixed(6);
  }

  String buildCoordinateText(dynamic lat, dynamic lng) {
    final latitude = _parseDouble(lat);
    final longitude = _parseDouble(lng);
    if (latitude == null || longitude == null) return '-';
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  Future<void> copySosCoordinate(dynamic lat, dynamic lng) async {
    final coordinateText = buildCoordinateText(lat, lng);
    if (coordinateText == '-') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Koordinat belum tersedia',
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

    await Clipboard.setData(ClipboardData(text: coordinateText));
    debugPrint('[FamilyHistory] koordinat SOS berhasil dicopy');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Koordinat berhasil disalin'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> focusToSosLocation(Map<String, dynamic> sosData) async {
    final sosLat = _parseDouble(sosData['lat']);
    final sosLng = _parseDouble(sosData['lng']);
    final liveLat = _parseDouble(_latestLiveDataForSos?['lat']);
    final liveLng = _parseDouble(_latestLiveDataForSos?['lng']);
    final target = sosLat != null && sosLng != null
        ? LatLng(sosLat, sosLng)
        : liveLat != null && liveLng != null
        ? LatLng(liveLat, liveLng)
        : null;

    debugPrint('[FamilyHistory] tombol Lihat Lokasi ditekan');

    if (target == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lokasi SOS belum tersedia'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      _mapController.move(target, _liveZoom);
    } catch (e) {
      debugPrint('[FamilyHistory] map belum siap untuk fokus SOS: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Map belum siap'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _animateSheetTo(_sheetMin);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Menampilkan lokasi SOS'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _focusInitialSosFromArgumentsIfNeeded() {
    if (_hasFocusedInitialSos) return;
    final sosData = widget.initialSosData;
    if (sosData == null) return;

    final target = _parseLatLng(sosData['lat'], sosData['lng']);
    if (target == null) return;

    _hasFocusedInitialSos = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.move(target, _liveZoom);
        _animateSheetTo(_sheetMin);
        debugPrint(
          '[FamilyHistory] auto focus SOS dari notification arguments',
        );
      } catch (e) {
        _hasFocusedInitialSos = false;
        debugPrint(
          '[FamilyHistory] gagal auto focus SOS dari notification arguments: $e',
        );
      }
    });
  }

  Future<void> resolveSosAlert(String sosId, String familyUid) async {
    try {
      final resolvedSosIds = await _resolveActiveSosAlerts(
        familyUid: familyUid,
        primarySosId: sosId,
      );

      debugPrint(
        '[FamilyHistory] SOS berhasil ditandai resolved: $resolvedSosIds',
      );
      NotificationService.instance.stopSosAlarmLoop();
      if (!mounted) return;
      setState(() {
        _hideInitialSosFallback = true;
        _hideSosCardAfterResolve = true;
        _hiddenResolvedSosIds.addAll(resolvedSosIds);
      });
      AppFeedback.success(context, 'SOS ditandai sudah ditangani.');
    } catch (error) {
      debugPrint('[FamilyHistory] error resolve SOS: $error');
      if (!mounted) return;
      AppFeedback.error(
        context,
        error,
        fallback: 'Status SOS belum dapat diperbarui. Silakan coba lagi.',
      );
    }
  }

  Future<List<String>> _resolveActiveSosAlerts({
    required String familyUid,
    required String primarySosId,
  }) async {
    if (familyUid.trim().isEmpty) {
      throw Exception('Family UID kosong');
    }

    final idsToResolve = <String>{};
    final trimmedPrimarySosId = primarySosId.trim();
    if (trimmedPrimarySosId.isNotEmpty) {
      idsToResolve.add(trimmedPrimarySosId);
    }

    final userId =
        _readSosString(widget.initialSosData?['userId']) ?? widget.targetUid;
    final snapshot = await _firestore
        .collection('sos_alerts')
        .where('familyUids', arrayContains: familyUid)
        .limit(50)
        .get();

    final activeDocs =
        snapshot.docs.where((doc) {
          final data = doc.data();
          final isActive = data['status'] == 'active';
          final docUserId = _readSosString(data['userId']);
          final sameUser = userId.trim().isEmpty || docUserId == userId.trim();
          return isActive && sameUser;
        }).toList()..sort((a, b) {
          final aCreatedAt = _parseTimestamp(a.data()['createdAt']);
          final bCreatedAt = _parseTimestamp(b.data()['createdAt']);
          final aMillis = aCreatedAt?.toDate().millisecondsSinceEpoch ?? 0;
          final bMillis = bCreatedAt?.toDate().millisecondsSinceEpoch ?? 0;
          return bMillis.compareTo(aMillis);
        });

    idsToResolve.addAll(activeDocs.map((doc) => doc.id));

    if (idsToResolve.isEmpty) {
      throw Exception('SOS aktif tidak ditemukan');
    }

    final batch = _firestore.batch();
    for (final sosId in idsToResolve) {
      final docRef = _firestore.collection('sos_alerts').doc(sosId);
      batch.update(docRef, {
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': familyUid,
      });
    }
    await batch.commit();

    return idsToResolve.toList();
  }

  Future<void> _confirmResolveSosAlert(String sosId) async {
    final familyUid = _currentFamilyUid;
    if (familyUid.isEmpty) {
      debugPrint('[FamilyHistory] resolve SOS failed: familyUid empty');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Akun keluarga tidak ditemukan'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

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

    if (confirmed == true) {
      await resolveSosAlert(sosId, familyUid);
    }
  }

  String buildGpsStatusText(bool isGpsActive) {
    return isGpsActive ? 'Aktif' : 'Tidak aktif';
  }

  String buildNavigationText(bool isGpsActive, bool isNavigating) {
    if (!isGpsActive) {
      return '-';
    }
    return isNavigating ? 'Aktif' : 'Tidak aktif';
  }

  Widget _buildMainMap(Map<String, dynamic>? liveData) {
    final lat = _parseDouble(liveData?['lat']);
    final lng = _parseDouble(liveData?['lng']);
    final heading = _parseDouble(liveData?['heading']) ?? 0.0;
    final isGpsActive = isGpsActiveTracking(liveData);
    final hasLiveLocation = lat != null && lng != null && isGpsActive;
    final initialSosPoint = _parseLatLng(
      widget.initialSosData?['lat'],
      widget.initialSosData?['lng'],
    );
    final hasSosLocation = initialSosPoint != null;
    final hasLocation = hasLiveLocation || hasSosLocation;
    final center = hasLiveLocation
        ? LatLng(lat, lng)
        : initialSosPoint ?? _fallbackCenter;

    if (!_hasCenteredMap && hasLocation) {
      _hasCenteredMap = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(center, _liveZoom);
        }
      });
    }

    final isNavigating = liveData?['isNavigating'] as bool? ?? false;
    final currentTripId = liveData?['currentTripId'] as String?;

    if (!isNavigating || currentTripId == null || currentTripId.isEmpty) {
      return _buildMainMapContent(
        center: center,
        heading: heading,
        hasLocation: hasLocation,
        isGpsActive: isGpsActive || hasSosLocation,
        canRecenterOnUser: hasLiveLocation,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('navigation_history')
          .doc(currentTripId)
          .snapshots(),
      builder: (context, snapshot) {
        final tripData = snapshot.data?.data();
        final remainingRoute = _parsePolyline(
          tripData?['remainingRoutePolyline'],
        );
        final routePolyline = _parsePolyline(tripData?['routePolyline']);
        final activeRoute = remainingRoute.isNotEmpty
            ? remainingRoute
            : routePolyline;
        final destination = _parseLatLng(
          tripData?['destinationLat'],
          tripData?['destinationLng'],
        );

        return _buildMainMapContent(
          center: hasLocation || activeRoute.isEmpty
              ? center
              : activeRoute.first,
          heading: heading,
          hasLocation: hasLocation,
          isGpsActive: isGpsActive || hasSosLocation,
          canRecenterOnUser: hasLiveLocation,
          activeRoute: activeRoute,
          destination: destination,
        );
      },
    );
  }

  Widget _buildMainMapContent({
    required LatLng center,
    required double heading,
    required bool hasLocation,
    required bool isGpsActive,
    required bool canRecenterOnUser,
    List<LatLng> activeRoute = const [],
    LatLng? destination,
  }) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: _liveZoom,
            minZoom: 5.0,
            maxZoom: 18.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              enableMultiFingerGestureRace: true,
              pinchZoomThreshold: 0.1,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.my_app',
              maxZoom: 18.0,
            ),
            if (activeRoute.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: activeRoute,
                    color: AppColors.primary,
                    strokeWidth: 5,
                    borderColor: Colors.white,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (destination != null)
                  Marker(
                    point: destination,
                    width: 48,
                    height: 48,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withOpacity(0.9),
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(
                        Icons.flag_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                if (hasLocation)
                  Marker(
                    point: center,
                    width: 56,
                    height: 56,
                    child: Transform.rotate(
                      angle: heading * (math.pi / 180),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryDark,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryDark.withValues(
                                alpha: 0.22,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.navigation_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (canRecenterOnUser && !_isSheetExpanded)
          Positioned(
            right: 20,
            bottom: 108,
            child: Semantics(
              button: true,
              label: 'Kembali ke posisi pengguna',
              hint: 'Memusatkan peta pada lokasi pengguna saat ini',
              child: Tooltip(
                message: 'Posisi pengguna',
                child: Material(
                  color: Colors.white,
                  elevation: 4,
                  shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      try {
                        _mapController.move(center, _liveZoom);
                      } catch (error) {
                        debugPrint(
                          '[FamilyHistory] gagal memusatkan peta: $error',
                        );
                      }
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Icon(
                        Icons.my_location_rounded,
                        color: AppColors.primaryDark,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (!hasLocation)
          Positioned.fill(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isGpsActive
                          ? Icons.location_off_rounded
                          : Icons.wifi_off_rounded,
                      color: AppColors.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isGpsActive
                          ? 'Belum ada data lokasi'
                          : 'Pengguna tidak aktif',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget buildSosEmergencyCard({
    required String sosId,
    required Map<String, dynamic> sosData,
  }) {
    final createdAt = _parseTimestamp(sosData['createdAt']);
    final lat = formatSosCoordinate(sosData['lat']);
    final lng = formatSosCoordinate(sosData['lng']);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFDC2626).withOpacity(0.2),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFDC2626).withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: Red alert status bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: const BoxDecoration(
                color: Color(0xFFDC2626),
                borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SOS Aktif',
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatSosSentTime(createdAt),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Body: Coordinates and actions
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Coordinates label
                  Text(
                    'Koordinat pengguna',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Coordinates values (two rows)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lat: $lat',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color(0xFF1E293B),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Lng: $lng',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color(0xFF1E293B),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Action buttons
                  Row(
                    children: [
                      // Copy button
                      Expanded(
                        child: _buildSosActionButton(
                          icon: Icons.content_copy_rounded,
                          label: 'Salin Koordinat',
                          foregroundColor: const Color(0xFFDC2626),
                          backgroundColor: const Color(0xFFFEE2E2),
                          borderColor: const Color(0xFFDC2626).withOpacity(0.2),
                          onPressed: () =>
                              copySosCoordinate(sosData['lat'], sosData['lng']),
                        ),
                      ),
                      const SizedBox(width: 9),
                      // Mark resolved button
                      Expanded(
                        child: _buildSosActionButton(
                          icon: Icons.check_rounded,
                          label: 'Tandai Ditangani',
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xFFDC2626),
                          onPressed: () => _confirmResolveSosAlert(sosId),
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
    );
  }

  Widget _buildSosActionButton({
    required IconData icon,
    required String label,
    required Color foregroundColor,
    required Color backgroundColor,
    required VoidCallback onPressed,
    Color? borderColor,
  }) {
    return SizedBox(
      height: 38,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: borderColor ?? Colors.transparent,
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLivePanelContent(Map<String, dynamic>? liveData) {
    final destinationName =
        (liveData?['destinationName'] as String?)?.isNotEmpty == true
        ? liveData!['destinationName'] as String
        : '-';
    final battery = liveData?['batteryLevel'] != null
        ? '${liveData!['batteryLevel']}%'
        : '-';
    final lat = _parseDouble(liveData?['lat']);
    final lng = _parseDouble(liveData?['lng']);
    final locationText = lat != null && lng != null
        ? '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'
        : '-';
    final headingValue = _parseDouble(liveData?['heading']) ?? 0.0;
    final isNavigating = liveData?['isNavigating'] as bool? ?? false;
    final updatedAt = _parseTimestamp(liveData?['updatedAt']);
    final isGpsActive = isGpsActiveTracking(liveData);
    final isNavigationActive = isGpsActive && isNavigating;

    // Prepare display values based on online status
    final displayLocation = isGpsActive ? locationText : '-';
    final displayLat = isGpsActive && lat != null
        ? lat.toStringAsFixed(6)
        : '-';
    final displayLng = isGpsActive && lng != null
        ? lng.toStringAsFixed(6)
        : '-';
    final displayDestination = isNavigationActive ? destinationName : '-';
    final navigationText = buildNavigationText(isGpsActive, isNavigating);
    final gpsStatusText = buildGpsStatusText(isGpsActive);
    final displayHeading = isNavigationActive
        ? headingValue.toStringAsFixed(0)
        : '-';
    final displayBattery = isGpsActive ? battery : '-';
    final displayLastUpdate = isNavigationActive
        ? formatLastUpdate(updatedAt)
        : '-';

    return [
      _buildSectionTitle('🎯 Tujuan realtime monitoring'),
      const SizedBox(height: 10),
      Text(
        isGpsActive
            ? 'Tahu posisi sekarang • Tahu kondisi user • Bisa respon cepat kalau ada masalah'
            : 'Pengguna sedang tidak aktif. Data tidak tersedia.',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textSecondary,
          height: 1.6,
        ),
      ),
      const SizedBox(height: 18),
      _buildDetailCard(
        title: 'Data realtime yang WAJIB ada',
        items: [
          'Lokasi realtime: $displayLocation',
          'Latitude: $displayLat',
          'Longitude: $displayLng',
        ],
      ),
      const SizedBox(height: 18),
      _buildDetailCard(
        title: 'Navigasi',
        items: [
          'Menuju: $displayDestination',
          'Navigasi: $navigationText',
          'GPS: $gpsStatusText',
        ],
      ),
      const SizedBox(height: 18),
      _buildDetailCard(
        title: 'Status pergerakan',
        items: ['Arah: $displayHeading°'],
      ),
      const SizedBox(height: 18),
      if (isGpsActive)
        Row(
          children: [
            Expanded(
              child: _buildMiniTag(
                'GPS Live 🟢',
                icon: Icons.gps_fixed,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMiniTag(
                'Predicted ⚠️',
                icon: Icons.verified_user,
                color: Colors.amber,
              ),
            ),
          ],
        ),
      if (isGpsActive) const SizedBox(height: 18),
      _buildDetailCard(
        title: 'Info tambahan',
        items: [
          'Baterai: $displayBattery',
          'Tujuan: $displayDestination',
          'Last update: $displayLastUpdate',
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackNavigation();
        }
      },
      child: Scaffold(
        body: FutureBuilder<String?>(
          future: _pairedUserUidFuture,
          builder: (context, pairedSnapshot) {
            final pairedUid = pairedSnapshot.data;
            if (pairedSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (pairedSnapshot.hasError ||
                pairedUid == null ||
                pairedUid.isEmpty) {
              return Stack(
                children: [
                  Positioned.fill(child: _buildMainMap(null)),
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.textTertiary.withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          'Belum ada data lokasi',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return StreamBuilder<Map<String, dynamic>?>(
              stream: getLiveTrackingStream(pairedUid),
              builder: (context, snapshot) {
                final liveData = snapshot.data;
                _cancelNavigationIfUserOffline(
                  userId: pairedUid,
                  liveData: liveData,
                );
                _latestLiveDataForSos = liveData;
                _focusInitialSosFromArgumentsIfNeeded();

                return Stack(
                  children: [
                    Positioned.fill(child: _buildMainMap(liveData)),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        bottom: false,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.045,
                                ),
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
                                  onTap: _handleBackNavigation,
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
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Lihat Detail Lokasi',
                                      style: AppTextStyles.heading3.copyWith(
                                        color: AppColors.textPrimary,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Pantau aktivitas pengguna',
                                      style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: _sosCardTopOffset(context),
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        child:
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: getActiveSosStream(_currentFamilyUid),
                              builder: (context, sosSnapshot) {
                                if (_hideSosCardAfterResolve) {
                                  return const SizedBox.shrink();
                                }

                                if (sosSnapshot.hasError) {
                                  debugPrint(
                                    '[FamilyHistory] active SOS listener error: '
                                    '${sosSnapshot.error}',
                                  );
                                }

                                final activeDocs =
                                    (sosSnapshot.data?.docs ?? []).where((doc) {
                                      return doc.data()['status'] == 'active' &&
                                          !_hiddenResolvedSosIds.contains(
                                            doc.id,
                                          );
                                    }).toList()..sort((a, b) {
                                      final aCreatedAt = _parseTimestamp(
                                        a.data()['createdAt'],
                                      );
                                      final bCreatedAt = _parseTimestamp(
                                        b.data()['createdAt'],
                                      );
                                      final aMillis =
                                          aCreatedAt
                                              ?.toDate()
                                              .millisecondsSinceEpoch ??
                                          0;
                                      final bMillis =
                                          bCreatedAt
                                              ?.toDate()
                                              .millisecondsSinceEpoch ??
                                          0;
                                      return bMillis.compareTo(aMillis);
                                    });

                                if (activeDocs.isEmpty) {
                                  final fallbackData = _initialSosFallbackData;
                                  if (fallbackData != null) {
                                    debugPrint(
                                      '[FamilyHistory] menampilkan SOS dari '
                                      'notification arguments',
                                    );
                                    return buildSosEmergencyCard(
                                      sosId: _initialSosFallbackId,
                                      sosData: fallbackData,
                                    );
                                  }
                                  return const SizedBox.shrink();
                                }

                                final sosDoc = activeDocs.first;
                                if (_lastLoggedActiveSosId != sosDoc.id) {
                                  _lastLoggedActiveSosId = sosDoc.id;
                                  debugPrint(
                                    '[FamilyHistory] active SOS ditemukan: '
                                    '${sosDoc.id}',
                                  );
                                }

                                return buildSosEmergencyCard(
                                  sosId: sosDoc.id,
                                  sosData: sosDoc.data(),
                                );
                              },
                            ),
                      ),
                    ),
                    IgnorePointer(
                      ignoring: !_isSheetExpanded,
                      child: DraggableScrollableSheet(
                        controller: _sheetController,
                        minChildSize: _sheetMin,
                        maxChildSize: _sheetMax,
                        initialChildSize: _sheetMin,
                        builder: (context, controller) {
                          final isExpanded = _isSheetExpanded;
                          return Container(
                            decoration: BoxDecoration(
                              color: isExpanded
                                  ? AppColors.background
                                  : Colors.transparent,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                              boxShadow: isExpanded
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primary.withOpacity(
                                          0.18,
                                        ),
                                        blurRadius: 24,
                                        offset: const Offset(0, -6),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: isExpanded
                                ? Stack(
                                    children: [
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        right: 0,
                                        bottom: 130,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            20,
                                            12,
                                            20,
                                            0,
                                          ),
                                          child: ListView(
                                            controller: controller,
                                            padding: const EdgeInsets.only(
                                              bottom: 24,
                                            ),
                                            children: [
                                              GestureDetector(
                                                onTap: _toggleSheet,
                                                child: Center(
                                                  child: Container(
                                                    width: 48,
                                                    height: 5,
                                                    decoration: BoxDecoration(
                                                      color: AppColors
                                                          .textTertiary
                                                          .withOpacity(0.4),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 14),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'Detail Lokasi',
                                                      style: AppTextStyles
                                                          .bodyLarge
                                                          .copyWith(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: AppColors
                                                                .textPrimary,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 14),
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 36,
                                                    height: 36,
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary
                                                          .withOpacity(0.12),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.radar_rounded,
                                                      color: AppColors.primary,
                                                      size: 20,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Info Realtime',
                                                          style: AppTextStyles
                                                              .bodyMedium
                                                              .copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          'Status aktivitas dan koneksi pengguna',
                                                          style: AppTextStyles
                                                              .bodySmall
                                                              .copyWith(
                                                                color: AppColors
                                                                    .textSecondary,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              _buildTunaNetraInfoCard(
                                                pairedUid,
                                                liveData,
                                              ),
                                              const SizedBox(height: 16),
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  border: Border.all(
                                                    color: AppColors.primary
                                                        .withOpacity(0.12),
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppColors.primary
                                                          .withOpacity(0.08),
                                                      blurRadius: 16,
                                                      offset: const Offset(
                                                        0,
                                                        8,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: Column(
                                                  children:
                                                      _buildLivePanelContent(
                                                        liveData,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: 20,
                                        right: 20,
                                        bottom: 12,
                                        child: _buildCollapsedSheetCard(
                                          liveData,
                                        ),
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          );
                        },
                      ),
                    ),
                    if (!_isSheetExpanded)
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 16,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showTunaNetraInfo(pairedUid),
                          child: _buildCollapsedSheetCard(liveData),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  double _sosCardTopOffset(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) return 88;
    return 125;
  }
}

class FamilyHistoryDetailScreen extends StatefulWidget {
  final String targetUid;
  final String familyId;

  const FamilyHistoryDetailScreen({
    super.key,
    required this.targetUid,
    required this.familyId,
  });

  @override
  State<FamilyHistoryDetailScreen> createState() =>
      _FamilyHistoryDetailScreenState();
}

class _FamilyHistoryDetailScreenState extends State<FamilyHistoryDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final Future<String?> _pairedUserUidFuture;

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreenView(screenName: 'FamilyHistoryDetail');
    _pairedUserUidFuture = getPairedUserUid();
  }

  Future<String?> getPairedUserUid() async {
    try {
      if (widget.targetUid.trim().isNotEmpty) {
        debugPrint(
          '[FAMILY_HISTORY] Using targetUid for navigation history: ${widget.targetUid}',
        );
        return widget.targetUid.trim();
      }

      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;

      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final data = userDoc.data();
      if (data == null) return null;

      final pairedUid = data['pairedUserUid'];
      if (pairedUid is String && pairedUid.trim().isNotEmpty) {
        return pairedUid.trim();
      }

      final pairedUids = data['pairedUserUids'];
      if (pairedUids is List && pairedUids.isNotEmpty) {
        for (final uid in pairedUids) {
          if (uid is String && uid.trim().isNotEmpty) {
            return uid.trim();
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('[FAMILY_HISTORY] Failed to load pairedUserUid: $e');
      return null;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getNavigationHistoryStream(
    String pairedUserUid,
  ) {
    debugPrint(
      '[FAMILY_HISTORY] Listening navigation_history for userId: $pairedUserUid',
    );
    return _firestore
        .collection('navigation_history')
        .where('userId', isEqualTo: pairedUserUid)
        .snapshots();
  }

  String formatTripDate(Timestamp? timestamp) {
    if (timestamp == null) return '-';
    return DateFormat('dd MMM yyyy').format(timestamp.toDate());
  }

  String formatTripTime(Timestamp? timestamp) {
    if (timestamp == null) return '-';
    return DateFormat('HH:mm').format(timestamp.toDate());
  }

  String formatDuration(dynamic durationSeconds) {
    final seconds = _toInt(durationSeconds);
    if (seconds == null) return '-';

    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    if (minutes < 60) return '$minutes menit';

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) return '$hours jam';
    return '$hours jam $remainingMinutes menit';
  }

  String formatCardDuration(dynamic durationSeconds) {
    final seconds = _toInt(durationSeconds);
    if (seconds == null) return '-';
    if (seconds >= 0 && seconds < 60) return '1 menit';
    return formatDuration(durationSeconds);
  }

  String formatDistance(dynamic totalDistanceMeters) {
    final meters = _toDouble(totalDistanceMeters);
    if (meters == null) return '-';
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String formatStatusText(String? status) {
    switch (status) {
      case 'completed':
        return 'Selesai';
      case 'cancelled':
      case 'canceled':
      case 'batal':
        return 'Dibatalkan';
      case 'ongoing':
        return 'Berjalan';
      default:
        return 'Berjalan';
    }
  }

  Color getStatusColor(String? status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
      case 'canceled':
      case 'batal':
        return AppColors.error;
      case 'ongoing':
        return AppColors.primary;
      default:
        return Colors.grey;
    }
  }

  Color getStatusBackgroundColor(String? status) {
    switch (status) {
      case 'completed':
        return AppColors.successLight;
      case 'cancelled':
      case 'canceled':
      case 'batal':
        return AppColors.errorLight;
      case 'ongoing':
        return AppColors.infoLight;
      default:
        return AppColors.surfaceLight;
    }
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _safeText(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  bool _shouldShowTripEvent(String type) {
    return type != 'gps_lost' &&
        type != 'gps_recovered' &&
        type != 'prediction_started' &&
        type != 'prediction_stopped';
  }

  Stream<int> getVisibleTripEventCountStream(String tripId) {
    return _firestore
        .collection('navigation_history')
        .doc(tripId)
        .collection('events')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.where((doc) {
            final type = doc.data()['type'];
            return type is String && _shouldShowTripEvent(type);
          }).length;
        });
  }

  Widget _buildHistoryContent() {
    return FutureBuilder<String?>(
      future: _pairedUserUidFuture,
      builder: (context, pairedSnapshot) {
        if (pairedSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final pairedUserUid = pairedSnapshot.data;
        if (pairedUserUid == null || pairedUserUid.isEmpty) {
          return _buildEmptyState(
            icon: Icons.link_off_rounded,
            title: 'Belum ada pengguna tuna netra terhubung',
            subtitle: 'Hubungkan akun terlebih dahulu untuk melihat riwayat',
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: getNavigationHistoryStream(pairedUserUid),
          builder: (context, historySnapshot) {
            if (historySnapshot.hasError) {
              debugPrint(
                '[FAMILY_HISTORY] History stream error: ${historySnapshot.error}',
              );
              return _buildEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Riwayat belum dapat dimuat',
                subtitle: 'Periksa koneksi atau indeks Firestore',
              );
            }

            if (historySnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = [...?historySnapshot.data?.docs]
              ..sort((a, b) {
                final aStartTime = a.data()['startTime'];
                final bStartTime = b.data()['startTime'];
                final aMillis = aStartTime is Timestamp
                    ? aStartTime.millisecondsSinceEpoch
                    : 0;
                final bMillis = bStartTime is Timestamp
                    ? bStartTime.millisecondsSinceEpoch
                    : 0;
                return bMillis.compareTo(aMillis);
              });
            debugPrint(
              '[FAMILY_HISTORY] Loaded ${docs.length} navigation_history docs',
            );

            if (docs.isEmpty) {
              return _buildEmptyState(
                icon: Icons.route_rounded,
                title: 'Belum ada riwayat perjalanan',
                subtitle: 'Riwayat navigasi tuna netra akan muncul di sini',
              );
            }

            final items = docs
                .map((doc) => NavigationHistoryItem.fromDoc(doc))
                .toList();

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
              itemCount: items.length,
              itemBuilder: (context, index) => _buildTripCard(items[index]),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD9E8F8)),
              ),
              child: Icon(icon, color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: AppTextStyles.heading2.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripCard(NavigationHistoryItem item) {
    final statusColor = getStatusColor(item.status);
    final durationText = formatCardDuration(item.durationSeconds);
    final startTimeText = formatTripTime(item.startTime);
    final endTimeText = formatTripTime(item.endTime);
    final originName = _safeText(item.originName, 'Lokasi awal');
    final destinationName = _safeText(item.destinationName, 'Tujuan');
    final distanceText = formatDistance(item.totalDistanceMeters);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NavigationHistoryDetailScreen(tripId: item.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.045),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          destinationName,
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 15,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${formatTripDate(item.startTime)} | $startTimeText - $endTimeText',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 112),
                    child: Text(
                      formatStatusText(item.status),
                      style: AppTextStyles.caption.copyWith(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE8EEF5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLocationInfo(
                      icon: Icons.radio_button_checked,
                      color: AppColors.success,
                      label: 'Dari',
                      value: originName,
                      showConnector: true,
                    ),
                    const SizedBox(height: 4),
                    _buildLocationInfo(
                      icon: Icons.location_on_rounded,
                      color: AppColors.error,
                      label: 'Ke',
                      value: destinationName,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStat(
                      icon: Icons.straighten_rounded,
                      label: distanceText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMiniStat(
                      icon: Icons.timer_outlined,
                      label: durationText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StreamBuilder<int>(
                      stream: getVisibleTripEventCountStream(item.id),
                      builder: (context, snapshot) {
                        final eventCount = snapshot.data ?? 0;
                        return _buildMiniStat(
                          icon: Icons.warning_amber_rounded,
                          label:
                              snapshot.connectionState ==
                                  ConnectionState.waiting
                              ? '-'
                              : '$eventCount aksi',
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationInfo({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    bool showConnector = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            _buildPointIcon(icon: icon, color: color),
            if (showConnector)
              Container(
                width: 2,
                height: 24,
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: AppTextStyles.bodySmall.copyWith(
                    color: _historyPrimaryText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(text: value),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPointIcon({required IconData icon, required Color color}) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 14),
    );
  }

  Widget _buildMiniStat({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 1),
          Icon(icon, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      body: Container(
        color: const Color(0xFFF7FAFD),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textPrimary.withOpacity(0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFFE5EAF0), width: 1),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Riwayat Perjalanan',
                            style: AppTextStyles.heading2.copyWith(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Pantau aktivitas & keamanan',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(child: _buildHistoryContent()),
            ],
          ),
        ),
      ),
    );
  }
}

class NavigationHistoryDetailScreen extends StatefulWidget {
  final String tripId;

  const NavigationHistoryDetailScreen({super.key, required this.tripId});

  @override
  State<NavigationHistoryDetailScreen> createState() =>
      _NavigationHistoryDetailScreenState();
}

class _NavigationHistoryDetailScreenState
    extends State<NavigationHistoryDetailScreen> {
  final MapController _historyMapController = MapController();
  bool _isHistoryMapReady = false;
  String? _lastFocusedRouteSignature;

  @override
  void dispose() {
    _historyMapController.dispose();
    super.dispose();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _tripStream {
    return FirebaseFirestore.instance
        .collection('navigation_history')
        .doc(widget.tripId)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _routePointsStream {
    return FirebaseFirestore.instance
        .collection('navigation_history')
        .doc(widget.tripId)
        .collection('route_points')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _eventsStream {
    return FirebaseFirestore.instance
        .collection('navigation_history')
        .doc(widget.tripId)
        .collection('events')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  String formatTripDate(Timestamp? timestamp) {
    if (timestamp == null) return '-';
    return DateFormat('dd MMMM yyyy').format(timestamp.toDate());
  }

  String formatTripTime(Timestamp? timestamp) {
    if (timestamp == null) return '-';
    return DateFormat('HH:mm').format(timestamp.toDate());
  }

  String formatDuration(dynamic durationSeconds) {
    final seconds = _toInt(durationSeconds);
    if (seconds == null) return '-';

    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    if (minutes < 60) return '$minutes menit';

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) return '$hours jam';
    return '$hours jam $remainingMinutes menit';
  }

  String formatDisplayDuration(dynamic durationSeconds) {
    final seconds = _toInt(durationSeconds);
    if (seconds == null) return '-';
    if (seconds >= 0 && seconds < 60) return '< 1 menit';
    return formatDuration(durationSeconds);
  }

  String formatDistance(dynamic totalDistanceMeters) {
    final meters = _toDouble(totalDistanceMeters);
    if (meters == null) return '-';
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String formatStatusText(String? status) {
    switch (status) {
      case 'completed':
        return 'Selesai';
      case 'cancelled':
      case 'canceled':
      case 'batal':
        return 'Dibatalkan';
      case 'ongoing':
        return 'Sedang berjalan';
      default:
        return 'Sedang berjalan';
    }
  }

  String formatCoordinate(dynamic lat, dynamic lng) {
    final latitude = _toDouble(lat);
    final longitude = _toDouble(lng);
    if (latitude == null || longitude == null) return '-';
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  String formatEventTime(Timestamp? timestamp) {
    if (timestamp == null) return '-';
    return DateFormat('HH:mm').format(timestamp.toDate());
  }

  IconData getEventIcon(String type) {
    switch (type) {
      case 'navigation_started':
        return Icons.play_arrow_rounded;
      case 'navigation_completed':
        return Icons.check_circle_rounded;
      case 'navigation_cancelled':
        return Icons.cancel_rounded;
      case 'arrived':
        return Icons.flag_rounded;
      case 'off_route':
        return Icons.warning_rounded;
      case 'back_to_route':
        return Icons.check_circle_outline_rounded;
      case 'sos_pressed':
        return Icons.warning_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Color getEventColor(String type) {
    switch (type) {
      case 'navigation_started':
        return AppColors.primary;
      case 'navigation_completed':
      case 'arrived':
      case 'back_to_route':
        return AppColors.success;
      case 'navigation_cancelled':
      case 'sos_pressed':
        return AppColors.error;
      case 'off_route':
        return AppColors.warning;
      default:
        return Colors.grey;
    }
  }

  bool _shouldShowTripEvent(String type) {
    return type != 'gps_lost' &&
        type != 'gps_recovered' &&
        type != 'prediction_started' &&
        type != 'prediction_stopped';
  }

  bool shouldShowTripEvent(String type) {
    return _shouldShowTripEvent(type);
  }

  LatLng? parseLatLng(dynamic lat, dynamic lng) {
    final latitude = _toDouble(lat);
    final longitude = _toDouble(lng);
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude, longitude);
  }

  List<LatLng> buildRoutePolyline(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .map((doc) {
          final data = doc.data();
          return parseLatLng(data['lat'], data['lng']);
        })
        .whereType<LatLng>()
        .toList();
  }

  LatLngBounds boundsFromLatLngList(List<LatLng> points) {
    if (points.isEmpty) {
      const defaultPoint = LatLng(-6.9175, 107.6191);
      return LatLngBounds(defaultPoint, defaultPoint);
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final southWest = LatLng(minLat, minLng);
    final northEast = LatLng(maxLat, maxLng);
    return LatLngBounds(southWest, northEast);
  }

  Set<Marker> buildHistoryMarkers({
    required List<LatLng> routePoints,
    required Map<String, dynamic> tripData,
    required String status,
  }) {
    final markers = <Marker>{};
    final isCompleted = status.toLowerCase() == 'completed';
    var destinationMerged = false;
    final destination = parseLatLng(
      tripData['destinationLat'],
      tripData['destinationLng'],
    );

    if (routePoints.length == 1) {
      final point = routePoints.first;
      final distanceToDestination = destination == null
          ? double.infinity
          : const Distance().as(LengthUnit.Meter, point, destination);
      destinationMerged =
          isCompleted && destination != null && distanceToDestination <= 20;

      markers.add(
        destinationMerged
            ? _buildCombinedHistoryMarker(
                point: destination,
                icons: const [
                  (Icons.location_on, Colors.red),
                  (Icons.flag_rounded, Colors.deepPurple),
                ],
                label: 'Sampai Tujuan',
                width: 142,
              )
            : _buildHistoryMarker(
                point: point,
                icon: Icons.location_on,
                color: status == 'ongoing' ? AppColors.primary : Colors.green,
                label: status == 'ongoing' ? 'Posisi terakhir' : 'Titik rute',
              ),
      );
    } else if (routePoints.length >= 2) {
      final start = routePoints.first;
      final end = routePoints.last;
      final startEndDistance = const Distance().as(
        LengthUnit.Meter,
        start,
        end,
      );
      final endDestinationDistance = destination == null
          ? double.infinity
          : const Distance().as(LengthUnit.Meter, end, destination);
      final isEndAtDestination =
          isCompleted && destination != null && endDestinationDistance <= 20;
      final isStartEndOverlapping =
          !isCompleted && status != 'ongoing' && startEndDistance <= 20;

      if (isEndAtDestination && startEndDistance <= 20) {
        destinationMerged = true;
        markers.add(
          _buildCombinedHistoryMarker(
            point: destination,
            icons: const [
              (Icons.radio_button_checked, Colors.green),
              (Icons.flag_rounded, Colors.deepPurple),
            ],
            label: 'Awal & Sampai Tujuan',
            width: 172,
          ),
        );
      } else if (isEndAtDestination) {
        destinationMerged = true;
        markers.add(
          _buildHistoryMarker(
            point: start,
            icon: Icons.radio_button_checked,
            color: Colors.green,
            label: 'Awal',
          ),
        );
        markers.add(
          _buildCombinedHistoryMarker(
            point: destination,
            icons: const [
              (Icons.location_on, Colors.red),
              (Icons.flag_rounded, Colors.deepPurple),
            ],
            label: 'Sampai Tujuan',
            width: 142,
          ),
        );
      } else if (isStartEndOverlapping) {
        markers.add(
          _buildOverlappingStartEndMarker(
            point: end,
            distanceMeters: startEndDistance,
          ),
        );
      } else {
        markers.add(
          _buildHistoryMarker(
            point: start,
            icon: Icons.radio_button_checked,
            color: Colors.green,
            label: 'Awal',
          ),
        );

        markers.add(
          _buildHistoryMarker(
            point: end,
            icon: Icons.location_on,
            color: status == 'ongoing' ? AppColors.primary : Colors.red,
            label: status == 'ongoing' ? 'Posisi terakhir' : 'Akhir',
          ),
        );
      }
    }

    if (destination != null && !destinationMerged) {
      markers.add(
        _buildHistoryMarker(
          point: destination,
          icon: Icons.flag_rounded,
          color: Colors.deepPurple,
          label: 'Tujuan',
        ),
      );
    }

    return markers;
  }

  Marker _buildCombinedHistoryMarker({
    required LatLng point,
    required List<(IconData, Color)> icons,
    required String label,
    required double width,
  }) {
    return Marker(
      point: point,
      width: width,
      height: 82,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < icons.length; index++) ...[
                  if (index > 0) const SizedBox(width: 3),
                  _buildCompactHistoryMarkerIcon(
                    icon: icons[index].$1,
                    color: icons[index].$2,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              maxLines: 1,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Marker _buildOverlappingStartEndMarker({
    required LatLng point,
    required double distanceMeters,
  }) {
    return Marker(
      point: point,
      width: 132,
      height: 82,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCompactHistoryMarkerIcon(
                  icon: Icons.radio_button_checked,
                  color: Colors.green,
                ),
                const SizedBox(width: 3),
                _buildCompactHistoryMarkerIcon(
                  icon: Icons.location_on,
                  color: Colors.red,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              'Awal & Akhir · ${distanceMeters.round()} m',
              maxLines: 1,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHistoryMarkerIcon({
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 17),
    );
  }

  Set<Polyline> buildHistoryPolylines(List<LatLng> routePoints) {
    if (routePoints.length < 2) return <Polyline>{};

    return {
      Polyline(
        points: routePoints,
        color: AppColors.primary,
        strokeWidth: 5.0,
        borderColor: Colors.white,
        borderStrokeWidth: 2.0,
      ),
    };
  }

  Color getStatusColor(String? status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
      case 'canceled':
      case 'batal':
        return AppColors.error;
      case 'ongoing':
        return AppColors.primary;
      default:
        return Colors.grey;
    }
  }

  Color getStatusSoftColor(String? status) {
    switch (status) {
      case 'completed':
        return AppColors.successLight;
      case 'cancelled':
      case 'canceled':
      case 'batal':
        return AppColors.errorLight;
      case 'ongoing':
        return AppColors.infoLight;
      default:
        return AppColors.surfaceLight;
    }
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Timestamp? _toTimestamp(dynamic value) {
    return value is Timestamp ? value : null;
  }

  String _safeText(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  Future<void> copyEndCoordinate(dynamic lat, dynamic lng) async {
    final coordinateText = formatCoordinate(lat, lng);
    if (coordinateText == '-') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Koordinat belum tersedia'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: coordinateText));
    debugPrint('[NAV_HISTORY_DETAIL] Koordinat berhenti berhasil dicopy');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Koordinat berhasil disalin'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Detail Perjalanan',
                  style: AppTextStyles.heading2.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'Informasi riwayat navigasi',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Data riwayat tidak ditemukan',
              style: AppTextStyles.heading2.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> data) {
    final status = data['status'] is String ? data['status'] as String : null;
    final statusColor = getStatusColor(status);
    final destinationName = _safeText(data['destinationName'], 'Tujuan');
    final statusText = formatStatusText(status);
    final statusSubtitle = switch (status) {
      'completed' => 'Perjalanan selesai',
      'cancelled' || 'canceled' || 'batal' => 'Perjalanan tidak diselesaikan',
      'ongoing' => 'Perjalanan sedang berjalan',
      _ => 'Status perjalanan tercatat',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.route_rounded, color: statusColor, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusText,
                    style: AppTextStyles.caption.copyWith(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Tujuan: $destinationName',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  statusSubtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteStep({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    bool showConnector = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            if (showConnector)
              Container(
                width: 2,
                height: 20,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 5),
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
                  color: AppColors.infoLight.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primaryDark, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing],
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE8EEF5))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfoTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    int maxLines = 2,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFE8EEF5).withValues(alpha: 0.9),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndCoordinateTile({required dynamic lat, required dynamic lng}) {
    final coordinateText = formatCoordinate(lat, lng);
    final isAvailable = coordinateText != '-';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFE8EEF5).withValues(alpha: 0.9),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.stop_circle_outlined,
                  color: AppColors.warning,
                  size: 17,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Titik berhenti pengguna',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      coordinateText,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isAvailable) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => copyEndCoordinate(lat, lng),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Salin Koordinat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning.withValues(alpha: 0.1),
                  foregroundColor: AppColors.warning,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: AppColors.warning.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Marker _buildHistoryMarker({
    required LatLng point,
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Marker(
      point: point,
      width: 92,
      height: 70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  LatLng _initialMapCenter({
    required List<LatLng> routePoints,
    required Map<String, dynamic> tripData,
  }) {
    if (routePoints.isNotEmpty) return routePoints.first;

    final origin = parseLatLng(tripData['originLat'], tripData['originLng']);
    if (origin != null) return origin;

    return const LatLng(-6.9175, 107.6191);
  }

  void _focusRoute({
    required List<LatLng> routePoints,
    required Map<String, dynamic> tripData,
  }) {
    final origin = parseLatLng(tripData['originLat'], tripData['originLng']);
    final destination = parseLatLng(
      tripData['destinationLat'],
      tripData['destinationLng'],
    );
    final focusPoints = <LatLng>[
      ...routePoints,
      if (origin != null) origin,
      if (destination != null) destination,
    ];

    if (focusPoints.isEmpty) return;

    try {
      if (focusPoints.length == 1) {
        _historyMapController.move(focusPoints.first, 16);
        return;
      }

      _historyMapController.fitCamera(
        CameraFit.bounds(
          bounds: boundsFromLatLngList(focusPoints),
          padding: const EdgeInsets.all(36),
          maxZoom: 17,
        ),
      );
    } catch (e) {
      debugPrint('[NAV_HISTORY_DETAIL] Failed to focus route: $e');
    }
  }

  String _routeFocusSignature({
    required List<LatLng> routePoints,
    required Map<String, dynamic> tripData,
  }) {
    final first = routePoints.isNotEmpty ? routePoints.first : null;
    final last = routePoints.isNotEmpty ? routePoints.last : null;
    return [
      routePoints.length,
      first?.latitude,
      first?.longitude,
      last?.latitude,
      last?.longitude,
      tripData['originLat'],
      tripData['originLng'],
      tripData['destinationLat'],
      tripData['destinationLng'],
    ].join('|');
  }

  void _focusRouteWhenReady({
    required List<LatLng> routePoints,
    required Map<String, dynamic> tripData,
    bool force = false,
  }) {
    if (!_isHistoryMapReady) return;

    final signature = _routeFocusSignature(
      routePoints: routePoints,
      tripData: tripData,
    );
    if (!force && signature == _lastFocusedRouteSignature) return;
    _lastFocusedRouteSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusRoute(routePoints: routePoints, tripData: tripData);
    });
  }

  Widget _buildRouteMapSection(Map<String, dynamic> tripData) {
    final status = tripData['status'] is String
        ? tripData['status'] as String
        : 'ongoing';

    return _buildSection(
      title: 'Rute Perjalanan',
      icon: Icons.map_rounded,
      children: [
        Text(
          'Peta rute perjalanan pengguna',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _routePointsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: 260,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              debugPrint(
                '[NAV_HISTORY_DETAIL] Route points stream error: ${snapshot.error}',
              );
            }

            final docs = snapshot.data?.docs ?? [];
            final routePoints = buildRoutePolyline(docs);
            final initialCenter = _initialMapCenter(
              routePoints: routePoints,
              tripData: tripData,
            );

            if (routePoints.isEmpty) {
              return Container(
                height: 260,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.08),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Belum ada data rute perjalanan',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final markers = buildHistoryMarkers(
              routePoints: routePoints,
              tripData: tripData,
              status: status,
            ).toList();
            final polylines = buildHistoryPolylines(routePoints).toList();

            _focusRouteWhenReady(routePoints: routePoints, tripData: tripData);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 260,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 0.8,
                      ),
                    ),
                    child: FlutterMap(
                      mapController: _historyMapController,
                      options: MapOptions(
                        initialCenter: initialCenter,
                        initialZoom: routePoints.length >= 2 ? 15 : 16,
                        minZoom: 5,
                        maxZoom: 18,
                        onMapReady: () {
                          _isHistoryMapReady = true;
                          _focusRouteWhenReady(
                            routePoints: routePoints,
                            tripData: tripData,
                            force: true,
                          );
                        },
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.my_app',
                        ),
                        if (polylines.isNotEmpty)
                          PolylineLayer(polylines: polylines),
                        MarkerLayer(markers: markers),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _focusRoute(
                      routePoints: routePoints,
                      tripData: tripData,
                    ),
                    icon: const Icon(
                      Icons.center_focus_strong_rounded,
                      size: 18,
                    ),
                    label: const Text('Fokus Rute'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                if (status == 'cancelled' ||
                    status == 'canceled' ||
                    status == 'batal') ...[
                  const SizedBox(height: 12),
                  _buildEndCoordinateTile(
                    lat: tripData['endLat'],
                    lng: tripData['endLng'],
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildTimelineSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _eventsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
            '[NAV_HISTORY_DETAIL] Events stream error: ${snapshot.error}',
          );
        }

        final docs = (snapshot.data?.docs ?? []).where((doc) {
          final type = doc.data()['type'];
          return type is String && shouldShowTripEvent(type);
        }).toList();
        final isWaiting = snapshot.connectionState == ConnectionState.waiting;

        return _buildSection(
          title: 'Aktivitas',
          icon: Icons.timeline_rounded,
          trailing: _buildEventCountBadge(isWaiting ? null : docs.length),
          children: [
            if (isWaiting)
              Container(
                height: 96,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              )
            else if (docs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withOpacity(0.1)),
                ),
                child: Text(
                  'Tidak ada kejadian selama perjalanan',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Column(
                children: [
                  for (var i = 0; i < docs.length; i++)
                    _buildEventTimelineItem(
                      docs[i].data(),
                      isLast: i == docs.length - 1,
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildEventCountBadge(int? count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.1),
          width: 0.8,
        ),
      ),
      child: Text(
        count == null ? '-' : '$count',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.primary.withOpacity(0.8),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildEventTimelineItem(
    Map<String, dynamic> data, {
    required bool isLast,
  }) {
    final type = data['type'] is String ? data['type'] as String : 'unknown';
    final color = getEventColor(type);
    final timestamp = _toTimestamp(data['timestamp']);
    final title = _safeText(data['title'], 'Kejadian perjalanan');
    final description = _safeText(data['description'], '-');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.2), width: 1.2),
                ),
                child: Icon(getEventIcon(type), color: color, size: 14),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: color.withOpacity(0.15),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 11, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formatEventTime(timestamp),
                        style: AppTextStyles.caption.copyWith(
                          color: color.withOpacity(0.7),
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary.withOpacity(0.85),
                      height: 1.4,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailContent(Map<String, dynamic> data) {
    final startTime = _toTimestamp(data['startTime']);
    final endTime = _toTimestamp(data['endTime']);
    final status = data['status'] is String ? data['status'] as String : null;
    final originName = _safeText(data['originName'], 'Lokasi awal');
    final destinationName = _safeText(data['destinationName'], 'Tujuan');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _buildSummaryCard(data),
        const SizedBox(height: 14),
        _buildSection(
          title: 'Informasi Perjalanan',
          icon: Icons.info_outline_rounded,
          children: [
            _buildDetailRow('Tanggal', formatTripDate(startTime)),
            _buildDetailRow('Waktu mulai', formatTripTime(startTime)),
            _buildDetailRow('Waktu selesai', formatTripTime(endTime)),
            _buildDetailRow(
              'Durasi',
              formatDisplayDuration(data['durationSeconds']),
            ),
            _buildDetailRow(
              'Status',
              formatStatusText(status),
              valueColor: getStatusColor(status),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildSection(
          title: 'Rute',
          icon: Icons.route_rounded,
          children: [
            _buildRouteStep(
              icon: Icons.radio_button_checked,
              color: AppColors.success,
              label: 'Dari',
              value: originName,
              showConnector: true,
            ),
            _buildRouteStep(
              icon: Icons.location_on_rounded,
              color: AppColors.error,
              label: 'Ke',
              value: destinationName,
            ),
            const SizedBox(height: 10),
            _buildRouteInfoTile(
              icon: Icons.straighten_rounded,
              color: AppColors.primary,
              label: 'Jarak total',
              value: formatDistance(data['totalDistanceMeters']),
              maxLines: 1,
            ),
            _buildRouteInfoTile(
              icon: Icons.my_location_rounded,
              color: AppColors.textTertiary,
              label: 'Koordinat awal',
              value: formatCoordinate(data['originLat'], data['originLng']),
              maxLines: 2,
            ),
            _buildRouteInfoTile(
              icon: Icons.flag_rounded,
              color: AppColors.textTertiary,
              label: 'Koordinat tujuan',
              value: formatCoordinate(
                data['destinationLat'],
                data['destinationLng'],
              ),
              maxLines: 2,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildRouteMapSection(data),
        const SizedBox(height: 14),
        _buildTimelineSection(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      body: Container(
        color: const Color(0xFFF7FAFD),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _tripStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      debugPrint(
                        '[NAV_HISTORY_DETAIL] Failed to load trip ${widget.tripId}: ${snapshot.error}',
                      );
                      return _buildNotFoundState();
                    }

                    final doc = snapshot.data;
                    final data = doc?.data();
                    if (doc == null || !doc.exists || data == null) {
                      return _buildNotFoundState();
                    }

                    return _buildDetailContent(data);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NavigationHistoryItem {
  final String id;
  final Timestamp? startTime;
  final Timestamp? endTime;
  final dynamic durationSeconds;
  final dynamic originName;
  final dynamic destinationName;
  final dynamic totalDistanceMeters;
  final String? status;
  final dynamic eventCount;

  const NavigationHistoryItem({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.originName,
    required this.destinationName,
    required this.totalDistanceMeters,
    required this.status,
    required this.eventCount,
  });

  factory NavigationHistoryItem.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return NavigationHistoryItem(
      id: doc.id,
      startTime: data['startTime'] is Timestamp
          ? data['startTime'] as Timestamp
          : null,
      endTime: data['endTime'] is Timestamp
          ? data['endTime'] as Timestamp
          : null,
      durationSeconds: data['durationSeconds'],
      originName: data['originName'],
      destinationName: data['destinationName'],
      totalDistanceMeters: data['totalDistanceMeters'],
      status: data['status'] is String ? data['status'] as String : null,
      eventCount: data['eventCount'],
    );
  }
}
