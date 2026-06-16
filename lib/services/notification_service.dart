import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' hide Int64List;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String sosFullScreenChannelId = 'sos_fullscreen_channel_v1';
  static const String sosFullScreenChannelName = 'SOS Full Screen Emergency';
  static const String sosFullScreenChannelDescription =
      'Notifikasi SOS layar penuh';
  static const String sosEmergencyChannelId = 'sos_emergency_channel_v3';
  static const String sosEmergencyChannelName = 'SOS Emergency';
  static const String sosEmergencyChannelDescription = 'Notifikasi darurat SOS';
  static const String sosSilentChannelId = 'sos_silent_channel_v1';
  static const String sosSilentChannelName = 'SOS Silent';
  static const String sosSilentChannelDescription =
      'Notifikasi SOS tanpa suara dan getar';
  static const String sosCustomSoundResourceName = 'sos_alert';
  static const int sosEmergencyNotificationId = 8801;
  static const Duration sosAlarmRepeatInterval = Duration(seconds: 5);

  // android/app/src/main/res/raw/sos_alert.mp3 is required for this sound.
  static const bool useCustomSosSound = true;
  static Int64List? get _sosVibrationPattern {
    if (kIsWeb) return null;
    return Int64List.fromList([0, 1000, 500, 1000, 500, 1500]);
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _activeSosStatusSubscription;
  GlobalKey<NavigatorState>? _navigatorKey;
  Timer? _sosAlarmTimer;
  Map<String, dynamic>? _activeSosData;
  Map<String, dynamic>? _initialSosPayload;
  Map<String, dynamic>? _initialSosMonitoringPayload;
  final Set<String> _shownOneShotSosIds = {};
  bool _fullScreenIntentAllowed = true;
  bool _messageHandlersInitialized = false;
  bool _localNotificationsInitialized = false;

  static AndroidNotificationSound? get _sosNotificationSound {
    if (!useCustomSosSound) return null;
    return const RawResourceAndroidNotificationSound(
      sosCustomSoundResourceName,
    );
  }

  static AndroidNotificationChannel _buildSosFullScreenAndroidChannel() {
    return AndroidNotificationChannel(
      sosFullScreenChannelId,
      sosFullScreenChannelName,
      description: sosFullScreenChannelDescription,
      importance: Importance.max,
      playSound: true,
      sound: _sosNotificationSound,
      enableVibration: true,
      vibrationPattern: _sosVibrationPattern,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
  }

  static AndroidNotificationChannel _buildSosAndroidChannel() {
    return AndroidNotificationChannel(
      sosEmergencyChannelId,
      sosEmergencyChannelName,
      description: sosEmergencyChannelDescription,
      importance: Importance.max,
      playSound: true,
      sound: _sosNotificationSound,
      enableVibration: true,
      vibrationPattern: _sosVibrationPattern,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
  }

  static AndroidNotificationChannel _buildSosSilentAndroidChannel() {
    return const AndroidNotificationChannel(
      sosSilentChannelId,
      sosSilentChannelName,
      description: sosSilentChannelDescription,
      importance: Importance.max,
      playSound: false,
      enableVibration: false,
    );
  }

  static NotificationDetails _buildSosNotificationDetails({
    bool fullScreenIntent = false,
    bool useFullScreenChannel = false,
  }) {
    final channelId = useFullScreenChannel
        ? sosFullScreenChannelId
        : sosEmergencyChannelId;
    final channelName = useFullScreenChannel
        ? sosFullScreenChannelName
        : sosEmergencyChannelName;
    final channelDescription = useFullScreenChannel
        ? sosFullScreenChannelDescription
        : sosEmergencyChannelDescription;

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        fullScreenIntent: fullScreenIntent,
        enableVibration: true,
        vibrationPattern: _sosVibrationPattern,
        playSound: true,
        sound: _sosNotificationSound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        onlyAlertOnce: false,
        ongoing: true,
        autoCancel: false,
      ),
    );
  }

  static NotificationDetails _buildSosOneShotNotificationDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        sosEmergencyChannelId,
        sosEmergencyChannelName,
        channelDescription: sosEmergencyChannelDescription,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        enableVibration: true,
        vibrationPattern: _sosVibrationPattern,
        playSound: true,
        sound: _sosNotificationSound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        onlyAlertOnce: true,
        ongoing: false,
        autoCancel: true,
      ),
    );
  }

  static const NotificationDetails _sosSilentNotificationDetails =
      NotificationDetails(
        android: AndroidNotificationDetails(
          sosSilentChannelId,
          sosSilentChannelName,
          channelDescription: sosSilentChannelDescription,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          fullScreenIntent: false,
          enableVibration: false,
          playSound: false,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
        ),
      );

  static void _debugSosSoundChoice() {
    if (useCustomSosSound) {
      debugPrint(
        '[NotificationService] custom SOS sound digunakan: '
        '$sosCustomSoundResourceName',
      );
    } else {
      debugPrint(
        '[NotificationService] custom SOS sound belum tersedia, fallback default sound',
      );
    }
  }

  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
    bool requestPermission = true,
  }) async {
    if (_messageHandlersInitialized) {
      debugPrint('[NotificationService] Message handlers sudah aktif');
      return;
    }

    _navigatorKey = navigatorKey;
    _messageHandlersInitialized = true;

    if (requestPermission) {
      await requestNotificationPermission();
    }
    await createSosEmergencyChannel();
    await _handleLocalNotificationLaunchDetails();

    FirebaseMessaging.onMessage.listen((message) {
      if (_isSosMessage(message)) {
        debugPrint('SOS FCM received');
        final data = Map<String, dynamic>.from(message.data);
        unawaited(_handleForegroundSosMessage(message, data));
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (_isSosMessage(message)) {
        debugPrint('full-screen notification clicked');
        _scheduleSosNavigationFromData(Map<String, dynamic>.from(message.data));
      }
    });

    _messaging.getInitialMessage().then((message) {
      if (message != null && _isSosMessage(message)) {
        debugPrint('full-screen notification clicked');
        _scheduleSosNavigationFromData(
          Map<String, dynamic>.from(message.data),
          delay: const Duration(milliseconds: 700),
        );
      }
    });
  }

  Future<void> initializeMessageHandlers({
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    return initialize(navigatorKey: navigatorKey);
  }

  Future<void> initializeForFamilyUser() async {
    debugPrint('[NotificationService] initializeForFamilyUser() started');

    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('[NotificationService] currentUser null, skip FCM setup');
        return;
      }

      final isFamily = await _isCurrentUserFamily(user.uid);
      if (!isFamily) {
        debugPrint(
          '[NotificationService] User ${user.uid} bukan family, token tidak disimpan',
        );
        return;
      }

      await createSosEmergencyChannel();
      await requestNotificationPermission();

      // Deteksi fresh install: SharedPreferences terhapus saat reinstall APK.
      // Jika belum ada flag untuk user ini, paksa hapus token lama dari FCM
      // agar token baru yang valid didapatkan (token debug/release bisa berbeda).
      final prefs = await SharedPreferences.getInstance();
      final registeredKey = 'fcm_registered_${user.uid}';
      final alreadyRegistered = prefs.getBool(registeredKey) ?? false;

      if (!alreadyRegistered) {
        debugPrint(
          '[NotificationService] Fresh install terdeteksi, memaksa refresh FCM token',
        );
        try {
          await _messaging.deleteToken();
        } catch (e) {
          debugPrint('[NotificationService] deleteToken gagal (diabaikan): $e');
        }
      }

      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[NotificationService] FCM token null/kosong');
        return;
      }

      debugPrint('[NotificationService] FCM token berhasil didapat');
      await saveFcmToken(token);

      if (!alreadyRegistered) {
        await prefs.setBool(registeredKey, true);
        debugPrint('[NotificationService] FCM token terdaftar untuk install ini');
      }

      listenTokenRefresh();
    } catch (e, stackTrace) {
      debugPrint('[NotificationService] FCM setup gagal: $e');
      debugPrint('$stackTrace');
    }
  }

  Future<void> requestNotificationPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint(
      '[NotificationService] Permission status: '
      '${settings.authorizationStatus}',
    );

    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    final androidGranted = await androidImplementation
        ?.requestNotificationsPermission();
    debugPrint(
      '[NotificationService] Android notification permission: $androidGranted',
    );

    try {
      final fullScreenGranted = await androidImplementation
          ?.requestFullScreenIntentPermission();
      if (fullScreenGranted == false) {
        _fullScreenIntentAllowed = false;
      }
      debugPrint(
        '[NotificationService] Android full-screen intent permission: '
        '$fullScreenGranted',
      );
    } catch (e) {
      debugPrint(
        '[NotificationService] full-screen intent permission check failed: $e',
      );
    }
  }

  Future<void> saveFcmToken(String token) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint(
        '[NotificationService] currentUser null, token tidak disimpan',
      );
      return;
    }

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final userType = userDoc.data()?['userType'] as String?;

    if (!_isFamilyUserType(userType)) {
      debugPrint(
        '[NotificationService] userType=$userType, token tidak disimpan',
      );
      return;
    }

    final tokenCollection = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('fcmTokens');
    final tokenRef = tokenCollection.doc(token);

    final tokenDoc = await tokenRef.get();
    if (tokenDoc.exists) {
      await tokenRef.update({'updatedAt': FieldValue.serverTimestamp()});
      debugPrint(
        '[NotificationService] FCM token sudah ada, updatedAt diperbarui',
      );
      return;
    }

    // Hapus token lama untuk platform yang sama sebelum simpan yang baru.
    // Ini terjadi saat FCM me-refresh token — token lama tidak lagi valid
    // dan harus diganti agar tidak ada duplikat per platform.
    final staleSnapshot = await tokenCollection
        .where('platform', isEqualTo: _platformName)
        .get();
    for (final doc in staleSnapshot.docs) {
      if (doc.id != token) {
        await doc.reference.delete();
        debugPrint(
          '[NotificationService] Token lama dihapus: ${doc.id.substring(0, 20)}…',
        );
      }
    }

    await tokenRef.set({
      'token': token,
      'platform': _platformName,
      'userId': user.uid,
      'userType': 'family',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('[NotificationService] FCM token berhasil disimpan');
  }

  void listenTokenRefresh() {
    if (_tokenRefreshSubscription != null) {
      debugPrint('[NotificationService] Token refresh listener sudah aktif');
      return;
    }

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) async {
      debugPrint('[NotificationService] FCM token refresh diterima');
      await saveFcmToken(token);
    });

    debugPrint('[NotificationService] Token refresh listener aktif');
  }

  Future<void> createSosEmergencyChannel() async {
    if (kIsWeb) {
      debugPrint(
        '[NotificationService] Web detected, skip Android notification channel',
      );
      return;
    }

    if (_localNotificationsInitialized) {
      return;
    }

    debugPrint('Creating SOS full-screen and fallback channels');

    const initializationSettingsAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('[NotificationService] local notification clicked');
        debugPrint('[NotificationService] local payload: ${response.payload}');
        _handleLocalNotificationPayload(response.payload);
      },
    );

    final fullScreenAndroidChannel = _buildSosFullScreenAndroidChannel();
    final fallbackAndroidChannel = _buildSosAndroidChannel();
    final silentAndroidChannel = _buildSosSilentAndroidChannel();

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(fullScreenAndroidChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(fallbackAndroidChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(silentAndroidChannel);

    _localNotificationsInitialized = true;
    _debugSosSoundChoice();
    debugPrint('SOS channel created with sound and vibration');
  }

  Future<void> createSosNotificationChannel() {
    return createSosEmergencyChannel();
  }

  Future<void> _handleLocalNotificationLaunchDetails() async {
    if (kIsWeb) return;

    final details = await _localNotifications.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    final payload = response?.payload;

    if (details?.didNotificationLaunchApp == true && payload != null) {
      final data = parseNotificationPayload(payload);
      if (data == null || data['type'] != 'sos') return;
      debugPrint('full-screen notification clicked');
      final openMode = data['openMode']?.toString();
      if (openMode == 'monitoring') {
        _initialSosMonitoringPayload = _buildSosPayload(
          data,
          openMode: 'monitoring',
        );
        return;
      }

      _initialSosPayload = _buildSosPayload(data, openMode: 'fullscreen');
    }
  }

  Map<String, dynamic>? takeInitialSosPayload() {
    final payload = _initialSosPayload;
    _initialSosPayload = null;
    return payload;
  }

  Map<String, dynamic>? takeInitialSosMonitoringPayload() {
    final payload = _initialSosMonitoringPayload;
    _initialSosMonitoringPayload = null;
    return payload;
  }

  Future<void> showSosLocalNotification(Map<String, dynamic> data) async {
    if (!await _shouldShowSosForCurrentUser(data)) return;
    await createSosEmergencyChannel();
    await _showSosLocalNotificationFromData(data);
    _startSosAlarmLoop(data);
  }

  Future<void> showSosOneShotNotification(Map<String, dynamic> data) async {
    if (kIsWeb) return;
    if (data['type'] != 'sos') return;
    if (!await _shouldShowSosForCurrentUser(data)) return;

    final sosId =
        _readStringFromMap(data, 'sosId') ??
        _readStringFromMap(data, 'alertId') ??
        _readStringFromMap(data, 'id');
    if (sosId != null && !_shownOneShotSosIds.add(sosId)) {
      debugPrint('[NotificationService] one-shot SOS already shown: $sosId');
      return;
    }

    await createSosEmergencyChannel();
    await _showSosNotificationFromData(
      data,
      details: _buildSosOneShotNotificationDetails(),
    );
  }

  Future<void> showSosFullScreenNotification(Map<String, dynamic> data) async {
    if (kIsWeb) return;
    if (!await _shouldShowSosForCurrentUser(data)) return;

    debugPrint('showing full-screen SOS notification');
    await createSosEmergencyChannel();

    if (!_fullScreenIntentAllowed) {
      debugPrint('fallback notification used');
      await _showSosLocalNotificationFromData(data);
      _startSosAlarmLoop(data);
      return;
    }

    try {
      await _showSosNotificationFromData(
        data,
        details: _buildSosNotificationDetails(
          fullScreenIntent: true,
          useFullScreenChannel: true,
        ),
        openMode: 'fullscreen',
      );
      _startSosAlarmLoop(data);
    } catch (e) {
      debugPrint(
        '[NotificationService] full-screen SOS notification failed: $e',
      );
      debugPrint('fallback notification used');
      await _showSosLocalNotificationFromData(data);
      _startSosAlarmLoop(data);
    }
  }

  static Future<void> showBackgroundSosLocalNotification(
    RemoteMessage message,
  ) async {
    if (kIsWeb) return;

    await showBackgroundSosLocalNotificationFromData(
      Map<String, dynamic>.from(message.data),
    );
  }

  static Future<void> showBackgroundSosFullScreenNotification(
    RemoteMessage message,
  ) async {
    await showSosFullScreenNotificationFromData(
      Map<String, dynamic>.from(message.data),
    );
  }

  static Future<void> showSosFullScreenNotificationFromData(
    Map<String, dynamic> data,
  ) async {
    if (kIsWeb) return;
    if (data['type'] != 'sos') return;

    debugPrint('SOS FCM received');
    debugPrint('showing full-screen SOS notification');

    final plugin = FlutterLocalNotificationsPlugin();
    const initializationSettingsAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await plugin.initialize(initializationSettings);

    await _createSosChannelsForPlugin(plugin);

    try {
      await _showSosNotificationWithPlugin(
        plugin: plugin,
        data: data,
        details: _buildSosNotificationDetails(
          fullScreenIntent: true,
          useFullScreenChannel: true,
        ),
        openMode: 'fullscreen',
      );
    } catch (e) {
      debugPrint('[NotificationService] background full-screen failed: $e');
      debugPrint('fallback notification used');
      await _showSosNotificationWithPlugin(
        plugin: plugin,
        data: data,
        details: _buildSosNotificationDetails(),
      );
    }
  }

  static Future<void> showBackgroundSosLocalNotificationFromData(
    Map<String, dynamic> data,
  ) async {
    if (kIsWeb) return;
    if (data['type'] != 'sos') return;

    final plugin = FlutterLocalNotificationsPlugin();
    const initializationSettingsAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await plugin.initialize(initializationSettings);

    await _createSosChannelsForPlugin(plugin);

    await _showSosNotificationWithPlugin(
      plugin: plugin,
      data: data,
      details: _buildSosNotificationDetails(),
    );

    debugPrint('Showing SOS notification with sound and vibration');
    debugPrint('SOS local notification shown');
  }

  Future<void> _showSosLocalNotificationFromData(
    Map<String, dynamic> data,
  ) async {
    if (kIsWeb) return;

    await _showSosNotificationFromData(
      data,
      details: _buildSosNotificationDetails(),
    );
  }

  Future<void> _showSosNotificationFromData(
    Map<String, dynamic> data, {
    required NotificationDetails details,
    String openMode = 'monitoring',
  }) async {
    final title = _sosNotificationTitle;
    final body = _sosNotificationBody(data);

    debugPrint('Showing SOS notification with sound and vibration');

    await _localNotifications.show(
      sosEmergencyNotificationId,
      title,
      body,
      details,
      payload: jsonEncode(_buildSosPayload(data, openMode: openMode)),
    );

    debugPrint('SOS local notification shown');
  }

  static Future<void> _createSosChannelsForPlugin(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    debugPrint('Creating SOS full-screen and fallback channels');

    final androidImplementation = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidImplementation?.createNotificationChannel(
      _buildSosFullScreenAndroidChannel(),
    );
    await androidImplementation?.createNotificationChannel(
      _buildSosAndroidChannel(),
    );
    await androidImplementation?.createNotificationChannel(
      _buildSosSilentAndroidChannel(),
    );

    _debugSosSoundChoice();
    debugPrint('SOS channel created with sound and vibration');
  }

  static Future<void> _showSosNotificationWithPlugin({
    required FlutterLocalNotificationsPlugin plugin,
    required Map<String, dynamic> data,
    required NotificationDetails details,
    String openMode = 'monitoring',
  }) async {
    await plugin.show(
      sosEmergencyNotificationId,
      _sosNotificationTitle,
      _sosNotificationBody(data),
      details,
      payload: jsonEncode(_buildSosPayload(data, openMode: openMode)),
    );
  }

  Future<void> handleSosNotification(RemoteMessage message) async {
    final data = Map<String, dynamic>.from(message.data);
    if (!await _shouldShowSosForCurrentUser(data)) return;

    final context = _navigatorKey?.currentContext;
    if (context == null) {
      debugPrint('[NotificationService] Navigator context null for SOS dialog');
      return;
    }

    final userName = _readSosString(message, 'userName') ?? 'Pengguna';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.error),
            const SizedBox(width: 10),
            const Expanded(child: Text('SOS Darurat')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$userName membutuhkan bantuan'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  navigateToFamilyMonitoringFromSos(message);
                },
                child: const Text('Lihat Lokasi'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleForegroundSosMessage(
    RemoteMessage message,
    Map<String, dynamic> data,
  ) async {
    if (!await _shouldShowSosForCurrentUser(data)) return;
    stopSosAlarmLoop(cancelNotification: true);
    await showSosOneShotNotification(data);
    await handleSosNotification(message);
  }

  void navigateToFamilyMonitoringFromSos(RemoteMessage message) {
    _navigateToFamilyMonitoringFromData(
      Map<String, dynamic>.from(message.data),
      remainingRetries: 8,
    );
  }

  void _navigateToFamilyMonitoringFromData(
    Map<String, dynamic> data, {
    required int remainingRetries,
  }) {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      debugPrint('[NotificationService] Navigator null for SOS navigation');
      if (remainingRetries > 0) {
        Future.delayed(const Duration(milliseconds: 350), () {
          _navigateToFamilyMonitoringFromData(
            data,
            remainingRetries: remainingRetries - 1,
          );
        });
      }
      return;
    }

    final userId = _readStringFromMap(data, 'userId') ?? '';
    final familyUid =
        _readStringFromMap(data, 'familyUid') ?? _auth.currentUser?.uid ?? '';
    final args = {
      'fromSos': true,
      'userId': userId,
      'targetUid': userId,
      'familyUid': familyUid,
      'familyId': familyUid,
      'lat': _readStringFromMap(data, 'lat'),
      'lng': _readStringFromMap(data, 'lng'),
      'batteryLevel': _readStringFromMap(data, 'batteryLevel'),
      'smartCaneBatteryLevel': _readStringFromMap(
        data,
        'smartCaneBatteryLevel',
      ),
      'currentTripId': _readStringFromMap(data, 'currentTripId'),
      'userName': _readStringFromMap(data, 'userName') ?? 'Pengguna',
      'sosId': _readStringFromMap(data, 'sosId'),
      'sosData': data,
    };

    debugPrint('Navigating to FamilyMonitoringScreen from SOS');
    debugPrint('[NotificationService] Navigate to family monitoring: $args');

    navigator.pushNamedAndRemoveUntil(
      AppRoutes.familyMonitoring,
      (route) => false,
      arguments: args,
    );
    debugPrint('[NotificationService] route navigation result: pushed');
  }

  void _handleLocalNotificationPayload(
    String? payload, {
    Duration delay = const Duration(milliseconds: 150),
  }) {
    if (payload == null || payload.isEmpty) return;

    debugPrint('SOS notification clicked');

    final data = parseNotificationPayload(payload);
    if (data == null || data['type'] != 'sos') return;

    debugPrint('full-screen notification clicked');
    final openMode = data['openMode']?.toString();
    if (openMode == 'fullscreen') {
      _scheduleSosFullScreenNavigation(data, delay: delay);
      return;
    }

    _scheduleSosNavigationFromData(data, delay: delay);
  }

  void _scheduleSosNavigationFromData(
    Map<String, dynamic> data, {
    Duration delay = const Duration(milliseconds: 150),
  }) {
    Future.delayed(delay, () {
      _navigateToFamilyMonitoringFromData(data, remainingRetries: 12);
    });
  }

  void _scheduleSosFullScreenNavigation(
    Map<String, dynamic> data, {
    Duration delay = const Duration(milliseconds: 150),
  }) {
    Future.delayed(delay, () {
      _navigateToSosFullScreen(data, remainingRetries: 12);
    });
  }

  void _navigateToSosFullScreen(
    Map<String, dynamic> data, {
    required int remainingRetries,
  }) {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      debugPrint('[NotificationService] Navigator null for SOS full-screen');
      if (remainingRetries > 0) {
        Future.delayed(const Duration(milliseconds: 350), () {
          _navigateToSosFullScreen(
            data,
            remainingRetries: remainingRetries - 1,
          );
        });
      }
      return;
    }

    debugPrint('SOS full-screen opened');
    navigator.pushNamed(
      AppRoutes.sosFullScreen,
      arguments: _buildSosPayload(data),
    );
  }

  void _startSosAlarmLoop(Map<String, dynamic> data) {
    if (kIsWeb) return;

    _activeSosData = Map<String, dynamic>.from(data);
    _listenActiveSosStatus(data);

    if (_sosAlarmTimer?.isActive == true) {
      debugPrint('[NotificationService] SOS alarm loop already active');
      return;
    }

    debugPrint('[NotificationService] SOS alarm loop started');
    _sosAlarmTimer = Timer.periodic(sosAlarmRepeatInterval, (_) async {
      final latestData = _activeSosData;
      if (latestData == null || latestData['type'] != 'sos') {
        stopSosAlarmLoop();
        return;
      }

      debugPrint('[NotificationService] SOS alarm loop cycle');
      await _showSosLocalNotificationFromData(latestData);
    });
  }

  void stopSosAlarmLoop({bool cancelNotification = true}) {
    final hadActiveAlarm =
        _sosAlarmTimer != null ||
        _activeSosData != null ||
        _activeSosStatusSubscription != null;

    _sosAlarmTimer?.cancel();
    _sosAlarmTimer = null;
    _activeSosData = null;
    _activeSosStatusSubscription?.cancel();
    _activeSosStatusSubscription = null;

    if (cancelNotification && !kIsWeb) {
      _localNotifications.cancel(sosEmergencyNotificationId);
      _localNotifications.cancelAll();
    }

    if (hadActiveAlarm) {
      debugPrint('[NotificationService] SOS alarm loop stopped');
    }
  }

  Future<void> silenceSosNotification(
    Map<String, dynamic> data, {
    required bool sosResolved,
  }) async {
    if (kIsWeb) return;

    debugPrint('[NotificationService] SOS notification silenced');
    stopSosAlarmLoop(cancelNotification: false);
    await createSosEmergencyChannel();
    await _localNotifications.cancelAll();

    if (sosResolved) {
      debugPrint(
        '[NotificationService] SOS already resolved, notification removed',
      );
      return;
    }

    await _showSosNotificationFromData(
      data,
      details: _sosSilentNotificationDetails,
    );
    debugPrint('[NotificationService] Silent SOS notification shown');
  }

  void _listenActiveSosStatus(Map<String, dynamic> data) {
    final sosId =
        _readStringFromMap(data, 'sosId') ??
        _readStringFromMap(data, 'alertId') ??
        _readStringFromMap(data, 'id');
    if (sosId == null) {
      debugPrint(
        '[NotificationService] SOS id missing, skip resolved listener',
      );
      return;
    }

    _activeSosStatusSubscription?.cancel();
    _activeSosStatusSubscription = _firestore
        .collection('sos_alerts')
        .doc(sosId)
        .snapshots()
        .listen(
          (snapshot) {
            final status = snapshot.data()?['status']?.toString();
            debugPrint('[NotificationService] active SOS status: $status');
            if (status == 'resolved') {
              stopSosAlarmLoop();
            }
          },
          onError: (Object error) {
            debugPrint(
              '[NotificationService] SOS status listener failed: $error',
            );
          },
        );
  }

  void handleSosNotificationTap(String payload) {
    _handleLocalNotificationPayload(payload);
  }

  Map<String, dynamic>? parseNotificationPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;

      final data = Map<String, dynamic>.from(decoded);
      debugPrint('SOS payload parsed');
      return data;
    } catch (e) {
      debugPrint('[NotificationService] local payload decode failed: $e');
      return null;
    }
  }

  Future<bool> _isCurrentUserFamily(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (!userDoc.exists) {
      return false;
    }

    final userType = userDoc.data()?['userType'] as String?;
    return _isFamilyUserType(userType);
  }

  Future<bool> _shouldShowSosForCurrentUser(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('[NotificationService] skip SOS: currentUser null');
      return false;
    }

    final senderUid = _readStringFromMap(data, 'userId');
    if (senderUid == user.uid) {
      debugPrint('[NotificationService] skip SOS: current user is sender');
      return false;
    }

    final isFamily = await _isCurrentUserFamily(user.uid);
    if (!isFamily) {
      debugPrint('[NotificationService] skip SOS: current user is not family');
      return false;
    }

    final familyUid =
        _readStringFromMap(data, 'familyUid') ??
        _readStringFromMap(data, 'familyId');
    if (familyUid != null && familyUid != user.uid) {
      debugPrint('[NotificationService] skip SOS: familyUid mismatch');
      return false;
    }

    return true;
  }

  bool _isFamilyUserType(String? userType) {
    return userType == 'family' || userType == 'UserType.family';
  }

  bool _isSosMessage(RemoteMessage message) {
    return message.data['type'] == 'sos';
  }

  String? _readSosString(RemoteMessage message, String key) {
    final value = message.data[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String? _readStringFromMap(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static Map<String, dynamic> _buildSosPayload(
    Map<String, dynamic> data, {
    String openMode = 'monitoring',
  }) {
    return <String, dynamic>{
      'type': _readStringFromMap(data, 'type') ?? 'sos',
      'openMode': openMode,
      'userId': _readStringFromMap(data, 'userId'),
      'familyUid':
          _readStringFromMap(data, 'familyUid') ??
          _readStringFromMap(data, 'familyId'),
      'userName': _readStringFromMap(data, 'userName'),
      'lat': _readStringFromMap(data, 'lat'),
      'lng': _readStringFromMap(data, 'lng'),
      'batteryLevel': _readStringFromMap(data, 'batteryLevel'),
      'smartCaneBatteryLevel': _readStringFromMap(
        data,
        'smartCaneBatteryLevel',
      ),
      'currentTripId': _readStringFromMap(data, 'currentTripId'),
      'sosId':
          _readStringFromMap(data, 'sosId') ??
          _readStringFromMap(data, 'alertId') ??
          _readStringFromMap(data, 'id'),
      'createdAt':
          _readStringFromMap(data, 'createdAt') ??
          _readStringFromMap(data, 'timestamp'),
    };
  }

  static String get _sosNotificationTitle => '🚨 SOS Darurat';

  static String _sosNotificationBody(Map<String, dynamic> data) {
    final userName = _readStringFromMap(data, 'userName') ?? 'Pengguna';
    return '$userName membutuhkan bantuan segera karena terjatuh. ($userName needs immediate assistance due to a fall)';
  }

  String get _platformName {
    if (kIsWeb) {
      return 'web';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'android';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'ios';
    }
    return defaultTargetPlatform.name;
  }
}
