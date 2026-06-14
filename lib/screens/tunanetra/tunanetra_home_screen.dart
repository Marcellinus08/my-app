import '../../main.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../utils/constants.dart';
import '../../utils/app_feedback.dart';
import '../../services/auth_service.dart';
import '../../services/core_permission_service.dart';
import '../../services/live_tracking_service.dart';
import '../../services/navigation_history_service.dart';
import '../../services/pairing_service.dart';
import '../../services/realtime_live_tracking_service.dart';
import '../../services/sos_service.dart';
import '../../services/smart_cane_ble_service.dart';
import '../../services/weather_service.dart';
import '../../services/stt_service.dart';
import '../../services/tts_service.dart';
import '../../services/tunanetra_voice_command_service.dart';
import '../../widgets/app_dialog.dart';

class TunaNetraHomeScreen extends StatefulWidget {
  const TunaNetraHomeScreen({super.key});

  @override
  State<TunaNetraHomeScreen> createState() => _TunaNetraHomeScreenState();
}

class _TunaNetraHomeScreenState extends State<TunaNetraHomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  static final Guid _smartCaneServiceUuid = Guid(
    '0000a001-0000-1000-8000-00805f9b34fb',
  );
  static final Guid _pairingCharacteristicUuid = Guid(
    '0000a003-0000-1000-8000-00805f9b34fb',
  );

  String _userName = 'Pengguna';
  WeatherData? _weatherData;
  bool _isLoadingWeather = true;
  bool _isSendingSos = false;
  final SmartCaneBleService _bleService = SmartCaneBleService.instance;
  final LiveTrackingService _liveTrackingService = LiveTrackingService();
  final NavigationHistoryService _navigationHistoryService =
      NavigationHistoryService();
  final PairingService _pairingService = PairingService();
  final SosService _sosService = SosService();
  final TextEditingController _homeCaneCodeController = TextEditingController();
  final TextEditingController _homeCanePinController = TextEditingController();
  final Map<DeviceIdentifier, ScanResult> _homeScanResults = {};
  StreamSubscription<User?>? _authStateSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pairingRequestSub;
  StreamSubscription<List<ScanResult>>? _homeScanSubscription;
  StreamSubscription<bool>? _homeScanStateSubscription;
  StreamSubscription<BluetoothAdapterState>? _homeAdapterStateSubscription;
  Timer? _weatherRefreshTimer;
  Timer? _smartCaneStatusRefreshTimer;
  final Set<String> _shownPairingRequestIds = {};
  bool _isPairingDialogOpen = false;
  final TTSService _ttsService = TTSService();
  final STTService _sttService = STTService();
  bool _isSpeaking = false;
  bool _initialPermissionFlowDone = false;
  bool _locationFeaturesStarted = false;
  bool _announceHomeOpenedFromVoice = false;
  bool _hasAnnouncedHomeOpened = false;
  bool _homeSttActive = false;
  bool _homeSttStarting = false;
  bool _suppressNextHomeReturnTts = false;
  bool _isBluetoothOn = false;
  bool _hasBlePermission = false;
  bool _isHomeBleScanning = false;
  bool _isHomePairingCane = false;
  String _homeBleStatus = 'Belum terhubung';
  ScanResult? _homeSelectedCaneResult;
  Future<void>? _sosStatusAnnouncement;
  StreamSubscription<SmartCaneButtonEvent>? _smartCaneButtonSubscription;
  StreamSubscription<SmartCaneBatteryData>? _smartCaneBatterySubscription;
  StreamSubscription<String>? _userNameSubscription;
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
    _bleService.addListener(_syncHomeBleServiceState);
    _startSmartCaneStatusRefreshTimer();
    _homeAdapterStateSubscription = FlutterBluePlus.adapterState.listen((
      state,
    ) {
      if (!mounted) return;
      setState(() => _isBluetoothOn = state == BluetoothAdapterState.on);
    });
    unawaited(_checkHomeBluetoothStatus());
    _smartCaneButtonSubscription = SmartCaneBleService
        .instance
        .buttonEventStream
        .listen(_handleSmartCaneButtonEvent);
    unawaited(_cancelStaleOngoingNavigationTrips());
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
      notifyTunaNetraHomeReady();
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

  Future<void> _cancelStaleOngoingNavigationTrips() async {
    final cancelledCount = await _navigationHistoryService
        .cancelOngoingTripsForCurrentUser();
    if (cancelledCount == 0) return;

    await _liveTrackingService.updateNavigationTripState(
      currentTripId: null,
      isNavigating: false,
    );
  }

  void _startWeatherRefreshTimer() {
    _weatherRefreshTimer?.cancel();
    _weatherRefreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _loadWeather(speakWhenReady: false);
    });
  }

  void _startSmartCaneStatusRefreshTimer() {
    _smartCaneStatusRefreshTimer?.cancel();
    _smartCaneStatusRefreshTimer = Timer.periodic(const Duration(seconds: 3), (
      _,
    ) {
      if (mounted) setState(() {});
    });
  }

  Future<void> speakSafe(
    String text, {
    TtsPriority priority = TtsPriority.normal,
    String? deduplicationKey,
    String? replacementKey,
    Duration? maxAge,
  }) async {
    _isSpeaking = true;
    try {
      await _ttsService.speak(
        text,
        priority: priority,
        deduplicationKey: deduplicationKey,
        replacementKey: replacementKey,
        maxAge: maxAge,
      );
    } finally {
      _isSpeaking = false;
    }
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

  bool get _isSmartCaneConnected =>
      SmartCaneBleService.instance.connectedDevice != null;

  bool get _isSensorRunning => _bleService.isSensorRunning;

  bool get _isModelRunning => _bleService.isModelRunning;

  bool get _isSmartCaneReady => _bleService.isSmartCaneReady;

  bool get _isSmartCaneBatteryLow {
    final percentage = _smartCaneBatteryPercentage;
    return percentage != null && percentage <= 20;
  }

  Color get _smartCaneStatusColor {
    if (!_isSmartCaneConnected) return AppColors.warning;
    if (_isSmartCaneBatteryLow) return AppColors.error;
    if (!_isSmartCaneReady) return AppColors.warning;
    return AppColors.success;
  }

  Color get _batteryStatusColor {
    final percentage = _smartCaneBatteryPercentage;
    if (percentage == null) return AppColors.textTertiary;
    if (percentage <= 20) return AppColors.error;
    if (percentage <= 40) return AppColors.warning;
    return AppColors.success;
  }

  String get _smartCanePrimaryStatus {
    if (!_isSmartCaneConnected) return 'Tongkat belum terhubung';
    if (_isSmartCaneBatteryLow) return 'Baterai tongkat rendah';
    if (!_isSmartCaneReady) return 'Smartcane Belum Siap';
    return 'Smartcane Siap';
  }

  String get _smartCaneSecondaryStatus {
    if (!_isSmartCaneConnected) return 'Hubungkan melalui koneksi';
    if (_isSmartCaneBatteryLow) return 'Lakukan pengisian baterai segera';
    if (!_isSensorRunning) return 'Menunggu data sensor';
    if (!_isModelRunning) return 'Menunggu model ML';
    return 'Sensor dan model ML aktif';
  }

  String get _bluetoothStatusLabel {
    if (_isSmartCaneConnected) return 'Terhubung';
    if (_isHomePairingCane || _bleService.isConnecting) {
      return 'Menyambungkan';
    }
    if (_isHomeBleScanning) return 'Mencari perangkat';
    return 'Belum terhubung';
  }

  String get _navigationStatusLabel => _locationFeaturesStarted
      ? 'Navigasi Siap Digunakan'
      : 'Navigasi belum siap';

  String get _sensorStatusLabel {
    if (!_isSmartCaneConnected) return 'Belum terhubung';
    if (!_isSensorRunning) return 'Sensor belum aktif';
    if (!_isModelRunning) return 'Model belum aktif';
    return 'SmartCane siap';
  }

  String get _gpsStatusLabel =>
      _locationFeaturesStarted ? 'GPS aktif' : 'GPS belum aktif';

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

    if (_suppressNextHomeReturnTts) {
      _suppressNextHomeReturnTts = false;
      return;
    }

    final sosStatusAnnouncement = _sosStatusAnnouncement;
    if (sosStatusAnnouncement != null) {
      await sosStatusAnnouncement;
    }

    await speakSafe("Kamu kembali ke halaman utama");
  }

  @override
  void didPushNext() {
    _stopHomeStt();
    unawaited(_ttsService.stop());
  }

  void _handleCommand(String command) async {
    await _stopHomeStt();

    if (TunaNetraVoiceCommands.isHomeCommand(command)) {
      await speakSafe("Kamu sudah berada di halaman utama");
    } else if (TunaNetraVoiceCommands.isSosCommand(command)) {
      await _triggerEmergency();
    } else if (command.contains("cek cuaca")) {
      await _speakCurrentWeather();
    } else if (_isReconnectSmartCaneCommand(command)) {
      await _reconnectSmartCaneFromVoice();
    } else if (_isConnectSmartCaneCommand(command)) {
      await speakSafe("Membuka koneksi SmartCane");
      await _handleHomeConnectionTap();
    } else if (command.contains("cek koneksi")) {
      await _speakSmartCaneConnectionStatus();
    } else if (command.contains("cek baterai")) {
      await _speakSmartCaneBatteryStatus();
    } else if (_isCheckSmartCaneCommand(command)) {
      await _speakSmartCaneStatus();
    } else if (command.contains("cek gps")) {
      await _speakGpsStatus();
    } else if (command.contains("navigasi")) {
      await speakSafe("Membuka navigasi");
      if (!mounted) return;
      Navigator.pushNamed(context, AppRoutes.tunaNetraNavigation);
    } else if (command.contains("ebook") || command.contains("buku panduan")) {
      await speakSafe("Membuka buku panduan");
      if (!mounted) return;
      Navigator.pushNamed(context, AppRoutes.tunaNetraEbook);
    } else if (command.contains("pengaturan")) {
      await speakSafe("Membuka pengaturan");
      if (!mounted) return;
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
          onNoSpeechDetected: () {
            if (!mounted) return;
            unawaited(
              speakSafe('Tidak ada suara terdeteksi. Tekan tombol dan coba lagi.'),
            );
          },
          onStatus: (status) {
            _homeSttActive = status == 'listening';
          },
          onError: (_) {
            _homeSttActive = false;
          },
          pauseFor: const Duration(seconds: 5),
          finalResultsOnly: true,
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

  Future<void> _finishHomeStt() async {
    _homeSttActive = false;
    _homeSttStarting = false;
    await _sttService.finishListening();
  }

  bool _isKnownHomeVoiceCommand(String text) {
    return TunaNetraVoiceCommands.isHomeCommand(text) ||
        text.contains("cek cuaca") ||
        text.contains("bluetooth") ||
        text.contains("hubungkan ulang tongkat") ||
        text.contains("hubungkan ulang smartcane") ||
        text.contains("hubungkan ulang smarthcane") ||
        text.contains("sambungkan ulang tongkat") ||
        text.contains("sambungkan ulang smartcane") ||
        text.contains("sambungkan ulang smarthcane") ||
        text.contains("hubungkan tongkat") ||
        text.contains("hubungkan smartcane") ||
        text.contains("hubungkan smarthcane") ||
        text.contains("cek koneksi") ||
        text.contains("cek baterai") ||
        text.contains("cek gps") ||
        text.contains("navigasi") ||
        text.contains("ebook") ||
        text.contains("buku panduan") ||
        text.contains("tongkat pintar") ||
        text.contains("smartcane") ||
        text.contains("smarthcane") ||
        text.contains("pengaturan") ||
        TunaNetraVoiceCommands.isSosCommand(text);
  }

  bool _isConnectSmartCaneCommand(String command) {
    return command.contains("bluetooth") ||
        command.contains("hubungkan tongkat") ||
        command.contains("hubungkan smartcane") ||
        command.contains("hubungkan smarthcane");
  }

  bool _isReconnectSmartCaneCommand(String command) {
    return TunaNetraVoiceCommands.isReconnectSmartCaneCommand(command);
  }

  Future<void> _reconnectSmartCaneFromVoice() async {
    if (_bleService.isConnected) {
      await speakSafe("SmartCane sudah terhubung.");
      return;
    }

    if (_bleService.isConnecting || _bleService.isAutoConnecting) {
      await speakSafe("SmartCane sedang dihubungkan. Mohon tunggu.");
      return;
    }

    final rememberedCaneId = await _bleService.getRememberedCaneRemoteId();
    if (rememberedCaneId == null) {
      await speakSafe(
        "Belum ada SmartCane tersimpan. Gunakan perintah hubungkan SmartCane untuk membuka menu koneksi.",
      );
      return;
    }

    await speakSafe("Mencoba menghubungkan ulang SmartCane.");
    await _bleService.initializeAutoReconnect(
      force: true,
      maxAttempts: 5,
      log: (message) => debugPrint(message),
      updateStatus: _updateHomeBleStatus,
    );

    if (_bleService.isConnected) {
      if (mounted) {
        AppFeedback.success(context, 'SmartCane berhasil terhubung kembali.');
      }
      await speakSafe("SmartCane berhasil terhubung kembali.");
      return;
    }

    if (mounted) {
      AppFeedback.warning(
        context,
        'SmartCane belum dapat terhubung. Pastikan tongkat menyala dan berada di dekat Anda.',
      );
    }
    await speakSafe(
      "SmartCane belum dapat terhubung. Pastikan SmartCane menyala dan berada di dekat Anda.",
    );
  }

  bool _isCheckSmartCaneCommand(String command) {
    return command.contains("cek smartcane") ||
        command.contains("cek smarthcane") ||
        command.contains("cek tongkat");
  }

  Future<void> _speakSmartCaneConnectionStatus() async {
    if (!_isSmartCaneConnected) {
      await speakSafe("SmartCane belum terhubung.");
      return;
    }

    final deviceName = _bleService.connectedBleName;
    final battery = _smartCaneBatteryPercentage;
    final batteryText = battery == null ? '' : ' Baterai $battery persen.';
    final deviceText = deviceName == null || deviceName.trim().isEmpty
        ? ''
        : ' ke $deviceName';

    await speakSafe("SmartCane terhubung$deviceText.$batteryText");
  }

  Future<void> _speakSmartCaneBatteryStatus() async {
    if (!_isSmartCaneConnected) {
      await speakSafe("SmartCane belum terhubung.");
      return;
    }

    final battery = _smartCaneBatteryPercentage;
    if (battery == null) {
      await speakSafe("Baterai SmartCane belum terbaca.");
      return;
    }

    await speakSafe("Baterai SmartCane $battery persen.");
  }

  Future<void> _speakSmartCaneStatus() async {
    if (!_isSmartCaneConnected) {
      await speakSafe("SmartCane belum terhubung.");
      return;
    }

    final battery = _smartCaneBatteryPercentage;
    final batteryText = battery == null ? '' : ' Baterai $battery persen.';
    if (!_isSensorRunning) {
      await speakSafe("SmartCane terhubung.$batteryText Menunggu data sensor.");
      return;
    }

    if (!_isModelRunning) {
      await speakSafe(
        "SmartCane terhubung.$batteryText Sensor aktif. Menunggu model ML.",
      );
      return;
    }

    await speakSafe(
      "SmartCane siap digunakan.$batteryText Sensor dan model ML aktif.",
    );
  }

  Future<void> _speakGpsStatus() async {
    await speakSafe(
      _locationFeaturesStarted ? "Status GPS aktif." : "GPS belum aktif.",
    );
  }

  void _speakIfReady() async {
    if (!_initialPermissionFlowDone) return;
    if (_isSpeaking) return;

    if (_announceHomeOpenedFromVoice && !_hasAnnouncedHomeOpened) {
      _hasAnnouncedHomeOpened = true;
      await _stopHomeStt();
      await speakSafe("Halaman utama dibuka");
    }
  }

  Future<void> _handleSmartCaneButtonEvent(SmartCaneButtonEvent event) async {
    debugPrint('[SMARTCANE_BUTTON] Home menerima event: ${event.type}');
    if (!mounted) return;

    // Jika halaman ini bukan route aktif (ada halaman lain di atas),
    // abaikan event agar tidak bentrok dengan handler halaman yang sedang aktif.
    if (ModalRoute.of(context)?.isCurrent != true) return;

    if (event.isVoiceAssistantStop) {
      debugPrint('[SMARTCANE_BUTTON] Home mematikan STT');
      await _finishHomeStt();
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
      _userNameSubscription?.cancel();
      _userNameSubscription = _userNameStream.listen((newName) {
        if (mounted) {
          setState(() {
            _userName = newName;
          });
          _speakIfReady();
        }
      });
      unawaited(_syncRealtimeTrackingAccess(uid));
    } else {
      print('❌ User UID is null');
      _userNameStream = Stream.value('Pengguna');
    }
  }

  Future<void> _syncRealtimeTrackingAccess(String userId) async {
    try {
      final snapshot = await _firestore.collection('users').doc(userId).get();
      final connectedFamilies = snapshot.data()?['connectedFamilies'];
      final familyUids = <String>{};
      if (connectedFamilies is List) {
        for (final family in connectedFamilies) {
          if (family is Map && family['uid'] is String) {
            familyUids.add(family['uid'] as String);
          }
        }
      }

      final familyMembers = await _firestore
          .collection('users')
          .doc(userId)
          .collection('family_members')
          .get();
      familyUids.addAll(familyMembers.docs.map((doc) => doc.id));

      await RealtimeLiveTrackingService.instance.syncFamilyAccess(
        userId: userId,
        familyUids: familyUids,
      );
    } catch (error) {
      debugPrint('[HOME] Gagal menyinkronkan akses live tracking: $error');
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

  void _syncHomeBleServiceState() {
    if (!mounted) return;
    setState(() {
      _latestSmartCaneBatteryData = _bleService.latestBatteryData;
      if (_bleService.isConnected) {
        final name = _bleService.connectedBleName ?? 'TemanArah-Cane';
        _homeBleStatus = 'Terhubung ke $name';
      } else if (_homeBleStatus.startsWith('Terhubung')) {
        _homeBleStatus = _isBluetoothOn
            ? 'Belum terhubung'
            : 'Bluetooth belum aktif';
      }
    });
  }

  Future<void> _handleHomeConnectionTap() async {
    if (_isHomeBleScanning ||
        _isHomePairingCane ||
        _bleService.isConnecting ||
        _bleService.isAutoConnecting) {
      return;
    }

    if (_bleService.isConnected) {
      await _disconnectHomeBleDevice();
      return;
    }

    final rememberedCaneId = await _bleService.getRememberedCaneRemoteId();
    if (rememberedCaneId != null) {
      await _connectRememberedHomeCaneDirect();
      return;
    }

    await _scanAndShowHomeBleDevices();
  }

  Future<void> _connectRememberedHomeCaneDirect() async {
    if (!mounted) return;
    setState(() {
      _isHomePairingCane = true;
      _homeBleStatus = 'Menghubungkan ulang tongkat...';
    });

    try {
      await _bleService.initializeAutoReconnect(
        force: true,
        maxAttempts: 5,
        log: (message) => debugPrint(message),
        updateStatus: _updateHomeBleStatus,
      );
      _syncHomeBleServiceState();

      if (_bleService.isConnected) {
        final bleName = _bleService.connectedBleName ?? 'Smart Cane';
        if (mounted) {
          setState(() => _homeBleStatus = 'Terhubung ke $bleName');
        }
        _showHomeBleSnackBar('Tongkat berhasil terhubung kembali.');
        return;
      }

      _showHomeBleSnackBar(
        'SmartCane tersimpan belum dapat dihubungkan. Pastikan tongkat menyala dan berada di dekat Anda.',
        isError: true,
      );
    } catch (error) {
      _updateHomeBleStatus('Gagal menghubungkan ulang');
      _showHomeBleSnackBar(
        'SmartCane tersimpan belum dapat dihubungkan. Pastikan tongkat menyala dan berada di dekat Anda.',
        isError: true,
      );
      debugPrint(
        '[HOME-BLE] Reconnect langsung perangkat tersimpan gagal: $error',
      );
    } finally {
      if (mounted) setState(() => _isHomePairingCane = false);
    }
  }

  Future<void> _checkHomeBluetoothStatus() async {
    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (!mounted) return;
      setState(() => _isBluetoothOn = adapterState == BluetoothAdapterState.on);
    } catch (error) {
      _updateHomeBleStatus('Gagal mengecek Bluetooth');
      debugPrint('[HOME-BLE] Gagal mengecek adapter: $error');
    }
  }

  Future<void> _requestHomeBlePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      if (!mounted) return;
      setState(() => _hasBlePermission = true);
      return;
    }

    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];
    final statuses = await permissions.request();
    final granted = statuses.values.every((status) => status.isGranted);

    if (!mounted) return;
    setState(() => _hasBlePermission = granted);
    if (!granted) {
      _updateHomeBleStatus('Izin Bluetooth belum lengkap');
    }
  }

  Future<void> _turnOnHomeBluetooth() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await FlutterBluePlus.turnOn(timeout: 20);
      await _checkHomeBluetoothStatus();
    } catch (error) {
      _updateHomeBleStatus('Bluetooth belum aktif');
      debugPrint('[HOME-BLE] Gagal menyalakan Bluetooth: $error');
    }
  }

  Future<void> _startHomeBleScan({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    await _checkHomeBluetoothStatus();
    await _requestHomeBlePermissions();

    if (!_isBluetoothOn) {
      _updateHomeBleStatus('Menyalakan Bluetooth...');
      await _turnOnHomeBluetooth();
      await _checkHomeBluetoothStatus();

      if (!_isBluetoothOn) {
        _showHomeBleSnackBar(
          'Bluetooth belum aktif. Nyalakan Bluetooth lalu coba kembali.',
          isError: true,
        );
        return;
      }
    }

    if (!_hasBlePermission) {
      _showHomeBleSnackBar(
        'Izin Bluetooth belum lengkap. Periksa izin aplikasi lalu coba kembali.',
        isError: true,
      );
      return;
    }

    await _stopHomeBleScan(logWhenStopped: false);

    if (!mounted) return;
    setState(() {
      _homeScanResults.clear();
      _homeSelectedCaneResult = null;
      _homeBleStatus = 'Mencari tongkat...';
    });

    _homeScanSubscription = FlutterBluePlus.scanResults.listen((results) {
      var hasNewDevice = false;
      for (final result in results) {
        final remoteId = result.device.remoteId;
        if (!_homeScanResults.containsKey(remoteId)) {
          hasNewDevice = true;
        }
        _homeScanResults[remoteId] = result;
      }
      if (hasNewDevice && mounted) setState(() {});
    });

    _homeScanStateSubscription = FlutterBluePlus.isScanning.listen((
      isScanning,
    ) {
      if (!mounted) return;
      setState(() => _isHomeBleScanning = isScanning);
    });

    try {
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (error) {
      _updateHomeBleStatus('Gagal mencari tongkat');
      debugPrint('[HOME-BLE] Scan gagal: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isHomeBleScanning = false;
          if (_homeBleStatus == 'Mencari tongkat...') {
            _homeBleStatus = _homeScanResults.isEmpty
                ? 'Tongkat tidak ditemukan'
                : 'Pilih tongkat';
          }
        });
      }
    }
  }

  Future<void> _stopHomeBleScan({bool logWhenStopped = true}) async {
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (error) {
      debugPrint('[HOME-BLE] Gagal menghentikan scan: $error');
    }

    await _homeScanSubscription?.cancel();
    _homeScanSubscription = null;
    await _homeScanStateSubscription?.cancel();
    _homeScanStateSubscription = null;

    if (!mounted) return;
    setState(() => _isHomeBleScanning = false);
  }

  Future<void> _scanAndShowHomeBleDevices() async {
    if (_bleService.isAutoConnecting) return;

    await _startHomeBleScan();
    if (!mounted) return;

    final results = _visibleHomeScanResults();
    if (results.isEmpty) {
      _showHomeBleSnackBar(
        'Tidak ada perangkat tongkat yang ditemukan.',
        isError: true,
      );
      return;
    }

    final selected = await _showHomeScanResultsSheet(results);
    if (selected == null || !mounted) return;

    _homeSelectedCaneResult = selected;
    _updateHomeBleStatus(
      'Perangkat dipilih: ${_displayHomeDeviceName(selected)}',
    );
    await _stopHomeBleScan(logWhenStopped: false);

    if (await _bleService.isRememberedCaneDevice(selected.device)) {
      await _connectRememberedHomeCane(selected);
      return;
    }

    await _showHomePairingDialog(selected);
  }

  Future<void> _connectRememberedHomeCane(ScanResult selectedResult) async {
    if (!mounted) return;
    setState(() {
      _isHomePairingCane = true;
      _homeBleStatus = 'Menghubungkan ulang tongkat...';
    });

    try {
      await _connectHomeBleDevice(selectedResult.device);

      if (!_bleService.isConnected) {
        _showHomeBleSnackBar(
          'Gagal menghubungkan ulang tongkat. Silakan coba kembali.',
          isError: true,
        );
        return;
      }

      final bleName = _homeDeviceName(selectedResult.device);
      if (!mounted) return;
      setState(() => _homeBleStatus = 'Terhubung ke $bleName');
      _showHomeBleSnackBar('Tongkat berhasil terhubung kembali.');
    } catch (error) {
      _updateHomeBleStatus('Gagal menghubungkan ulang');
      _showHomeBleSnackBar(
        'Gagal menghubungkan ulang tongkat. Silakan coba kembali.',
        isError: true,
      );
      debugPrint('[HOME-BLE] Reconnect perangkat tersimpan gagal: $error');
    } finally {
      if (mounted) setState(() => _isHomePairingCane = false);
    }
  }

  Future<ScanResult?> _showHomeScanResultsSheet(List<ScanResult> results) {
    _suppressNextHomeReturnTts = true;
    return showModalBottomSheet<ScanResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: const Border(
              top: BorderSide(color: AppDialogStyle.borderColor),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.045),
                blurRadius: 14,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Text(
                    'Hubungkan Tongkat',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pilih Smart Cane yang ditemukan di sekitar.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final result in results) ...[
                            _HomeBleDeviceTile(
                              name: _displayHomeDeviceName(result),
                              remoteId: result.device.remoteId.toString(),
                              rssi: result.rssi,
                              onTap: () => Navigator.pop(context, result),
                            ),
                            if (result != results.last)
                              const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showHomePairingDialog(ScanResult result) async {
    _homeCaneCodeController.clear();
    _homeCanePinController.clear();

    _suppressNextHomeReturnTts = true;
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isDismissible: !_isHomePairingCane,
      enableDrag: !_isHomePairingCane,
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: const Border(
                top: BorderSide(color: AppDialogStyle.borderColor),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.045),
                  blurRadius: 14,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.infoLight.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.bluetooth_rounded,
                            color: AppColors.primaryDark,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hubungkan Tongkat',
                                style: AppTextStyles.bodyLarge.copyWith(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _displayHomeDeviceName(result),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _HomePairingTextField(
                      controller: _homeCaneCodeController,
                      icon: Icons.badge_rounded,
                      label: 'Kode Tongkat',
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 12),
                    _HomePairingTextField(
                      controller: _homeCanePinController,
                      icon: Icons.pin_rounded,
                      label: 'PIN Tongkat',
                      keyboardType: TextInputType.number,
                      obscureText: true,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Hubungkan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (submitted == true) {
      FocusManager.instance.primaryFocus?.unfocus();
      await _pairHomeCaneWithPin();
    }
  }

  Future<void> _pairHomeCaneWithPin() async {
    final selectedResult = _homeSelectedCaneResult;
    final caneCode = _homeCaneCodeController.text.trim();
    final pin = _homeCanePinController.text.trim();

    if (selectedResult == null) {
      _showHomeBleSnackBar(
        'Silakan pilih perangkat tongkat terlebih dahulu.',
        isError: true,
      );
      return;
    }

    if (caneCode.isEmpty || pin.isEmpty) {
      _showHomeBleSnackBar('Kode tongkat dan PIN wajib diisi.', isError: true);
      return;
    }

    await _checkHomeBluetoothStatus();
    await _requestHomeBlePermissions();

    if (!_isBluetoothOn || !_hasBlePermission) {
      _showHomeBleSnackBar(
        'Bluetooth atau izin aplikasi belum siap.',
        isError: true,
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isHomePairingCane = true;
      _homeBleStatus = 'Menghubungkan tongkat...';
    });

    try {
      await _connectHomeBleDevice(selectedResult.device);
      if (_bleService.connectedDevice == null) {
        _showHomeBleSnackBar(
          'Gagal terhubung ke perangkat tongkat.',
          isError: true,
        );
        return;
      }

      final bleName = _homeDeviceName(selectedResult.device);
      if (mounted) {
        setState(() => _homeBleStatus = 'Terhubung ke $bleName');
      }

      try {
        final paired = await _sendHomePairingPin(
          device: selectedResult.device,
          caneCode: caneCode,
          pin: pin,
        );

        if (!paired) {
          debugPrint('[HOME-BLE] PIN pairing tidak tervalidasi.');
        }
      } catch (error) {
        debugPrint('[HOME-BLE] Validasi pairing dilewati: $error');
      }

      try {
        await _bleService.saveRememberedCane(
          caneCode: caneCode,
          bleName: bleName,
          remoteId: selectedResult.device.remoteId.toString(),
        );
      } catch (error) {
        debugPrint(
          '[HOME-BLE] Koneksi berhasil, penyimpanan lokal gagal: $error',
        );
      }

      // Trigger urutan TTS/snackbar (terhubung → siap → baterai) seperti auto-reconnect.
      // ChangeNotifier listener di SmartCaneStatusNotificationService sudah menangani
      // ini secara reaktif; notifikasi ini sebagai safety net untuk edge case.
      notifySmartCaneManuallyPaired();

      try {
        await _saveHomeCanePairingToFirestore(
          caneCode: caneCode,
          bleName: bleName,
          remoteId: selectedResult.device.remoteId.toString(),
        );
      } catch (error) {
        debugPrint(
          '[HOME-BLE] Koneksi berhasil, penyimpanan Firestore gagal: $error',
        );
      }

      if (!mounted) return;
      setState(() => _homeBleStatus = 'Terhubung ke $bleName');
    } catch (error) {
      if (_bleService.isConnected) {
        final bleName = _bleService.connectedBleName ?? 'Smart Cane';
        try {
          await _bleService.saveRememberedCane(
            caneCode: caneCode,
            bleName: bleName,
            remoteId: selectedResult.device.remoteId.toString(),
          );
        } catch (saveError) {
          debugPrint(
            '[HOME-BLE] Koneksi berhasil, penyimpanan lokal gagal: $saveError',
          );
        }
        notifySmartCaneManuallyPaired();
        if (mounted) {
          setState(() => _homeBleStatus = 'Terhubung ke $bleName');
        }
        debugPrint('[HOME-BLE] Koneksi berhasil dengan catatan: $error');
        return;
      }

      _updateHomeBleStatus('Pairing tongkat gagal');
      _showHomeBleSnackBar(
        'Proses koneksi tongkat gagal. Silakan coba kembali.',
        isError: true,
      );
      debugPrint('[HOME-BLE] Pairing gagal: $error');
    } finally {
      if (mounted) setState(() => _isHomePairingCane = false);
    }
  }

  Future<void> _connectHomeBleDevice(BluetoothDevice device) async {
    await _stopHomeBleScan(logWhenStopped: false);
    await _bleService.connectToDevice(
      device,
      log: (message) => debugPrint(message),
      updateStatus: _updateHomeBleStatus,
    );
    _syncHomeBleServiceState();
  }

  Future<void> _disconnectHomeBleDevice() async {
    await _bleService.disconnect(
      log: (message) => debugPrint(message),
      updateStatus: _updateHomeBleStatus,
    );
    _syncHomeBleServiceState();
  }

  Future<bool> _sendHomePairingPin({
    required BluetoothDevice device,
    required String caneCode,
    required String pin,
  }) async {
    final services = await device.discoverServices(
      subscribeToServicesChanged: false,
    );

    BluetoothCharacteristic? pairingCharacteristic;
    for (final service in services) {
      if (service.uuid != _smartCaneServiceUuid) continue;
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == _pairingCharacteristicUuid) {
          pairingCharacteristic = characteristic;
          break;
        }
      }
    }

    if (pairingCharacteristic == null) return false;

    final bytes = utf8.encode('$caneCode|$pin');
    await pairingCharacteristic.write(
      bytes,
      withoutResponse: pairingCharacteristic.properties.writeWithoutResponse,
    );

    if (pairingCharacteristic.properties.read) {
      final responseBytes = await pairingCharacteristic.read();
      if (responseBytes.isNotEmpty) {
        final responseText = utf8.decode(responseBytes, allowMalformed: true);
        try {
          final response = jsonDecode(responseText);
          if (response is Map && response['ok'] == true) return true;
          if (response is Map && response['ok'] == false) return false;
        } catch (_) {
          return responseText.toLowerCase().contains('ok');
        }
      }
    }

    return true;
  }

  Future<void> _saveHomeCanePairingToFirestore({
    required String caneCode,
    required String bleName,
    required String remoteId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firestore = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();
    final caneRef = firestore.collection('smart_canes').doc(caneCode);
    final userCaneRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('smart_canes')
        .doc(caneCode);

    await firestore.runTransaction((transaction) async {
      transaction.set(caneRef, {
        'deviceId': caneCode,
        'bleName': bleName,
        'lastRemoteId': remoteId,
        'ownerUid': user.uid,
        'allowedUsers': FieldValue.arrayUnion([user.uid]),
        'pairedPhonesCount': FieldValue.increment(1),
        'lastPairedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      transaction.set(userCaneRef, {
        'deviceId': caneCode,
        'bleName': bleName,
        'remoteId': remoteId,
        'pairedAt': now,
        'lastConnectedAt': now,
        'role': 'owner',
      }, SetOptions(merge: true));
    });
  }

  void _updateHomeBleStatus(String status) {
    if (!mounted) return;
    setState(() => _homeBleStatus = status);
  }

  void _showHomeBleSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    AppFeedback.show(
      context,
      message,
      type: isError ? AppFeedbackType.error : AppFeedbackType.success,
      announce: true,
    );
  }

  String _homeDeviceName(BluetoothDevice device) {
    final platformName = device.platformName.trim();
    final name = platformName.isNotEmpty ? platformName : device.advName.trim();
    return name.isEmpty ? 'Unknown BLE Device' : name;
  }

  String _displayHomeDeviceName(ScanResult result) {
    final name = _homeDeviceName(result.device);
    return name == 'Unknown BLE Device' ? 'Perangkat tanpa nama' : name;
  }

  List<ScanResult> _visibleHomeScanResults() {
    final results = _homeScanResults.values
        .where(
          (result) => _homeDeviceName(result.device) != 'Unknown BLE Device',
        )
        .toList();
    results.sort((a, b) {
      final aName = _homeDeviceName(a.device).toLowerCase();
      final bName = _homeDeviceName(b.device).toLowerCase();
      final aLikelyCane = aName.contains('temanarah');
      final bLikelyCane = bName.contains('temanarah');
      if (aLikelyCane != bLikelyCane) return aLikelyCane ? -1 : 1;
      return b.rssi.compareTo(a.rssi);
    });
    return results.take(12).toList();
  }

  void _navigateToEbook() {
    Navigator.pushNamed(context, AppRoutes.tunaNetraEbook);
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

    SosSendResult? sosResult;
    Object? sosError;

    try {
      await speakSafe(
        'Mengirim SOS darurat',
        priority: TtsPriority.critical,
        deduplicationKey: 'home-sos-sending',
      );
      sosResult = await _sosService.sendSosAlert();
    } catch (e) {
      sosError = e;
    } finally {
      if (mounted) {
        setState(() {
          _isSendingSos = false;
        });
      }
    }

    if (!mounted) return;

    if (sosResult != null) {
      AppFeedback.show(
        context,
        sosResult.feedbackMessage,
        type: sosResult.deliveredToAnyFamily
            ? AppFeedbackType.success
            : AppFeedbackType.warning,
        announce: false,
      );
      _queueSosStatusAnnouncement(sosResult.spokenMessage);
    } else {
      AppFeedback.error(
        context,
        sosError,
        fallback:
            'SOS belum dapat dikirim. Periksa koneksi dan coba kembali segera.',
        announce: true,
      );
      _queueSosStatusAnnouncement('SOS gagal dikirim');
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
      await speakSafe(
        message,
        priority: TtsPriority.critical,
        deduplicationKey: 'home-sos-status-$message',
      );
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

    final accepted = await showAppConfirmDialog(
      context: context,
      title: 'Konfirmasi Keluarga',
      description: '$displayName ingin terhubung dan memonitor akun Anda.',
      icon: Icons.family_restroom_rounded,
      iconColor: AppColors.primaryDark,
      cancelText: 'Tolak',
      confirmText: 'Terima',
      confirmButtonColor: AppColors.primaryDark,
      barrierDismissible: false,
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
      AppFeedback.show(
        context,
        accepted
            ? 'Keluarga berhasil terhubung.'
            : 'Permintaan keluarga ditolak.',
        type: accepted ? AppFeedbackType.success : AppFeedbackType.warning,
        announce: true,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        error,
        fallback:
            'Respons koneksi keluarga belum dapat diproses. Silakan coba lagi.',
        announce: true,
      );
    } finally {
      _isPairingDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFD),
      body: Stack(
        children: [
          FadeTransition(opacity: _fadeAnimation, child: _buildMainContent()),
          if (_isSendingSos) _buildSosLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildSosLoadingOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: AppDialogStyle.barrierColor,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppDialogStyle.borderRadius),
              border: Border.all(color: AppDialogStyle.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.error,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Mengirim SOS...',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 18),
            _buildSmartCaneStatusCard(),
            const SizedBox(height: 16),
            _buildPrimaryActions(),
            const SizedBox(height: 18),
            Text(
              'Menu',
              style: AppTextStyles.bodyLarge.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                _SafetyMenuCard(
                  icon: Icons.menu_book_rounded,
                  title: 'Buku Panduan',
                  subtitle: 'Panduan penggunaan',
                  color: AppColors.textSecondary,
                  onTap: _navigateToEbook,
                ),
                _SafetyMenuCard(
                  icon: Icons.settings_rounded,
                  title: 'Pengaturan',
                  subtitle: 'Akun dan aplikasi',
                  color: AppColors.textSecondary,
                  onTap: _navigateToSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selamat datang',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.heading3.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        _buildWeatherBadge(),
      ],
    );
  }

  Widget _buildWeatherBadge() {
    if (_weatherData == null) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: _isLoadingWeather
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(
                Icons.cloud_off_rounded,
                color: AppColors.textTertiary,
              ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            WeatherService.getWeatherEmoji(_weatherData!.weatherCondition),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 6),
          Text(
            '${_weatherData!.temperature.toStringAsFixed(0)} C',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartCaneStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _smartCaneStatusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _isSmartCaneConnected
                      ? Icons.check_circle_rounded
                      : Icons.sync_problem_rounded,
                  color: _smartCaneStatusColor,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _smartCanePrimaryStatus,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _smartCaneSecondaryStatus,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatusPill(
                  icon: _isSmartCaneConnected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_searching_rounded,
                  label: 'Koneksi',
                  value: _bluetoothStatusLabel,
                  color: _isSmartCaneConnected
                      ? AppColors.success
                      : AppColors.primaryDark,
                  onTap: _handleHomeConnectionTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatusPill(
                  icon: Icons.sensors_rounded,
                  label: 'SmartCane',
                  value: _sensorStatusLabel,
                  color: _isSmartCaneReady
                      ? AppColors.success
                      : AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatusPill(
                  icon: Icons.battery_full_rounded,
                  label: 'Baterai',
                  value: _smartCaneBatteryPercentage == null
                      ? 'Belum terbaca'
                      : _smartCaneBatteryLabel,
                  color: _batteryStatusColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatusPill(
                  icon: Icons.location_on_rounded,
                  label: 'Lokasi',
                  value: _gpsStatusLabel,
                  color: AppColors.info,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryActions() {
    return Column(
      children: [
        _PrimaryActionButton(
          icon: Icons.navigation_rounded,
          title: 'Mulai Navigasi',
          subtitle: _navigationStatusLabel,
          color: AppColors.primaryDark,
          onTap: _navigateToNavigation,
        ),
        const SizedBox(height: 12),
        _PrimaryActionButton(
          icon: Icons.warning_amber_rounded,
          title: _isSendingSos ? 'Mengirim SOS...' : 'Kirim SOS',
          subtitle: 'Hubungi keluarga saat kondisi darurat',
          color: AppColors.error,
          onTap: _triggerEmergency,
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveTrackingService.stopHomeLocationTracking();
    _weatherRefreshTimer?.cancel();
    _smartCaneStatusRefreshTimer?.cancel();
    _homeCaneCodeController.dispose();
    _homeCanePinController.dispose();
    _homeScanSubscription?.cancel();
    _homeScanStateSubscription?.cancel();
    _homeAdapterStateSubscription?.cancel();
    _bleService.removeListener(_syncHomeBleServiceState);
    _smartCaneButtonSubscription?.cancel();
    _smartCaneBatterySubscription?.cancel();
    _userNameSubscription?.cancel();
    _authStateSub?.cancel();
    _stopHomeStt();
    routeObserver.unsubscribe(this);
    _pairingRequestSub?.cancel();
    _fadeController.dispose();
    _rotationController.dispose();
    super.dispose();
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _StatusPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              fontSize: 13,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Semantics(
        liveRegion: true,
        label: '$label, $value',
        child: ExcludeSemantics(child: content),
      );
    }

    return Semantics(
      button: true,
      label: '$label, $value',
      hint: 'Ketuk dua kali untuk membuka',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _HomeBleDeviceTile extends StatelessWidget {
  const _HomeBleDeviceTile({
    required this.name,
    required this.remoteId,
    required this.rssi,
    required this.onTap,
  });

  final String name;
  final String remoteId;
  final int rssi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.infoLight.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.bluetooth_rounded,
                  color: AppColors.primaryDark,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      remoteId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$rssi dBm',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePairingTextField extends StatefulWidget {
  const _HomePairingTextField({
    required this.controller,
    required this.icon,
    required this.label,
    required this.keyboardType,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final TextInputType keyboardType;
  final bool obscureText;

  @override
  State<_HomePairingTextField> createState() => _HomePairingTextFieldState();
}

class _HomePairingTextFieldState extends State<_HomePairingTextField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      obscureText: _obscureText,
      style: AppTextStyles.bodySmall.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(widget.icon, color: AppColors.primaryDark, size: 20),
        suffixIcon: widget.obscureText
            ? IconButton(
                onPressed: () {
                  setState(() => _obscureText = !_obscureText);
                },
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: AppColors.primaryDark, width: 1.3),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PrimaryActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.18),
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
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.button.copyWith(
                            fontSize: 18,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white.withOpacity(0.88),
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.86),
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SafetyMenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SafetyMenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
