import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class SmartcaneMonitoringScreen extends StatefulWidget {
  const SmartcaneMonitoringScreen({super.key});

  @override
  State<SmartcaneMonitoringScreen> createState() =>
      _SmartcaneMonitoringScreenState();
}

class _SmartcaneMonitoringScreenState extends State<SmartcaneMonitoringScreen>
    with TickerProviderStateMixin {
  bool _isConnected = true;
  double _batteryLevel = 85;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.primary,
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
                              'SmartCane',
                              style: AppTextStyles.heading2.copyWith(
                                color: Colors.white,
                                fontSize: 26,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Status & Monitoring',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Connection Status Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _isConnected
                                ? [Colors.white, Colors.white.withOpacity(0.95)]
                                : [Colors.white, Colors.white.withOpacity(0.95)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: _isConnected
                                  ? AppColors.success.withOpacity(0.2)
                                  : Colors.red.withOpacity(0.2),
                              blurRadius: 25,
                              offset: const Offset(0, 10),
                            ),
                          ],
                          border: Border.all(
                            color: _isConnected
                                ? AppColors.success.withOpacity(0.3)
                                : Colors.red.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Pulse Animation for Connected Status
                            if (_isConnected)
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) {
                                  return Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 100 +
                                            (_pulseController.value * 40),
                                        height: 100 +
                                            (_pulseController.value * 40),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.success.withOpacity(
                                              0.1 -
                                                  (_pulseController.value *
                                                      0.1)),
                                        ),
                                      ),
                                      Container(
                                        width: 100,
                                        height: 100,
                                        decoration: BoxDecoration(
                                          gradient:
                                              AppColors.successGradient,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.success
                                                  .withOpacity(0.4),
                                              blurRadius: 20,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.accessibility_new_rounded,
                                          color: Colors.white,
                                          size: 48,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              )
                            else
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFEF4444),
                                      Color(0xFFDC2626)
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFEF4444)
                                          .withOpacity(0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                            const SizedBox(height: 20),
                            Text(
                              _isConnected ? 'Terhubung' : 'Terputus',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: _isConnected
                                    ? AppColors.success
                                    : Colors.red,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isConnected
                                  ? 'SmartCane siap digunakan'
                                  : 'Tidak ada koneksi SmartCane',
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _isConnected
                                    ? AppColors.success.withOpacity(0.1)
                                    : Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _isConnected
                                    ? 'ID: SC-2024-001'
                                    : 'Coba hubungkan kembali',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _isConnected
                                      ? AppColors.success
                                      : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Battery Status
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.white, Colors.white.withOpacity(0.95)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Baterai',
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: _batteryLevel > 50
                                        ? AppColors.successGradient
                                        : _batteryLevel > 20
                                            ? const LinearGradient(
                                                colors: [
                                                  Color(0xFFF59E0B),
                                                  Color(0xFFD97706)
                                                ],
                                              )
                                            : const LinearGradient(
                                                colors: [
                                                  Color(0xFFEF4444),
                                                  Color(0xFFDC2626)
                                                ],
                                              ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${_batteryLevel.toInt()}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _batteryLevel / 100,
                                minHeight: 12,
                                backgroundColor:
                                    AppColors.primary.withOpacity(0.1),
                                valueColor: AlwaysStoppedAnimation(
                                  _batteryLevel > 50
                                      ? AppColors.success
                                      : _batteryLevel > 20
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFFEF4444),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Features
                      _buildFeatureSelector(),
                      const SizedBox(height: 24),
                      
                      // Connection Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() => _isConnected = !_isConnected);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _isConnected
                                        ? 'SmartCane terhubung'
                                        : 'SmartCane terputus',
                                  ),
                                  backgroundColor: _isConnected
                                      ? AppColors.success
                                      : Colors.red,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: _isConnected
                                    ? AppColors.successGradient
                                    : const LinearGradient(
                                        colors: [
                                          Color(0xFF3B82F6),
                                          Color(0xFF2563EB)
                                        ],
                                      ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: _isConnected
                                        ? AppColors.success.withOpacity(0.3)
                                        : const Color(0xFF3B82F6)
                                            .withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  _isConnected
                                      ? 'Putuskan Koneksi'
                                      : 'Hubungkan SmartCane',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildFeatureSelector() {
    final features = [
      {'name': 'Navigasi', 'icon': Icons.navigation_rounded},
      {'name': 'Pendeteksi', 'icon': Icons.radar_rounded},
      {'name': 'Getaran', 'icon': Icons.vibration_rounded},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fitur Aktif',
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          physics: const NeverScrollableScrollPhysics(),
          children: features
              .map((feature) => Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Fitur ${feature['name']} aktif',
                            ),
                            backgroundColor: AppColors.primary,
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white,
                              Colors.white.withOpacity(0.95),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                          border: Border.all(
                            color: AppColors.success.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: AppColors.successGradient,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                feature['icon'] as IconData,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              feature['name'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
