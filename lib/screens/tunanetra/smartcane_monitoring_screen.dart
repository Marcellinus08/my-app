import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../services/tunanetra_voice_command_service.dart';

class SmartcaneMonitoringScreen extends StatefulWidget {
  const SmartcaneMonitoringScreen({super.key});

  @override
  State<SmartcaneMonitoringScreen> createState() =>
      _SmartcaneMonitoringScreenState();
}

class _SmartcaneMonitoringScreenState extends State<SmartcaneMonitoringScreen>
    with TunaNetraHomeVoiceCommandMixin {
  bool cameraActive = true;
  bool raspberryConnected = true;
  bool mlActive = true;
  String detectionMode = 'Objek + Lubang';
  String sensitivity = 'Sedang';

  final String raspberryIp = '192.168.1.24';
  final String lastSync = '2 detik lalu';
  final int lastConfidence = 87;

  final List<Map<String, String>> lastLogs = const [
    {
      'type': 'Lubang',
      'direction': 'Depan',
      'distance': '1.2 m',
      'recommendation': 'Berhenti dan geser sedikit ke kanan',
      'time': 'Baru saja',
    },
    {
      'type': 'Objek motor',
      'direction': 'Kanan',
      'distance': '2.0 m',
      'recommendation': 'Jaga arah lurus',
      'time': '1 menit lalu',
    },
    {
      'type': 'Rekomendasi',
      'direction': 'Kiri',
      'distance': '-',
      'recommendation': 'Geser ke kiri',
      'time': '2 menit lalu',
    },
  ];

  @override
  void initState() {
    super.initState();
    startHomeVoiceCommandListener();
  }

  @override
  void dispose() {
    stopHomeVoiceCommandListener();
    super.dispose();
  }

  String get _detectionModeHelperText {
    switch (detectionMode) {
      case 'Objek':
        return 'Mendeteksi objek di sekitar pengguna';
      case 'Lubang':
        return 'Memprioritaskan deteksi lubang pada jalur';
      default:
        return 'Mendeteksi objek dan lubang sekaligus';
    }
  }

  void _showTestMessage(String message) {
    debugPrint('[SMARTCANE] $message');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  TextStyle get _cardDescriptionStyle => AppTextStyles.bodySmall.copyWith(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFAFBFC),
              AppColors.primary.withValues(alpha: 0.08),
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                  child: Column(
                    children: [
                      buildStatusCard(
                        title: 'Status Kamera',
                        status: cameraActive ? 'Aktif' : 'Tidak Aktif',
                        description: 'Deteksi lingkungan',
                        icon: Icons.videocam_rounded,
                        active: cameraActive,
                      ),
                      const SizedBox(height: 16),
                      buildStatusCard(
                        title: 'Raspberry Pi',
                        status: raspberryConnected
                            ? 'Terhubung'
                            : 'Tidak Terhubung',
                        description: 'Data tongkat',
                        icon: Icons.developer_board_rounded,
                        active: raspberryConnected,
                        details: [
                          'IP: $raspberryIp',
                          'Sinkron terakhir: $lastSync',
                        ],
                      ),
                      const SizedBox(height: 16),
                      buildStatusCard(
                        title: 'Status ML',
                        status: mlActive ? 'Aktif' : 'Tidak Aktif',
                        description: 'Deteksi objek',
                        icon: Icons.psychology_rounded,
                        active: mlActive,
                        details: ['Tingkat keyakinan: $lastConfidence%'],
                      ),
                      const SizedBox(height: 16),
                      buildDetectionModeCard(),
                      const SizedBox(height: 16),
                      buildSensitivityCard(),
                      const SizedBox(height: 16),
                      _buildTestActionsCard(),
                      const SizedBox(height: 16),
                      buildDetectionLogCard(),
                    ],
                  ),
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
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.1),
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
                gradient: const LinearGradient(
                  colors: [Color(0xFFEC4899), Color(0xFFDB2777)],
                ),
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'SmartCane',
                  style: AppTextStyles.heading2.copyWith(
                    color: const Color(0xFFDB2777),
                    fontSize: 26,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Monitoring perangkat',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
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

  Widget buildStatusCard({
    required String title,
    required String status,
    required String description,
    required IconData icon,
    required bool active,
    List<String> details = const [],
  }) {
    final color = active ? AppColors.success : AppColors.error;
    final softColor = active ? AppColors.successLight : AppColors.errorLight;

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: _cardDescriptionStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _buildStatusBadge(
                label: status,
                color: color,
                backgroundColor: softColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 66),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      active ? 'Aktif' : 'Tidak Aktif',
                      style: AppTextStyles.caption.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: details.map(_buildInfoChip).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge({
    required String label,
    required Color color,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget buildDetectionModeCard() {
    return _buildOptionCard(
      title: 'Mode Deteksi',
      subtitle: 'Pilih jenis deteksi',
      icon: Icons.visibility_rounded,
      children: [
        _buildChoiceWrap(
          options: const ['Objek', 'Lubang', 'Objek + Lubang'],
          selectedValue: detectionMode,
          onSelected: (value) {
            setState(() {
              detectionMode = value;
            });
          },
        ),
        const SizedBox(height: 12),
        Text(_detectionModeHelperText, style: _cardDescriptionStyle),
      ],
    );
  }

  Widget buildSensitivityCard() {
    const descriptions = {
      'Rendah': 'Peringatan hanya untuk objek sangat dekat',
      'Sedang': 'Seimbang untuk penggunaan harian',
      'Tinggi': 'Lebih sensitif terhadap objek dan lubang',
    };

    return _buildOptionCard(
      title: 'Sensitivitas',
      subtitle: 'Atur tingkat sensitivitas',
      icon: Icons.tune_rounded,
      children: [
        _buildChoiceWrap(
          options: const ['Rendah', 'Sedang', 'Tinggi'],
          selectedValue: sensitivity,
          onSelected: (value) {
            setState(() {
              sensitivity = value;
            });
          },
        ),
        const SizedBox(height: 12),
        Text(descriptions[sensitivity] ?? '-', style: _cardDescriptionStyle),
      ],
    );
  }

  Widget buildDetectionLogCard() {
    return _buildOptionCard(
      title: 'Catatan Deteksi Terakhir',
      subtitle: 'Riwayat deteksi terbaru',
      icon: Icons.history_rounded,
      children: [
        if (lastLogs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('Belum ada deteksi', style: _cardDescriptionStyle),
          )
        else
          ...lastLogs.map(_buildDetectionLogItem),
      ],
    );
  }

  Widget buildTestButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: AppTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildTestActionsCard() {
    return _buildOptionCard(
      title: 'Tes Perangkat',
      subtitle: 'Uji fungsi perangkat SmartCane',
      icon: Icons.touch_app_rounded,
      children: [
        Column(
          children: [
            buildTestButton(
              label: 'Tes Kamera',
              icon: Icons.videocam_rounded,
              onPressed: () => _showTestMessage('Tes kamera dijalankan'),
            ),
            const SizedBox(height: 10),
            buildTestButton(
              label: 'Tes Suara',
              icon: Icons.volume_up_rounded,
              onPressed: () => _showTestMessage('Tes suara dijalankan'),
            ),
            const SizedBox(height: 10),
            buildTestButton(
              label: 'Tes Getar',
              icon: Icons.vibration_rounded,
              onPressed: () => _showTestMessage('Tes getar dijalankan'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildOptionCard({
    required String title,
    String? subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: _cardDescriptionStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildChoiceWrap({
    required List<String> options,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((option) {
        final selected = option == selectedValue;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(option),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    option,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: selected ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInfoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.10)),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildDetectionLogItem(Map<String, String> log) {
    final type = log['type'] ?? '-';
    final direction = log['direction'] ?? '-';
    final distance = log['distance'] ?? '-';
    final recommendation = log['recommendation'] ?? '';
    final time = log['time'] ?? '-';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EEF5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        type,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE8EEF5)),
                      ),
                      child: Text(
                        time,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '$direction - $distance',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (recommendation.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    recommendation,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
