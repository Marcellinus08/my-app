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
import '../../services/notification_service.dart';
import '../../utils/constants.dart';

const Color _historyPrimaryText = Color(0xFF475569);
const Color _historyStrongText = Color(0xFF334155);

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
      navigator.pop();
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
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
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pantau kondisi user secara cepat',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
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

  void _openHistoryScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyHistoryDetailScreen(
          targetUid: widget.targetUid,
          familyId: widget.familyId,
        ),
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        isScrollControlled: true,
        builder: (context) {
          // Use StatefulBuilder to allow realtime updates in modal
          return StatefulBuilder(
            builder: (context, setModalState) {
              _modalSetState = setModalState;
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: getLiveTrackingStream(pairedUid),
                builder: (context, snapshot) {
                  final hasLiveData =
                      snapshot.hasData && snapshot.data?.exists == true;
                  final liveData = hasLiveData ? snapshot.data!.data() : null;

                  final isNavigating =
                      liveData?['isNavigating'] as bool? ?? false;
                  final batteryLevel =
                      liveData?['batteryLevel']?.toString() ?? '-';
                  final speed = liveData?['speed']?.toString() ?? '-';
                  final accuracy = liveData?['accuracy']?.toString() ?? '-';
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
                  final updatedAt = _parseTimestamp(liveData?['updatedAt']);
                  final isGpsActive = isGpsActiveTracking(liveData);
                  final isNavigationActive = isGpsActive && isNavigating;
                  final gpsStatusText = buildGpsStatusText(isGpsActive);
                  final navigationText = buildNavigationText(
                    isGpsActive,
                    isNavigating,
                  );

                  return Padding(
                    padding: MediaQuery.of(context).viewInsets,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
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
                                color: AppColors.textTertiary.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Detail Tuna Netra',
                            style: AppTextStyles.heading2.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Data diambil langsung dari live_tracking.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _buildDetailRow('Nama', userName),
                          const SizedBox(height: 12),
                          _buildDetailRow('GPS', gpsStatusText),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            'Lokasi',
                            isGpsActive ? locationText : '-',
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            'Baterai',
                            isGpsActive
                                ? (batteryLevel != '-' ? '$batteryLevel%' : '-')
                                : '-',
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow('Navigasi', navigationText),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            'Tujuan',
                            isNavigationActive ? destinationName : '-',
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            'Akurasi',
                            isNavigationActive
                                ? (accuracy != '-' ? '$accuracy meter' : '-')
                                : '-',
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            'Kecepatan',
                            isNavigationActive
                                ? (speed != '-' ? '$speed m/s' : '-')
                                : '-',
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            'Last update',
                            isNavigationActive
                                ? formatLastUpdate(updatedAt)
                                : '-',
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
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

  Widget _buildDetailRow(String title, String value) {
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
          child: Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
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
    return value is Timestamp ? value : null;
  }

  Future<String?> getPairedUserUid() async {
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
    return null;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> getLiveTrackingStream(
    String tunaNetraUid,
  ) {
    return _firestore.collection('live_tracking').doc(tunaNetraUid).snapshots();
  }

  bool isTrackingFresh(Timestamp? updatedAt) {
    if (updatedAt == null) return false;
    final age = DateTime.now().difference(updatedAt.toDate());
    return age.inSeconds <= 30;
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
          content: Text('Koordinat tidak tersedia'),
          backgroundColor: Colors.orange,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS ditandai sudah ditangani'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('[FamilyHistory] error resolve SOS: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menandai SOS: $e'),
          backgroundColor: AppColors.error,
        ),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Tandai SOS ditangani?'),
        content: const Text(
          'Pastikan keluarga sudah merespons kondisi pengguna.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ya, Tandai'),
          ),
        ],
      ),
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
    final hasLocation = lat != null && lng != null && isGpsActive;
    final center = hasLocation ? LatLng(lat, lng) : _fallbackCenter;

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
        isGpsActive: isGpsActive,
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
          isGpsActive: isGpsActive,
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
              flags: InteractiveFlag.all,
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
                          color: Colors.blue.withOpacity(0.9),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.35),
                              blurRadius: 10,
                              spreadRadius: 2,
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
        if (!hasLocation)
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
                  isGpsActive ? 'Belum ada data lokasi' : 'User sedang offline',
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

  Widget buildSosEmergencyCard({
    required String sosId,
    required Map<String, dynamic> sosData,
  }) {
    final createdAt = _parseTimestamp(sosData['createdAt']);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFB91C1C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.16)),
          boxShadow: [
            BoxShadow(
              color: AppColors.error.withOpacity(0.26),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOS Aktif',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatSosSentTime(createdAt),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.82),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Text(
                'Lat: ${formatSosCoordinate(sosData['lat'])}  |  '
                'Lng: ${formatSosCoordinate(sosData['lng'])}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSosActionButton(
                    icon: Icons.copy_rounded,
                    label: 'Copy Koordinat',
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withOpacity(0.14),
                    borderColor: Colors.white.withOpacity(0.65),
                    onPressed: () =>
                        copySosCoordinate(sosData['lat'], sosData['lng']),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSosActionButton(
                    icon: Icons.check_circle_rounded,
                    label: 'Tandai Ditangani',
                    foregroundColor: AppColors.error,
                    backgroundColor: Colors.white,
                    onPressed: () => _confirmResolveSosAlert(sosId),
                  ),
                ),
              ],
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 42),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor ?? Colors.transparent),
          ),
          textStyle: AppTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w800,
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
    final speedValue = _parseDouble(liveData?['speed']);
    final speed = speedValue != null
        ? '${speedValue.toStringAsFixed(1)} m/s'
        : '-';
    final battery = liveData?['batteryLevel'] != null
        ? '${liveData!['batteryLevel']}%'
        : '-';
    final accuracyValue = _parseDouble(liveData?['accuracy']);
    final accuracy = accuracyValue != null
        ? '${accuracyValue.toStringAsFixed(1)} m'
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
    final displayAccuracy = isNavigationActive ? accuracy : '-';
    final displayDestination = isNavigationActive ? destinationName : '-';
    final navigationText = buildNavigationText(isGpsActive, isNavigating);
    final gpsStatusText = buildGpsStatusText(isGpsActive);
    final displaySpeed = isNavigationActive ? speed : '-';
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
            : 'User sedang offline. Data tidak tersedia.',
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
          'Akurasi GPS: $displayAccuracy',
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
        items: ['Kecepatan: $displaySpeed', 'Arah: $displayHeading°'],
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
      canPop: Navigator.canPop(context),
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

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: getLiveTrackingStream(pairedUid),
              builder: (context, snapshot) {
                final hasLiveData =
                    snapshot.hasData && snapshot.data?.exists == true;
                final liveData = hasLiveData ? snapshot.data!.data() : null;
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
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white,
                                Colors.white.withOpacity(0.95),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.15),
                                blurRadius: 25,
                                offset: const Offset(0, 10),
                              ),
                            ],
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: _handleBackNavigation,
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
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ShaderMask(
                                      shaderCallback: (bounds) => AppColors
                                          .primaryGradient
                                          .createShader(bounds),
                                      child: Text(
                                        'Lihat Detail & Lokasi',
                                        style: AppTextStyles.heading2.copyWith(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Pantau realtime & riwayat perjalanan',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
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
                      top: 154,
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
                    DraggableScrollableSheet(
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
                                          16,
                                          12,
                                          16,
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
                                                    'Riwayat Perjalanan',
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
                                                GestureDetector(
                                                  onTap: _openHistoryScreen,
                                                  child: Container(
                                                    width: 42,
                                                    height: 42,
                                                    decoration: BoxDecoration(
                                                      gradient: AppColors
                                                          .primaryGradient,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: AppColors
                                                              .primary
                                                              .withOpacity(
                                                                0.25,
                                                              ),
                                                          blurRadius: 12,
                                                          offset: const Offset(
                                                            0,
                                                            6,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    child: const Icon(
                                                      Icons.route_rounded,
                                                      color: Colors.white,
                                                      size: 22,
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
                                                      const SizedBox(height: 2),
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
                                              padding: const EdgeInsets.all(12),
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
                                                    offset: const Offset(0, 8),
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
                                      left: 16,
                                      right: 16,
                                      bottom: 12,
                                      child: _buildCollapsedSheetCard(liveData),
                                    ),
                                  ],
                                )
                              : Material(
                                  color: Colors.transparent,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onTap: () =>
                                              _showTunaNetraInfo(pairedUid),
                                        ),
                                      ),
                                      Positioned(
                                        right: 24,
                                        bottom: 118,
                                        child: GestureDetector(
                                          onTap: _openHistoryScreen,
                                          child: Container(
                                            width: 46,
                                            height: 46,
                                            decoration: BoxDecoration(
                                              gradient:
                                                  AppColors.primaryGradient,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppColors.primary
                                                      .withOpacity(0.25),
                                                  blurRadius: 14,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.route_rounded,
                                              color: Colors.white,
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: GestureDetector(
                                          onTap: () =>
                                              _showTunaNetraInfo(pairedUid),
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              0,
                                              16,
                                              16,
                                            ),
                                            child: _buildCollapsedSheetCard(
                                              liveData,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        );
                      },
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: AppTextStyles.heading2.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.6,
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
    final statusBackgroundColor = getStatusBackgroundColor(item.status);
    final durationText = formatCardDuration(item.durationSeconds);
    final startTimeText = formatTripTime(item.startTime);
    final endTimeText = formatTripTime(item.endTime);
    final originName = _safeText(item.originName, 'Lokasi awal');
    final destinationName = _safeText(item.destinationName, 'Tujuan');

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
        borderRadius: BorderRadius.circular(22),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.primary.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.infoLight,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.12),
                      ),
                    ),
                    child: Text(
                      formatTripDate(item.startTime),
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: statusBackgroundColor,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: statusColor.withOpacity(0.18)),
                    ),
                    child: Text(
                      formatStatusText(item.status),
                      style: AppTextStyles.caption.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$startTimeText -> $endTimeText',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: _historyStrongText,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    durationText,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                  border: Border.all(color: const Color(0xFFE8EEF5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rute Perjalanan',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildLocationInfo(
                      icon: Icons.radio_button_checked,
                      color: AppColors.success,
                      label: 'Dari',
                      value: originName,
                      showConnector: true,
                    ),
                    const SizedBox(height: 6),
                    _buildLocationInfo(
                      icon: Icons.location_on_rounded,
                      color: AppColors.error,
                      label: 'Ke',
                      value: destinationName,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStat(
                      icon: Icons.straighten_rounded,
                      label:
                          'Jarak: ${formatDistance(item.totalDistanceMeters)}',
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
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
                              : '$eventCount aktivitas',
                          color: eventCount == 0
                              ? AppColors.success
                              : AppColors.warning,
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
                height: 30,
                margin: const EdgeInsets.symmetric(vertical: 4),
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
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.visible,
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: AppTextStyles.bodySmall.copyWith(
                  color: _historyPrimaryText,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPointIcon({required IconData icon, required Color color}) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }

  Widget _buildMiniStat({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: color,
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFAFBFC),
              AppColors.primaryLight.withOpacity(0.04),
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
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                padding: const EdgeInsets.all(16),
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
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Riwayat Perjalanan',
                            style: AppTextStyles.heading2.copyWith(
                              color: AppColors.primary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pantau aktivitas & keamanan',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
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
    final destination = parseLatLng(
      tripData['destinationLat'],
      tripData['destinationLng'],
    );

    if (routePoints.length == 1) {
      markers.add(
        _buildHistoryMarker(
          point: routePoints.first,
          icon: Icons.location_on,
          color: status == 'ongoing' ? AppColors.primary : Colors.green,
          label: status == 'ongoing' ? 'Posisi terakhir' : 'Titik rute',
        ),
      );
    } else if (routePoints.length >= 2) {
      markers.add(
        _buildHistoryMarker(
          point: routePoints.first,
          icon: Icons.radio_button_checked,
          color: Colors.green,
          label: 'Awal',
        ),
      );

      markers.add(
        _buildHistoryMarker(
          point: routePoints.last,
          icon: Icons.location_on,
          color: status == 'ongoing' ? AppColors.primary : Colors.red,
          label: status == 'ongoing' ? 'Posisi terakhir' : 'Akhir',
        ),
      );
    }

    if (destination != null) {
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

  Widget _buildHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: AppColors.primary.withOpacity(0.08),
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
                borderRadius: BorderRadius.circular(14),
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
                    color: AppColors.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Informasi riwayat navigasi',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
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
    final originName = _safeText(data['originName'], 'Lokasi awal');
    final destinationName = _safeText(data['destinationName'], 'Tujuan');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statusColor.withOpacity(0.12), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.route_rounded, color: statusColor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatStatusText(status),
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '$originName -> $destinationName',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing],
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
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
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EEF5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 19),
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
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _routePointsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: 280,
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
                height: 280,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.infoLight.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primary.withOpacity(0.1)),
                ),
                child: Center(
                  child: Text(
                    'Belum ada data rute perjalanan',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
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

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _focusRoute(routePoints: routePoints, tripData: tripData);
            });

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    height: 280,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.10),
                      ),
                    ),
                    child: FlutterMap(
                      mapController: _historyMapController,
                      options: MapOptions(
                        initialCenter: initialCenter,
                        initialZoom: routePoints.length >= 2 ? 15 : 16,
                        minZoom: 5,
                        maxZoom: 18,
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _focusRoute(
                      routePoints: routePoints,
                      tripData: tripData,
                    ),
                    icon: const Icon(Icons.center_focus_strong_rounded),
                    label: const Text('Fokus Rute'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
      ),
      child: Text(
        count == null ? '-' : '$count',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w900,
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.24)),
                ),
                child: Icon(getEventIcon(type), color: color, size: 20),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    color: color.withOpacity(0.22),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withOpacity(0.14)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textPrimary.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatEventTime(timestamp),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
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
        const SizedBox(height: 16),
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
            _buildDetailRow('Status', formatStatusText(status)),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: 'Rute',
          icon: Icons.route_rounded,
          children: [
            _buildRouteInfoTile(
              icon: Icons.radio_button_checked,
              color: AppColors.success,
              label: 'Dari',
              value: originName,
            ),
            _buildRouteInfoTile(
              icon: Icons.location_on_rounded,
              color: AppColors.error,
              label: 'Ke',
              value: destinationName,
            ),
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
        const SizedBox(height: 16),
        _buildRouteMapSection(data),
        const SizedBox(height: 16),
        _buildTimelineSection(),
      ],
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
