import '../../main.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import '../../utils/constants.dart';
import '../../services/auth_service.dart';
import '../../services/core_permission_service.dart';
import '../../services/live_tracking_service.dart';
import '../../services/pairing_service.dart';
import '../../services/sos_service.dart';
import '../../services/smart_cane_ble_service.dart';
import '../../services/weather_service.dart';
import '../../services/stt_service.dart';
import '../../services/tts_service.dart';
import '../../services/tunanetra_voice_command_service.dart';

class TunaNetraHomeScreen extends StatefulWidget {
  const TunaNetraHomeScreen({super.key});

  @override
  State<TunaNetraHomeScreen> createState() => _TunaNetraHomeScreenState();
}

class _TunaNetraHomeScreenState extends State<TunaNetraHomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  static bool _hasSpokenWelcomeThisSession = false;

  String _userName = 'Pengguna';
  WeatherData? _weatherData;
  bool _isLoadingWeather = true;
  bool _isSendingSos = false;
  final LiveTrackingService _liveTrackingService = LiveTrackingService();
  final PairingService _pairingService = PairingService();
  final SosService _sosService = SosService();
  StreamSubscription<User?>? _authStateSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pairingRequestSub;
  Timer? _weatherRefreshTimer;
  final Set<String> _shownPairingRequestIds = {};
  bool _isPairingDialogOpen = false;
  final TTSService _ttsService = TTSService();
  final STTService _sttService = STTService();
  bool _hasSpoken = _hasSpokenWelcomeThisSession;
  bool _isSpeaking = false;
  bool _initialPermissionFlowDone = false;
  bool _locationFeaturesStarted = false;
  bool _announceHomeOpenedFromVoice = false;
  bool _hasAnnouncedHomeOpened = false;
  bool _homeSttActive = false;
  bool _homeSttStarting = false;
  Future<void>? _sosStatusAnnouncement;
  StreamSubscription<SmartCaneButtonEvent>? _smartCaneButtonSubscription;
  StreamSubscription<SmartCaneBatteryData>? _smartCaneBatterySubscription;
  SmartCaneBatteryData? _latestSmartCaneBatteryData;

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
    _smartCaneButtonSubscription = SmartCaneBleService
        .instance
        .buttonEventStream
        .listen(_handleSmartCaneButtonEvent);
    _latestSmartCaneBatteryData =
        SmartCaneBleService.instance.latestBatteryData;
    _smartCaneBatterySubscription = SmartCaneBleService
        .instance
        .batteryDataStream
        .listen(_handleSmartCaneBatteryData);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await CorePermissionService().ensureTunaNetraCorePermissions(
        onLocationPermissionHandled: (_) async {
          if (!mounted) return;
          _startLocationFeatures();
        },
      );
      if (!mounted) return;
      _initialPermissionFlowDone = true;
      _speakIfReady();
    });
  }

  void _startLocationFeatures() {
    if (_locationFeaturesStarted) return;
    _locationFeaturesStarted = true;
    _loadWeather();
    _startWeatherRefreshTimer();
    _liveTrackingService.startHomeLocationTracking();
  }

  void _startWeatherRefreshTimer() {
    _weatherRefreshTimer?.cancel();
    _weatherRefreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _loadWeather(speakWhenReady: false);
    });
  }

  Future<void> speakSafe(String text) async {
    _isSpeaking = true;
    await _ttsService.speak(text);
    _isSpeaking = false;
  }

  void _handleSmartCaneBatteryData(SmartCaneBatteryData data) {
    if (!mounted) return;
    setState(() {
      _latestSmartCaneBatteryData = data;
    });
  }

  int? get _smartCaneBatteryPercentage =>
      _latestSmartCaneBatteryData?.percentage;

  String get _smartCaneBatteryLabel {
    final percentage = _smartCaneBatteryPercentage;
    if (percentage == null) return '?';
    return '$percentage%';
  }

  double get _smartCaneBatteryFillHeight {
    final percentage = _smartCaneBatteryPercentage;
    if (percentage == null) return 44;
    return 44 * math.max(0.08, percentage / 100);
  }

  List<Color> get _smartCaneBatteryGradient {
    final percentage = _smartCaneBatteryPercentage;
    if (percentage == null) {
      return [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.18)];
    }
    if (percentage <= 20) {
      return const [Color(0xFFEF4444), Color(0xFFF97316)];
    }
    if (percentage <= 40) {
      return const [Color(0xFFF59E0B), Color(0xFFFBBF24)];
    }
    return const [Color(0xFF22C55E), Color(0xFF86EFAC)];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is Map && arguments['announceHomeOpened'] == true) {
      _announceHomeOpenedFromVoice = true;
    }
  }

  @override
  void didPopNext() async {
    print("🔙 Balik ke HomeScreen");

    await _stopHomeStt();

    final sosStatusAnnouncement = _sosStatusAnnouncement;
    if (sosStatusAnnouncement != null) {
      await sosStatusAnnouncement;
    }

    await speakSafe("Kamu kembali ke halaman utama");
  }

  @override
  void didPushNext() {
    _stopHomeStt();
  }

  void _handleCommand(String command) async {
    await _stopHomeStt();

    if (TunaNetraVoiceCommands.isHomeCommand(command)) {
      await speakSafe("Kamu sudah berada di halaman utama");
    } else if (command.contains("cuaca")) {
      await _speakCurrentWeather();
    } else if (command.contains("bluetooth")) {
      await speakSafe("Membuka bluetooth");
      Navigator.pushNamed(context, AppRoutes.tunaNetraBluetooth);
    } else if (TunaNetraVoiceCommands.isSosCommand(command)) {
      await _triggerEmergency();
    } else if (command.contains("navigasi")) {
      await speakSafe("Membuka navigasi");
      Navigator.pushNamed(context, AppRoutes.tunaNetraNavigation);
    } else if (command.contains("ebook") || command.contains("buku panduan")) {
      await speakSafe("Membuka buku panduan");
      Navigator.pushNamed(context, AppRoutes.tunaNetraEbook);
    } else if (command.contains("tongkat pintar")) {
      await speakSafe("Membuka pengaturan smartcane");
      Navigator.pushNamed(context, AppRoutes.tunaNetraSmartcane);
    } else if (command.contains("pengaturan")) {
      await speakSafe("Membuka pengaturan");
      Navigator.pushNamed(context, AppRoutes.tunaNetraSettings);
    } else {
      await speakSafe("Perintah tidak dikenali");
    }
  }

  void _startListening() {
    if (_isSpeaking || _homeSttStarting || _homeSttActive || !mounted) return;

    _homeSttStarting = true;

    _sttService
        .startListening(
          (result) {
            if (_isSpeaking) return;

            final text = result.toString().toLowerCase();

            if (text.length < 15 && !_isKnownHomeVoiceCommand(text)) {
              return;
            }

            print("🎤 $text");

            _handleCommand(text);
          },
          onStatus: (status) {
            _homeSttActive = status == 'listening';
          },
          onError: (_) {
            _homeSttActive = false;
          },
        )
        .whenComplete(() {
          _homeSttStarting = false;
        });
  }

  Future<void> _stopHomeStt() async {
    _homeSttActive = false;
    _homeSttStarting = false;
    await _sttService.stopListening();
  }

  bool _isKnownHomeVoiceCommand(String text) {
    return TunaNetraVoiceCommands.isHomeCommand(text) ||
        text.contains("cuaca") ||
        text.contains("bluetooth") ||
        text.contains("navigasi") ||
        text.contains("ebook") ||
        text.contains("buku panduan") ||
        text.contains("tongkat pintar") ||
        text.contains("smartcane") ||
        text.contains("pengaturan") ||
        TunaNetraVoiceCommands.isSosCommand(text);
  }

  void _speakIfReady() async {
    if (!_initialPermissionFlowDone) return;
    if (_isSpeaking) return;

    if (_announceHomeOpenedFromVoice && !_hasAnnouncedHomeOpened) {
      _hasAnnouncedHomeOpened = true;
      await _stopHomeStt();
      await speakSafe("Halaman utama dibuka");
      return;
    }

    if (_hasSpoken) {
      return;
    }

    if (_weatherData != null && _userName.isNotEmpty) {
      _hasSpoken = true;
      _hasSpokenWelcomeThisSession = true;

      final cuaca = _weatherData!;
      final text = "Selamat datang $_userName. ${_formatWeatherSpeech(cuaca)}";

      await _stopHomeStt();
      _isSpeaking = true;
      try {
        await TTSService().speak(text);
      } finally {
        _isSpeaking = false;
      }
    }
  }

  Future<void> _handleSmartCaneButtonEvent(SmartCaneButtonEvent event) async {
    debugPrint('[SMARTCANE_BUTTON] Home menerima event: ${event.type}');
    if (!mounted) return;

    if (event.isVoiceAssistantStop) {
      debugPrint('[SMARTCANE_BUTTON] Home mematikan STT');
      await _stopHomeStt();
      return;
    }

    if (event.isSos) {
      debugPrint('[SMARTCANE_BUTTON] Home mengirim SOS');
      await _triggerEmergency();
      return;
    }

    if (!event.isVoiceAssistantStart) return;

    await _stopHomeStt();

    if (!mounted) return;
    debugPrint('[SMARTCANE_BUTTON] Home menyalakan STT');
    _startListening();
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
          _speakIfReady();
        }
      });
    } else {
      print('❌ User UID is null');
      _userNameStream = Stream.value('Pengguna');
    }
  }

  Future<void> _loadWeather({bool speakWhenReady = true}) async {
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
        if (speakWhenReady) {
          _speakIfReady();
        }
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

  String _formatWeatherSpeech(WeatherData weather) {
    return "Cuaca hari ini ${weather.temperature.toStringAsFixed(0)} derajat, "
        "kelembapan ${weather.humidity} persen, "
        "kecepatan angin ${weather.windSpeed.toStringAsFixed(0)} kilometer per jam.";
  }

  Future<void> _speakCurrentWeather() async {
    final weather = _weatherData;
    if (weather != null) {
      await speakSafe(_formatWeatherSpeech(weather));
    } else {
      await speakSafe(
        "Data cuaca belum tersedia. Mengambil data cuaca terbaru",
      );
      await _loadWeather(speakWhenReady: false);
      if (_weatherData != null) {
        await speakSafe(_formatWeatherSpeech(_weatherData!));
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

  Future<void> _triggerEmergency() async {
    if (_isSendingSos) return;
    if (!TunaNetraVoiceCommands.claimSosTrigger()) return;

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
      await speakSafe('Mengirim SOS darurat');
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
      _queueSosStatusAnnouncement('SOS berhasil dikirim ke keluarga');
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
      _queueSosStatusAnnouncement('SOS gagal dikirim');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingSos = false;
        });
      }
    }
  }

  void _queueSosStatusAnnouncement(String message) {
    final announcement = _announceSosStatus(message);
    _sosStatusAnnouncement = announcement;
    unawaited(announcement);
  }

  Future<void> _announceSosStatus(String message) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) {
      _sosStatusAnnouncement = null;
      return;
    }
    try {
      await speakSafe(message);
    } finally {
      _sosStatusAnnouncement = null;
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
                SizedBox(
                  width: 42,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 38,
                        height: 56,
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            Positioned(
                              top: 0,
                              child: Container(
                                width: 14,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.85),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(2),
                                    topRight: Radius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 5,
                              left: 2,
                              right: 2,
                              bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.85),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 5),
                              width: 34,
                              height: 51,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                children: [
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      width: double.infinity,
                                      height: _smartCaneBatteryFillHeight,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: _smartCaneBatteryGradient,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Center(
                                    child: Text(
                                      _smartCaneBatteryLabel,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: Colors.white,
                                        fontSize:
                                            _latestSmartCaneBatteryData == null
                                            ? 24
                                            : 13,
                                        fontWeight: FontWeight.w900,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black.withOpacity(
                                              0.35,
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
    _weatherRefreshTimer?.cancel();
    _smartCaneButtonSubscription?.cancel();
    _smartCaneBatterySubscription?.cancel();
    _authStateSub?.cancel();
    _stopHomeStt();
    routeObserver.unsubscribe(this);
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
