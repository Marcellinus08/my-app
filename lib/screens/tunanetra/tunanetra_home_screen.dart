import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import '../../utils/constants.dart';
import '../../services/auth_service.dart';
import '../../services/live_tracking_service.dart';
import '../../services/notification_service.dart';
import '../../services/pairing_service.dart';
import '../../services/sos_service.dart';
import '../../services/weather_service.dart';

class TunaNetraHomeScreen extends StatefulWidget {
  const TunaNetraHomeScreen({super.key});

  @override
  State<TunaNetraHomeScreen> createState() => _TunaNetraHomeScreenState();
}

class _TunaNetraHomeScreenState extends State<TunaNetraHomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String _userName = 'Pengguna';
  WeatherData? _weatherData;
  bool _isLoadingWeather = true;
  bool _isSendingSos = false;
  final LiveTrackingService _liveTrackingService = LiveTrackingService();
  final PairingService _pairingService = PairingService();
  final SosService _sosService = SosService();
  StreamSubscription<User?>? _authStateSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pairingRequestSub;
  final Set<String> _shownPairingRequestIds = {};
  bool _isPairingDialogOpen = false;

  late AnimationController _fadeController;
  late AnimationController _rotationController;
  late Animation<double> _fadeAnimation;
  late Stream<String> _userNameStream;
  late FirebaseFirestore _firestore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAnimations();
    _firestore = FirebaseFirestore.instance;
    _setupUserNameStream();
    _subscribeToPairingRequests();
    _loadWeather();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _liveTrackingService.startHomeLocationTracking();
      NotificationService.instance.requestNotificationPermission().catchError(
        (error) {
          debugPrint(
            '[TunaNetraHome] Notification permission request failed: $error',
          );
        },
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _liveTrackingService.startHomeLocationTracking();
    }
  }

  void _setupUserNameStream() {
    final authService = AuthService();
    final uid = authService.currentUserId;

    print('🔍 Home Screen - User UID: $uid');

    if (uid != null) {
      _userNameStream = _firestore.collection('users').doc(uid).snapshots().map(
        (snapshot) {
          if (snapshot.exists) {
            final data = snapshot.data();
            final name = data?['name'] as String? ?? 'Pengguna';
            print('📝 User name updated: $name');
            return name;
          }
          print('⚠️ User document does not exist');
          return 'Pengguna';
        },
      );

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
      final cachedWeather = await weatherService.getCachedWeather();
      if (mounted && cachedWeather != null) {
        setState(() {
          _weatherData = cachedWeather;
        });
      }

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

  void _initializeAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _fadeController.forward();
  }

  void _navigateToNavigation() {
    _liveTrackingService.stopHomeLocationTracking();
    Navigator.pushNamed(context, AppRoutes.tunaNetraNavigation);
  }

  void _navigateToBluetooth() {
    _showComingSoonSnackBar();
    // Navigator.pushNamed(context, AppRoutes.tunaNetraBluetooth);
  }

  void _navigateToEbook() {
    _showComingSoonSnackBar();
    // Navigator.pushNamed(context, AppRoutes.tunaNetraEbook);
  }

  void _navigateToSmartcane() {
    _showComingSoonSnackBar();
    // Navigator.pushNamed(context, AppRoutes.tunaNetraSmartcane);
  }

  void _navigateToSettings() {
    Navigator.pushNamed(context, AppRoutes.tunaNetraSettings);
  }

  void _showComingSoonSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fitur ini akan segera hadir'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _triggerEmergency() async {
    if (_isSendingSos) return;

    setState(() {
      _isSendingSos = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.error),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                'Mengirim SOS...',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      await _sosService.sendSosAlert();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS berhasil dikirim ke keluarga'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengirim SOS: ${_formatSosError(e)}'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingSos = false;
        });
      }
    }
  }

  void _subscribeToPairingRequests() {
    final currentUid = AuthService().currentUserId;
    if (currentUid != null && currentUid.isNotEmpty) {
      _startPairingRequestListener(currentUid);
    }

    _authStateSub?.cancel();
    _authStateSub = AuthService().authStateChanges.listen((user) {
      final uid = user?.uid;
      if (uid == null || uid.isEmpty) {
        _pairingRequestSub?.cancel();
        _pairingRequestSub = null;
        return;
      }

      _startPairingRequestListener(uid);
    });
  }

  void _startPairingRequestListener(String uid) {
    _pairingRequestSub?.cancel();
    _pairingRequestSub = _pairingService
        .watchPendingRequestsForTunaNetra(uid)
        .listen(
          (snapshot) {
            if (!mounted || _isPairingDialogOpen) return;

            for (final doc in snapshot.docs) {
              if (_shownPairingRequestIds.contains(doc.id)) continue;
              _shownPairingRequestIds.add(doc.id);
              _showPairingRequestDialog(doc.id, doc.data());
              break;
            }
          },
          onError: (error) {
            debugPrint(
              '[TunaNetraHome] Pairing request listener error: $error',
            );
          },
        );
  }

  Future<void> _showPairingRequestDialog(
    String requestId,
    Map<String, dynamic> request,
  ) async {
    _isPairingDialogOpen = true;
    final familyName = (request['familyName'] as String?)?.trim();
    final familyEmail = (request['familyEmail'] as String?)?.trim();
    final displayName = familyName?.isNotEmpty == true
        ? familyName!
        : (familyEmail?.isNotEmpty == true ? familyEmail! : 'Keluarga');

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Konfirmasi Keluarga',
          style: AppTextStyles.heading3.copyWith(fontWeight: FontWeight.w800),
        ),
        content: Text(
          '$displayName ingin terhubung dan memonitor akun Anda.',
          style: AppTextStyles.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Tolak'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Terima'),
          ),
        ],
      ),
    );

    if (!mounted || accepted == null) {
      _isPairingDialogOpen = false;
      return;
    }

    try {
      await _pairingService.respondToPairingRequest(
        requestId: requestId,
        accepted: accepted,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? 'Keluarga berhasil terhubung'
                : 'Permintaan keluarga ditolak',
          ),
          backgroundColor: accepted ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      _isPairingDialogOpen = false;
    }
  }

  String _formatSosError(Object error) {
    return error.toString().replaceAll('Exception: ', '');
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
                  final angle =
                      _rotationController.value * 2 * math.pi +
                      (index * math.pi / 2);
                  final size = 120.0 + (index * 40);
                  final distance = 150.0 + (index * 30);

                  return Positioned(
                    left:
                        MediaQuery.of(context).size.width / 2 +
                        math.cos(angle) * distance -
                        size / 2,
                    top:
                        MediaQuery.of(context).size.height / 3 +
                        math.sin(angle) * distance -
                        size / 2,
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
            FadeTransition(opacity: _fadeAnimation, child: _buildMainContent()),
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
                colors: [const Color(0xFF0D47A1), const Color(0xFF1565C0)],
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
              crossAxisAlignment: CrossAxisAlignment.center,
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
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _userName,
                            maxLines: 1,
                            style: AppTextStyles.heading1.copyWith(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Weather Info
                      if (_weatherData != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
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
                            if (_isLoadingWeather)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white.withOpacity(0.6),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        )
                      else if (_isLoadingWeather)
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
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Right: Battery Indicator
                SizedBox(
                  width: 52,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
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
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
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
                                  // Placeholder until SmartCane battery data is available.
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      width: double.infinity,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.14),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                  Center(
                                    child: Text(
                                      '?',
                                      style: AppTextStyles.heading2.copyWith(
                                        color: Colors.white,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black.withOpacity(
                                              0.3,
                                            ),
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
                        title: 'SOS',
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
    WidgetsBinding.instance.removeObserver(this);
    _liveTrackingService.stopHomeLocationTracking();
    _authStateSub?.cancel();
    _pairingRequestSub?.cancel();
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
              colors: [Colors.white, Colors.white.withOpacity(0.95)],
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
