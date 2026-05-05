import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../models/family_location_model.dart';
import '../../services/family_location_service.dart';
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
  final FamilyLocationService _service = FamilyLocationService();
  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  late final Stream<FamilyLocation> _liveStream;
  FamilyLocation? _latestLocation;
  LatLng? _lastLiveCenter;
  bool _isSheetExpanded = false;
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
    _liveStream = _service.listenToRealtime(
      widget.targetUid,
      storeHistory: false,
    );
  }

  @override
  void dispose() {
    _service.dispose();
    _sheetController.dispose();
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

  Widget _buildCollapsedSheetCard(FamilyLocation? location) {
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

  String _activityLabel(FamilyLocation location) {
    if (location.navigationStatus == 'navigating') {
      return 'Navigasi aktif';
    }
    if (location.speed >= 0.8) {
      return 'Sedang berjalan';
    }
    return 'Diam';
  }

  String _formatTimeAgo(DateTime timestamp) {
    final duration = DateTime.now().difference(timestamp);
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

  Color _activityColor(FamilyLocation location) {
    if (location.navigationStatus == 'navigating') {
      return Colors.blue;
    }
    if (location.speed >= 0.8) {
      return Colors.green;
    }
    return Colors.orange;
  }

  String _navigationLabel(FamilyLocation location) {
    if (location.navigationStatus == 'navigating') {
      return 'Menuju: ${location.destination ?? '-'}';
    }
    return 'Tidak sedang navigasi';
  }

  String _etaLabel(FamilyLocation location) {
    if (location.navigationStatus == 'navigating') {
      return 'Estimasi: sedang dihitung';
    }
    return 'Estimasi: -';
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

  Widget _buildTunaNetraInfoCard() {
    return GestureDetector(
      onTap: _showTunaNetraInfo,
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
                    'Ketuk untuk melihat detail pengguna (dummy data)',
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

  void _showTunaNetraInfo() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
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
                  'Informasi ini masih menggunakan data dummy. Nantinya akan diambil dari profil tuna netra yang dipantau.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                _buildDetailRow('Nama', 'Adi Saputra'),
                const SizedBox(height: 12),
                _buildDetailRow('Usia', '28 tahun'),
                const SizedBox(height: 12),
                _buildDetailRow('Lokasi', 'Bandung, Jawa Barat'),
                const SizedBox(height: 12),
                _buildDetailRow('Kondisi', 'Stabil'),
                const SizedBox(height: 12),
                _buildDetailRow('Status navigasi', 'Sedang berjalan'),
                const SizedBox(height: 12),
                _buildDetailRow(
                  'Last update',
                  _latestLocation != null
                      ? _formatTimeAgo(_latestLocation!.timestamp)
                      : '3 detik lalu',
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

  Widget _buildMainMap(FamilyLocation? location) {
    final hasLocation = location != null;
    final center = hasLocation
        ? LatLng(location.latitude, location.longitude)
        : _fallbackCenter;

    if (_lastLiveCenter == null ||
        _lastLiveCenter!.latitude != center.latitude ||
        _lastLiveCenter!.longitude != center.longitude) {
      _lastLiveCenter = center;
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
                    width: 48,
                    height: 48,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green.withOpacity(0.9),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person_pin_circle,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildLivePanelContent(FamilyLocation? location) {
    final destination = location?.destination ?? 'Kampus';
    final speed = location != null ? '${location.speed.toStringAsFixed(1)} m/s' : '1.2 m/s';
    final battery = location != null ? '${location.battery.round()}%' : '45%';
    final gpsAccuracy = '5 m';
    final address = 'Jl. Merdeka No. 1, Bandung';
    final isNavigating = location?.navigationStatus == 'navigating';
    final navigationStatus = isNavigating ? 'Navigasi aktif' : 'Tidak sedang navigasi';
    final statusMovement = location != null && location.speed >= 0.8 ? 'Berjalan' : 'Diam';
    final lastUpdate = location != null ? _formatTimeAgo(location.timestamp) : '3 detik lalu';
    final heading = 'Timur';
    final distance = '1.2 km';
    final confidence = 'High';
    final alert = 'Tidak ada masalah';
    final connectionStatus = location?.internetAvailable == true ? 'Online' : 'Offline';
    final gpsStatus = location?.gpsEnabled == true ? 'Aktif' : 'Tidak aktif';

    return [
      _buildSectionTitle('🎯 Tujuan realtime monitoring'),
      const SizedBox(height: 10),
      Text(
        'Tahu posisi sekarang • Tahu kondisi user • Bisa respon cepat kalau ada masalah',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textSecondary,
          height: 1.6,
        ),
      ),
      const SizedBox(height: 18),
      _buildDetailCard(
        title: 'Data realtime yang WAJIB ada',
        items: [
          'Lokasi realtime: $address',
          'Latitude: ${location?.latitude.toStringAsFixed(6) ?? '-6.914700'}',
          'Longitude: ${location?.longitude.toStringAsFixed(6) ?? '107.609800'}',
          'Akurasi GPS: $gpsAccuracy',
        ],
      ),
      const SizedBox(height: 18),
      _buildDetailCard(
        title: 'Status navigasi',
        items: [
          'Menuju: $destination',
          'ETA: 10 menit',
          'Status: $navigationStatus',
        ],
      ),
      const SizedBox(height: 18),
      _buildDetailCard(
        title: 'Status pergerakan',
        items: [
          'Status: $statusMovement',
          'Kecepatan: $speed',
          'Arah: $heading',
        ],
      ),
      const SizedBox(height: 18),
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
      const SizedBox(height: 18),
      _buildDetailCard(
        title: 'Status keamanan',
        items: [
          '⚠️ $alert',
          'Keluar rute: tidak',
          'SOS: tidak aktif',
          'GPS: $gpsStatus',
          'Internet: $connectionStatus',
        ],
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: _buildInfoTile('Baterai', battery, color: battery.endsWith('%') && int.tryParse(battery.replaceAll('%', ''))! < 20 ? Colors.red : Colors.orange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildInfoTile('Jarak ke tujuan', distance),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(child: _buildInfoTile('Koneksi', connectionStatus)),
          const SizedBox(width: 10),
          Expanded(child: _buildInfoTile('Confidence', confidence)),
        ],
      ),
      const SizedBox(height: 18),
      _buildDetailRow('Last update', lastUpdate),
      const SizedBox(height: 10),
      Text(
        'Update tiap 1–3 detik atau saat perubahan signifikan menjaga keluarga tetap yakin tanpa boros.',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textSecondary,
          height: 1.6,
        ),
      ),
    ];
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<FamilyLocation>(
        stream: _liveStream,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _latestLocation = snapshot.data;
          }
          final location = snapshot.data ?? _latestLocation;

          return Stack(
            children: [
              Positioned.fill(
                child: _buildMainMap(location),
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
                                    _buildTunaNetraInfoCard(),
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
                                        children: _buildLivePanelContent(location),
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
                              child: _buildCollapsedSheetCard(location),
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
                                    onTap: _showTunaNetraInfo,
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
                                    onTap: _showTunaNetraInfo,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        16,
                                      ),
                                      child: _buildCollapsedSheetCard(location),
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
      ),
    );
  }
}

class Trip {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final int duration; // in seconds
  final double distance; // in meters
  final String origin;
  final String destination;
  final String status; // 'completed', 'cancelled', 'off_route'
  final List<LatLng> routePoints;
  final List<TripEvent> events;

  Trip({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.distance,
    required this.origin,
    required this.destination,
    required this.status,
    required this.routePoints,
    required this.events,
  });
}

class TripEvent {
  final String type; // 'off_route', 'sos', 'stop_long', 'gps_lost'
  final DateTime timestamp;
  final String description;

  TripEvent({
    required this.type,
    required this.timestamp,
    required this.description,
  });
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
  List<Trip> _trips = [];
  Trip? _selectedTrip;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreenView(screenName: 'FamilyHistoryDetail');
    _loadDummyTrips();
  }

  void _loadDummyTrips() {
    setState(() => _isLoading = true);

    // Dummy data
    _trips = [
      Trip(
        id: '1',
        startTime: DateTime.now().subtract(const Duration(hours: 2)),
        endTime: DateTime.now().subtract(const Duration(hours: 1, minutes: 45)),
        duration: 900, // 15 minutes
        distance: 3200, // 3.2 km
        origin: 'Rumah',
        destination: 'Kampus',
        status: 'completed',
        routePoints: [
          const LatLng(-6.9147, 107.6098),
          const LatLng(-6.9150, 107.6100),
          const LatLng(-6.9160, 107.6110),
          const LatLng(-6.9170, 107.6120),
          const LatLng(-6.9180, 107.6130),
        ],
        events: [
          TripEvent(
            type: 'off_route',
            timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 50)),
            description: 'User keluar jalur sebentar',
          ),
        ],
      ),
      Trip(
        id: '2',
        startTime: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
        endTime: DateTime.now().subtract(const Duration(days: 1, hours: 2, minutes: 30)),
        duration: 1800, // 30 minutes
        distance: 4500, // 4.5 km
        origin: 'Kampus',
        destination: 'Mall',
        status: 'completed',
        routePoints: [
          const LatLng(-6.9180, 107.6130),
          const LatLng(-6.9190, 107.6140),
          const LatLng(-6.9200, 107.6150),
          const LatLng(-6.9210, 107.6160),
        ],
        events: [],
      ),
      Trip(
        id: '3',
        startTime: DateTime.now().subtract(const Duration(days: 2, hours: 1)),
        endTime: DateTime.now().subtract(const Duration(days: 2, hours: 0, minutes: 45)),
        duration: 2700, // 45 minutes
        distance: 6800, // 6.8 km
        origin: 'Mall',
        destination: 'Rumah',
        status: 'off_route',
        routePoints: [
          const LatLng(-6.9210, 107.6160),
          const LatLng(-6.9200, 107.6150),
          const LatLng(-6.9190, 107.6140),
          const LatLng(-6.9180, 107.6130),
          const LatLng(-6.9170, 107.6120),
        ],
        events: [
          TripEvent(
            type: 'off_route',
            timestamp: DateTime.now().subtract(const Duration(days: 2, hours: 0, minutes: 50)),
            description: 'User keluar jalur dan belum kembali',
          ),
          TripEvent(
            type: 'sos',
            timestamp: DateTime.now().subtract(const Duration(days: 2, hours: 0, minutes: 40)),
            description: 'Tombol SOS ditekan',
          ),
        ],
      ),
    ];

    setState(() => _isLoading = false);
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes < 60) {
      return '$minutes menit';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '$hours jam $remainingMinutes menit';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'completed':
        return 'Selesai ✅';
      case 'cancelled':
        return 'Dibatalkan ❌';
      case 'off_route':
        return 'Keluar Rute ⚠️';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'off_route':
        return Colors.orange;
      default:
        return Colors.grey;
    }
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

  Widget _buildTripCard(Trip trip) {
    final dateStr = DateFormat('dd MMM yyyy').format(trip.startTime);
    final timeStr = '${DateFormat('HH:mm').format(trip.startTime)} → ${DateFormat('HH:mm').format(trip.endTime)}';

    return GestureDetector(
      onTap: () => setState(() => _selectedTrip = trip),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.06),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    dateStr,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(trip.status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _getStatusColor(trip.status).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _getStatusText(trip.status),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: _getStatusColor(trip.status),
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
                Text(
                  '$timeStr (${_formatDuration(trip.duration)})',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
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
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.radio_button_checked,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      trip.origin,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      trip.destination,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildMiniTag(
                    '📏 ${_formatDistance(trip.distance)}',
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMiniTag(
                    '⚠️ ${trip.events.length} event',
                    color: trip.events.isEmpty ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripDetail(Trip trip) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _selectedTrip = null),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              DateFormat('dd MMM').format(trip.startTime),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getStatusColor(trip.status).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getStatusText(trip.status),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${trip.origin} → ${trip.destination}',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEEE, dd MMMM yyyy • HH:mm').format(trip.startTime),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Map
          Container(
            height: 220,
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: trip.routePoints.isNotEmpty ? trip.routePoints.first : const LatLng(-6.9147, 107.6098),
                  initialZoom: 14.5,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.my_app',
                  ),
                  if (trip.routePoints.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: trip.routePoints,
                          color: trip.status == 'off_route' ? Colors.red : AppColors.primary,
                          strokeWidth: 5.0,
                          borderColor: Colors.white,
                          borderStrokeWidth: 2.0,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      if (trip.routePoints.isNotEmpty)
                        Marker(
                          point: trip.routePoints.first,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.9),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.radio_button_checked,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      if (trip.routePoints.isNotEmpty)
                        Marker(
                          point: trip.routePoints.last,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.9),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoTile('⏱️ Durasi', _formatDuration(trip.duration)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildInfoTile('📏 Jarak', _formatDistance(trip.distance)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoTile(
                        '📊 Status',
                        _getStatusText(trip.status),
                        color: _getStatusColor(trip.status),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildInfoTile(
                        '⚠️ Event',
                        '${trip.events.length} kejadian',
                        color: trip.events.isEmpty ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Timeline
          if (trip.events.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Timeline Event',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...trip.events.map((event) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (event.type == 'sos' ? Colors.red : Colors.orange).withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (event.type == 'sos' ? Colors.red : Colors.orange).withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: event.type == 'sos' ? Colors.red : Colors.orange,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (event.type == 'sos' ? Colors.red : Colors.orange).withOpacity(0.3),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.description,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('HH:mm • dd MMM yyyy').format(event.timestamp),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    event.type == 'sos' ? Icons.warning_rounded : Icons.error_outline_rounded,
                    color: event.type == 'sos' ? Colors.red : Colors.orange,
                    size: 20,
                  ),
                ],
              ),
            )),
            const SizedBox(height: 24),
          ] else ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Perjalanan berjalan lancar tanpa kejadian khusus',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
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

              // Content
              Expanded(
                child: _selectedTrip != null
                  ? _buildTripDetail(_selectedTrip!)
                  : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _trips.isEmpty
                      ? Center(
                          child: _buildEmptyCard(
                            icon: Icons.route,
                            title: 'Belum ada riwayat',
                            subtitle: 'Riwayat perjalanan akan muncul di sini',
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            ..._trips.map(_buildTripCard),
                          ],
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
