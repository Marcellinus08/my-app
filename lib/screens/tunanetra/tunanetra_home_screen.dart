import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import '../../utils/constants.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../services/weather_service.dart';

class TunaNetraHomeScreen extends StatefulWidget {
  const TunaNetraHomeScreen({super.key});

  @override
  State<TunaNetraHomeScreen> createState() => _TunaNetraHomeScreenState();
}

class _TunaNetraHomeScreenState extends State<TunaNetraHomeScreen> 
    with TickerProviderStateMixin {
  bool _isSmartcaneConnected = true;
  double _smartcaneBattery = 85;
  String _userName = 'Pengguna';
  WeatherData? _weatherData;
  bool _isLoadingWeather = true;
  
  late AnimationController _fadeController;
  late AnimationController _rotationController;
  late Animation<double> _fadeAnimation;
  late Stream<String> _userNameStream;
  late FirebaseFirestore _firestore;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _firestore = FirebaseFirestore.instance;
    _setupUserNameStream();
    _loadWeather();
  }

  void _setupUserNameStream() {
    final authService = AuthService();
    final uid = authService.currentUserId;
    
    print('🔍 Home Screen - User UID: $uid');
    
    if (uid != null) {
      _userNameStream = _firestore
          .collection('users')
          .doc(uid)
          .snapshots()
          .map((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>?;
          final name = data?['name'] as String? ?? 'Pengguna';
          print('📝 User name updated: $name');
          return name;
        }
        print('⚠️ User document does not exist');
        return 'Pengguna';
      });
      
      // Subscribe to stream changes
      _userNameStream.listen((newName) {
        if (mounted) {
          setState(() {
            _userName = newName;
          });
        }
      });
    } else {
      print('❌ User UID is null');
      _userNameStream = Stream.value('Pengguna');
    }
  }

  Future<void> _loadWeather() async {
    try {
      final weatherService = WeatherService();
      final weather = await weatherService.getWeatherByLocation();
      
      if (mounted) {
        setState(() {
          _weatherData = weather;
          _isLoadingWeather = false;
        });
      }
    } catch (e) {
      print('❌ Error loading weather: $e');
      if (mounted) {
        setState(() {
          _isLoadingWeather = false;
        });
      }
    }
  }

  /// Get battery color based on level
  Color _getBatteryColor() {
    if (_smartcaneBattery >= 50) {
      return Colors.green;
    } else if (_smartcaneBattery >= 20) {
      return Colors.amber;
    } else {
      return Colors.red;
    }
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _fadeController.forward();
  }

  void _navigateToNavigation() {
    Navigator.pushNamed(context, AppRoutes.tunaNetraNavigation);
  }

  void _navigateToBluetooth() {
    Navigator.pushNamed(context, AppRoutes.tunaNetraBluetooth);
  }

  void _navigateToEbook() {
    Navigator.pushNamed(context, AppRoutes.tunaNetraEbook);
  }

  void _navigateToSmartcane() {
    Navigator.pushNamed(context, AppRoutes.tunaNetraSmartcane);
  }

  void _navigateToSettings() {
    Navigator.pushNamed(context, AppRoutes.tunaNetraSettings);
  }

  void _triggerEmergency() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.warning_rounded, size: 60, color: Color(0xFFEF4444)),
              ),
              const SizedBox(height: 20),
              const Text(
                'DARURAT',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'Mengirim lokasi Anda ke kontak darurat...',
                style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('BATAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
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
        child: Stack(
          children: [
            // Animated rotating circles background
            ...List.generate(4, (index) {
              return AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  final angle = _rotationController.value * 2 * math.pi + (index * math.pi / 2);
                  final size = 120.0 + (index * 40);
                  final distance = 150.0 + (index * 30);
                  
                  return Positioned(
                    left: MediaQuery.of(context).size.width / 2 + 
                          math.cos(angle) * distance - size / 2,
                    top: MediaQuery.of(context).size.height / 3 + 
                         math.sin(angle) * distance - size / 2,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.primaryLight.withOpacity(0.06),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
            
            // Main content with fade animation
            FadeTransition(
              opacity: _fadeAnimation,
              child: _buildMainContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return SafeArea(
      child: Column(
        children: [
          // Clean & Elegant Header
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0D47A1),
                  const Color(0xFF1565C0),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0D47A1).withOpacity(0.2),
                  blurRadius: 25,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Greeting + Name + Weather
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selamat Datang',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _userName,
                        style: AppTextStyles.heading1.copyWith(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                      ),
                      const SizedBox(height: 6),
                      // Weather Info
                      if (_isLoadingWeather)
                        SizedBox(
                          height: 18,
                          child: Center(
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ),
                          ),
                        )
                      else if (_weatherData != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${WeatherService.getWeatherEmoji(_weatherData!.weatherCondition)} ${_weatherData!.temperature.toStringAsFixed(1)}°C',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '|',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 9,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_weatherData!.humidity}%',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 9,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '|',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 9,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_weatherData!.windSpeed.toStringAsFixed(0)} km/h',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Right: Battery Indicator
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const SizedBox(height: 2),
                      // Modern Battery Icon with Fill
                      Container(
                      width: 52,
                      height: 60,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withOpacity(0.8),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        children: [
                          // Battery top bump
                          Positioned(
                            top: -4,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.8),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(2),
                                  topRight: Radius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          // Battery fill with gradient
                          Container(
                            width: double.infinity,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Stack(
                              children: [
                                // Background
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                // Fill based on battery level
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: double.infinity,
                                    height: (_smartcaneBattery / 100) * 60,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          _getBatteryColor(),
                                          _getBatteryColor().withOpacity(0.6),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                                // Percentage text overlay
                                Center(
                                  child: Text(
                                    '${_smartcaneBattery.toInt()}%',
                                    style: AppTextStyles.heading2.copyWith(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 3,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Status text below
                    Text(
                      _isSmartcaneConnected ? 'Terhubung' : 'Offline',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: _isSmartcaneConnected
                            ? Colors.green.withOpacity(0.9)
                            : Colors.orange.withOpacity(0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                  ],
                ),
                ),
              ],
            ),
          ),
              
              // Main Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        children: [
                          _ModernMenuCard(
                            icon: Icons.map_rounded,
                            title: 'Navigasi',
                            gradient: AppColors.primaryGradient,
                            onTap: _navigateToNavigation,
                            onHover: () {},
                          ),
                          _ModernMenuCard(
                            icon: Icons.bluetooth_rounded,
                            title: 'Bluetooth',
                            gradient: AppColors.successGradient,
                            onTap: _navigateToBluetooth,
                            onHover: () {},
                          ),
                          _ModernMenuCard(
                            icon: Icons.book_rounded,
                            title: 'Buku Panduan',
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                            ),
                            onTap: _navigateToEbook,
                            onHover: () {},
                          ),
                          _ModernMenuCard(
                            icon: Icons.accessibility_new_rounded,
                            title: 'SmartCane',
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEC4899), Color(0xFFDB2777)],
                            ),
                            onTap: _navigateToSmartcane,
                            onHover: () {},
                          ),
                          _ModernMenuCard(
                            icon: Icons.settings_rounded,
                            title: 'Pengaturan',
                            gradient: const LinearGradient(
                              colors: [Color(0xFF64748B), Color(0xFF475569)],
                            ),
                            onTap: _navigateToSettings,
                            onHover: () {},
                          ),
                          _ModernMenuCard(
                            icon: Icons.warning_rounded,
                            title: 'Darurat',
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                            ),
                            onTap: _triggerEmergency,
                            onHover: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _rotationController.dispose();
    super.dispose();
  }
}

class _ModernMenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final LinearGradient gradient;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _ModernMenuCard({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onHover: (hovering) {
          if (hovering) onHover();
        },
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white,
                Colors.white.withOpacity(0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: gradient.colors.first.withOpacity(0.2),
                blurRadius: 25,
                spreadRadius: 0,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                spreadRadius: -5,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: gradient.colors.first.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.colors.first.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(icon, size: 42, color: Colors.white),
              ),
              const SizedBox(height: 14),
              ShaderMask(
                shaderCallback: (bounds) => gradient.createShader(bounds),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
