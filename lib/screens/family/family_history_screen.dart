import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../services/analytics_service.dart';
import '../../utils/constants.dart';

class FamilyHistoryScreen extends StatefulWidget {
  final String targetUid;
  final String familyId;

  const FamilyHistoryScreen({
    super.key,
    required this.targetUid,
    required this.familyId,
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
  bool _isSheetExpanded = false;
  Timer? _realtimeUpdateTimer;
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

  Widget _buildMiniTag(String label, {IconData? icon, Color color = AppColors.primary}) {
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
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '• $item',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, {Color color = AppColors.primary}) {
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

  Widget _buildTunaNetraInfoCard(String pairedUid, Map<String, dynamic>? liveData) {
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
                  final hasLiveData = snapshot.hasData && snapshot.data?.exists == true;
                  final liveData = hasLiveData ? snapshot.data!.data() : null;
                  
                  final isNavigating = liveData?['isNavigating'] as bool? ?? false;
                  final batteryLevel = liveData?['batteryLevel']?.toString() ?? '-';
                  final speed = liveData?['speed']?.toString() ?? '-';
                  final accuracy = liveData?['accuracy']?.toString() ?? '-';
                  final destinationName = (liveData?['destinationName'] as String?)?.isNotEmpty == true
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
                  final navigationText =
                      buildNavigationText(isGpsActive, isNavigating);
                  
                  return Padding(
                    padding: MediaQuery.of(context).viewInsets,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                          _buildDetailRow(
                            'GPS',
                            gpsStatusText,
                          ),
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
                          _buildDetailRow(
                            'Navigasi',
                            navigationText,
                          ),
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
                            isNavigationActive ? formatLastUpdate(updatedAt) : '-',
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
                                padding: const EdgeInsets.symmetric(vertical: 14),
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
      String tunaNetraUid) {
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
            if (hasLocation)
              MarkerLayer(
                markers: [
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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.textTertiary.withOpacity(0.2)),
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

  List<Widget> _buildLivePanelContent(Map<String, dynamic>? liveData) {
    final destinationName = (liveData?['destinationName'] as String?)?.isNotEmpty == true
        ? liveData!['destinationName'] as String
        : '-';
    final speedValue = _parseDouble(liveData?['speed']);
    final speed = speedValue != null ? '${speedValue.toStringAsFixed(1)} m/s' : '-';
    final battery = liveData?['batteryLevel'] != null
        ? '${liveData!['batteryLevel']}%'
        : '-';
    final accuracyValue = _parseDouble(liveData?['accuracy']);
    final accuracy = accuracyValue != null ? '${accuracyValue.toStringAsFixed(1)} m' : '-';
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
    final displayLat =
        isGpsActive && lat != null ? lat.toStringAsFixed(6) : '-';
    final displayLng =
        isGpsActive && lng != null ? lng.toStringAsFixed(6) : '-';
    final displayAccuracy = isNavigationActive ? accuracy : '-';
    final displayDestination = isNavigationActive ? destinationName : '-';
    final navigationText = buildNavigationText(isGpsActive, isNavigating);
    final gpsStatusText = buildGpsStatusText(isGpsActive);
    final displaySpeed = isNavigationActive ? speed : '-';
    final displayHeading =
        isNavigationActive ? headingValue.toStringAsFixed(0) : '-';
    final displayBattery = isGpsActive ? battery : '-';
    final displayLastUpdate =
        isNavigationActive ? formatLastUpdate(updatedAt) : '-';

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
        items: [
          'Kecepatan: $displaySpeed',
          'Arah: $displayHeading°',
        ],
      ),
      const SizedBox(height: 18),
      if (isGpsActive)
        Row(
          children: [
            Expanded(
              child: _buildMiniTag('GPS Live 🟢', icon: Icons.gps_fixed, color: Colors.green),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMiniTag('Predicted ⚠️', icon: Icons.verified_user, color: Colors.amber),
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
    return Scaffold(
      body: FutureBuilder<String?>(
        future: _pairedUserUidFuture,
        builder: (context, pairedSnapshot) {
          final pairedUid = pairedSnapshot.data;
          if (pairedSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (pairedSnapshot.hasError || pairedUid == null || pairedUid.isEmpty) {
            return Stack(
              children: [
                Positioned.fill(child: _buildMainMap(null)),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.textTertiary.withOpacity(0.2)),
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
              final hasLiveData = snapshot.hasData && snapshot.data?.exists == true;
              final liveData = hasLiveData ? snapshot.data!.data() : null;

              return Stack(
                children: [
                  Positioned.fill(
                    child: _buildMainMap(liveData),
                  ),
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
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ShaderMask(
                                    shaderCallback: (bounds) =>
                                        AppColors.primaryGradient.createShader(bounds),
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
                  DraggableScrollableSheet(
                    controller: _sheetController,
                    minChildSize: _sheetMin,
                    maxChildSize: _sheetMax,
                    initialChildSize: _sheetMin,
                    builder: (context, controller) {
                      final isExpanded = _isSheetExpanded;
                      return Container(
                        decoration: BoxDecoration(
                          color: isExpanded ? AppColors.background : Colors.transparent,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          boxShadow: isExpanded
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.18),
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
                                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                      child: ListView(
                                        controller: controller,
                                        padding: const EdgeInsets.only(bottom: 24),
                                        children: [
                                          GestureDetector(
                                            onTap: _toggleSheet,
                                            child: Center(
                                              child: Container(
                                                width: 48,
                                                height: 5,
                                                decoration: BoxDecoration(
                                                  color: AppColors.textTertiary
                                                      .withOpacity(0.4),
                                                  borderRadius:
                                                      BorderRadius.circular(999),
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
                                                  style: AppTextStyles.bodyLarge.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: _openHistoryScreen,
                                                child: Container(
                                                  width: 42,
                                                  height: 42,
                                                  decoration: BoxDecoration(
                                                    gradient: AppColors.primaryGradient,
                                                    borderRadius:
                                                        BorderRadius.circular(14),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: AppColors.primary
                                                            .withOpacity(0.25),
                                                        blurRadius: 12,
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
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Info Realtime',
                                                      style: AppTextStyles.bodyMedium
                                                          .copyWith(
                                                        fontWeight: FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      'Status aktivitas dan koneksi pengguna',
                                                      style: AppTextStyles.bodySmall
                                                          .copyWith(
                                                        color: AppColors.textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          _buildTunaNetraInfoCard(pairedUid, liveData),
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
                                              children: _buildLivePanelContent(liveData),
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
                                        onTap: () => _showTunaNetraInfo(pairedUid),
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
                                            gradient: AppColors.primaryGradient,
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
                                        onTap: () => _showTunaNetraInfo(pairedUid),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            0,
                                            16,
                                            16,
                                          ),
                                          child: _buildCollapsedSheetCard(liveData),
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

  String formatDistance(dynamic totalDistanceMeters) {
    final meters = _toDouble(totalDistanceMeters);
    if (meters == null) return '-';
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String formatStatusText(String? status) {
    switch (status) {
      case 'completed':
        return 'Selesai ✅';
      case 'cancelled':
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
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'ongoing':
        return AppColors.primary;
      default:
        return Colors.grey;
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
    final durationText = formatDuration(item.durationSeconds);
    final startTimeText = formatTripTime(item.startTime);
    final endTimeText = formatTripTime(item.endTime);
    final originName = _safeText(item.originName, 'Lokasi awal');
    final destinationName = _safeText(item.destinationName, 'Tujuan');
    final eventCount = _toInt(item.eventCount) ?? 0;

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
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.07),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  formatTripDate(item.startTime),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor.withOpacity(0.25)),
                ),
                child: Text(
                  formatStatusText(item.status),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$startTimeText → $endTimeText ($durationText)',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _buildPointIcon(
                  icon: Icons.radio_button_checked,
                  color: Colors.green,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    originName,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    destinationName,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                _buildPointIcon(icon: Icons.location_on, color: Colors.red),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  icon: Icons.straighten_rounded,
                  label: formatDistance(item.totalDistanceMeters),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  icon: Icons.warning_amber_rounded,
                  label: '$eventCount event',
                  color: eventCount == 0 ? Colors.green : Colors.orange,
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

  Widget _buildPointIcon({
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }

  Widget _buildMiniStat({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
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
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.white, Colors.white.withOpacity(0.95)],
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                AppColors.primaryGradient.createShader(bounds),
                            child: Text(
                              'Riwayat Perjalanan',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
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

  const NavigationHistoryDetailScreen({
    super.key,
    required this.tripId,
  });

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

  String formatDistance(dynamic totalDistanceMeters) {
    final meters = _toDouble(totalDistanceMeters);
    if (meters == null) return '-';
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String formatStatusText(String? status) {
    switch (status) {
      case 'completed':
        return 'Selesai ✅';
      case 'cancelled':
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

  String formatEventCount(dynamic eventCount) {
    final count = _toInt(eventCount) ?? 0;
    return '$count event';
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
      case 'gps_lost':
        return Icons.gps_off_rounded;
      case 'gps_recovered':
        return Icons.gps_fixed_rounded;
      case 'prediction_started':
        return Icons.timeline_rounded;
      case 'prediction_stopped':
        return Icons.gps_fixed_rounded;
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
      case 'gps_recovered':
        return Colors.green;
      case 'navigation_cancelled':
      case 'gps_lost':
      case 'sos_pressed':
        return Colors.red;
      case 'off_route':
      case 'prediction_started':
        return Colors.orange;
      case 'prediction_stopped':
        return Colors.blue;
      default:
        return Colors.grey;
    }
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
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'ongoing':
        return AppColors.primary;
      default:
        return Colors.grey;
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
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
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
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) =>
                      AppColors.primaryGradient.createShader(bounds),
                  child: Text(
                    'Detail Perjalanan',
                    style: AppTextStyles.heading2.copyWith(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
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
          colors: [
            statusColor.withOpacity(0.12),
            Colors.white,
          ],
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
                ),
                const SizedBox(height: 6),
                Text(
                  '$originName → $destinationName',
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
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.07),
            blurRadius: 18,
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.right,
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
    final status =
        tripData['status'] is String ? tripData['status'] as String : 'ongoing';

    return _buildSection(
      title: 'Rute Perjalanan',
      icon: Icons.map_rounded,
      children: [
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
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
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
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 280,
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
                Align(
                  alignment: Alignment.centerRight,
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
    return _buildSection(
      title: 'Timeline Kejadian',
      icon: Icons.timeline_rounded,
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _eventsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: 96,
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              debugPrint(
                '[NAV_HISTORY_DETAIL] Events stream error: ${snapshot.error}',
              );
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withOpacity(0.1)),
                ),
                child: Text(
                  'Tidak ada event selama perjalanan',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            }

            return Column(
              children: [
                for (var i = 0; i < docs.length; i++)
                  _buildEventTimelineItem(
                    docs[i].data(),
                    isLast: i == docs.length - 1,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildEventTimelineItem(
    Map<String, dynamic> data, {
    required bool isLast,
  }) {
    final type = data['type'] is String ? data['type'] as String : 'unknown';
    final color = getEventColor(type);
    final timestamp = _toTimestamp(data['timestamp']);
    final title = _safeText(data['title'], 'Event perjalanan');
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
                  color: color.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.16)),
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
    final userId = _safeText(data['userId'], '-');

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
            _buildDetailRow('Durasi', formatDuration(data['durationSeconds'])),
            _buildDetailRow('Status', formatStatusText(status)),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: 'Rute',
          icon: Icons.route_rounded,
          children: [
            _buildDetailRow('Lokasi awal', originName),
            _buildDetailRow('Tujuan', destinationName),
            _buildDetailRow(
              'Jarak total',
              formatDistance(data['totalDistanceMeters']),
            ),
            _buildDetailRow(
              'Koordinat awal',
              formatCoordinate(data['originLat'], data['originLng']),
            ),
            _buildDetailRow(
              'Koordinat tujuan',
              formatCoordinate(data['destinationLat'], data['destinationLng']),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildRouteMapSection(data),
        const SizedBox(height: 16),
        _buildTimelineSection(),
        const SizedBox(height: 16),
        _buildSection(
          title: 'Keamanan',
          icon: Icons.health_and_safety_rounded,
          children: [
            _buildDetailRow(
              'Jumlah event',
              formatEventCount(data['eventCount']),
            ),
          ],
        ),
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
      startTime:
          data['startTime'] is Timestamp ? data['startTime'] as Timestamp : null,
      endTime: data['endTime'] is Timestamp ? data['endTime'] as Timestamp : null,
      durationSeconds: data['durationSeconds'],
      originName: data['originName'],
      destinationName: data['destinationName'],
      totalDistanceMeters: data['totalDistanceMeters'],
      status: data['status'] is String ? data['status'] as String : null,
      eventCount: data['eventCount'],
    );
  }
}
