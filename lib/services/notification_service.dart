import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/constants.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String sosEmergencyChannelId = 'sos_emergency_channel';
  static const String sosEmergencyChannelName = 'SOS Emergency';
  static const String sosEmergencyChannelDescription = 'Notifikasi darurat SOS';
  static const String sosCustomSoundResourceName = 'sos_alert';

  // Set true after adding android/app/src/main/res/raw/sos_alert.mp3 or .wav.
  static const bool useCustomSosSound = false;
  static final Int64List _sosVibrationPattern = Int64List.fromList([
    0,
    1000,
    500,
    1000,
    500,
    1500,
  ]);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<String>? _tokenRefreshSubscription;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _messageHandlersInitialized = false;
  bool _localNotificationsInitialized = false;

  static AndroidNotificationSound? get _sosNotificationSound {
    if (!useCustomSosSound) return null;
    return const RawResourceAndroidNotificationSound(
      sosCustomSoundResourceName,
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

  static NotificationDetails _buildSosNotificationDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        sosEmergencyChannelId,
        sosEmergencyChannelName,
        channelDescription: sosEmergencyChannelDescription,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: false,
        enableVibration: true,
        vibrationPattern: _sosVibrationPattern,
        playSound: true,
        sound: _sosNotificationSound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
  }

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

  Future<void> initializeMessageHandlers({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    if (_messageHandlersInitialized) {
      debugPrint('[NotificationService] Message handlers sudah aktif');
      return;
    }

    _navigatorKey = navigatorKey;
    _messageHandlersInitialized = true;
    await createSosNotificationChannel();
    await _handleLocalNotificationLaunchDetails();

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[NotificationService] FCM FOREGROUND');
      debugPrint('[NotificationService] payload data: ${message.data}');
      if (_isSosMessage(message)) {
        debugPrint('[NotificationService] foreground SOS received');
        showSosLocalNotification(message);
        handleSosNotification(message);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[NotificationService] FCM CLICK BACKGROUND');
      debugPrint('[NotificationService] payload data: ${message.data}');
      if (_isSosMessage(message)) {
        debugPrint('[NotificationService] notification opened');
        _scheduleSosNavigationFromData(Map<String, dynamic>.from(message.data));
      }
    });

    _messaging.getInitialMessage().then((message) {
      debugPrint('[NotificationService] FCM CLICK TERMINATED');
      debugPrint('[NotificationService] payload data: ${message?.data}');
      if (message != null && _isSosMessage(message)) {
        debugPrint('[NotificationService] initial message opened');
        _scheduleSosNavigationFromData(
          Map<String, dynamic>.from(message.data),
          delay: const Duration(milliseconds: 700),
        );
      }
    });
  }

  Future<void> initializeForFamilyUser() async {
    debugPrint('[NotificationService] initializeForFamilyUser() started');

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

    await createSosNotificationChannel();
    await requestNotificationPermission();

    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('[NotificationService] FCM token null/kosong');
      return;
    }

    debugPrint('[NotificationService] FCM token berhasil didapat: $token');
    await saveFcmToken(token);
    listenTokenRefresh();
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

    final tokenRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('fcmTokens')
        .doc(token);

    final tokenDoc = await tokenRef.get();
    if (tokenDoc.exists) {
      await tokenRef.update({'updatedAt': FieldValue.serverTimestamp()});
      debugPrint(
        '[NotificationService] FCM token sudah ada, updatedAt diperbarui',
      );
      return;
    }

    await tokenRef.set({
      'token': token,
      'platform': _platformName,
      'userId': user.uid,
      'userType': 'family',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint(
      '[NotificationService] FCM token berhasil disimpan: '
      'users/${user.uid}/fcmTokens/$token',
    );
  }

  void listenTokenRefresh() {
    if (_tokenRefreshSubscription != null) {
      debugPrint('[NotificationService] Token refresh listener sudah aktif');
      return;
    }

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) async {
      debugPrint('[NotificationService] FCM token refresh diterima: $token');
      await saveFcmToken(token);
    });

    debugPrint('[NotificationService] Token refresh listener aktif');
  }

  Future<void> createSosNotificationChannel() async {
    if (_localNotificationsInitialized) {
      return;
    }

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

    final androidChannel = _buildSosAndroidChannel();

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    _localNotificationsInitialized = true;
    _debugSosSoundChoice();
    debugPrint(
      '[NotificationService] Android SOS notification channel dibuat: '
      '$sosEmergencyChannelId',
    );
  }

  Future<void> _handleLocalNotificationLaunchDetails() async {
    final details = await _localNotifications.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    final payload = response?.payload;

    if (details?.didNotificationLaunchApp == true && payload != null) {
      debugPrint('[NotificationService] local notification launch details');
      debugPrint('[NotificationService] local payload: $payload');
      _handleLocalNotificationPayload(
        payload,
        delay: const Duration(milliseconds: 700),
      );
    }
  }

  Future<void> showSosLocalNotification(RemoteMessage message) async {
    await createSosNotificationChannel();
    final data = Map<String, dynamic>.from(message.data);
    await _showSosLocalNotificationFromData(data);
  }

  static Future<void> showBackgroundSosLocalNotification(
    RemoteMessage message,
  ) async {
    final data = Map<String, dynamic>.from(message.data);
    if (data['type'] != 'sos') return;

    debugPrint('[NotificationService] background message received');
    debugPrint('[NotificationService] background payload data: $data');

    final plugin = FlutterLocalNotificationsPlugin();
    const initializationSettingsAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await plugin.initialize(initializationSettings);

    final androidChannel = _buildSosAndroidChannel();

    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);
    _debugSosSoundChoice();
    debugPrint(
      '[NotificationService] Android SOS notification channel dibuat: '
      '$sosEmergencyChannelId',
    );

    final title = _readStringFromMap(data, 'title') ?? 'SOS Darurat';
    final body =
        _readStringFromMap(data, 'body') ?? 'Pengguna membutuhkan bantuan';

    await plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      _buildSosNotificationDetails(),
      payload: jsonEncode(data),
    );

    debugPrint('[NotificationService] SOS local notification ditampilkan');
  }

  Future<void> _showSosLocalNotificationFromData(
    Map<String, dynamic> data,
  ) async {
    final title = _readStringFromMap(data, 'title') ?? 'SOS Darurat';
    final body =
        _readStringFromMap(data, 'body') ?? 'Pengguna membutuhkan bantuan';

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      _buildSosNotificationDetails(),
      payload: jsonEncode(data),
    );

    debugPrint('[NotificationService] SOS local notification ditampilkan');
  }

  Future<void> handleSosNotification(RemoteMessage message) async {
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
        content: Text('$userName membutuhkan bantuan'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Tutup'),
          ),
          ElevatedButton(
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
        ],
      ),
    );
  }

  void navigateToFamilyMonitoringFromSos(RemoteMessage message) {
    _navigateToFamilyMonitoringFromData(
      Map<String, dynamic>.from(message.data),
      remainingRetries: 8,
    );
  }

  void _scheduleSosNavigationFromData(
    Map<String, dynamic> data, {
    Duration delay = const Duration(milliseconds: 150),
  }) {
    Future.delayed(delay, () {
      _navigateToFamilyMonitoringFromData(data, remainingRetries: 12);
    });
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
      'currentTripId': _readStringFromMap(data, 'currentTripId'),
      'userName': _readStringFromMap(data, 'userName') ?? 'Pengguna',
      'sosData': data,
    };

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

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;

      final data = Map<String, dynamic>.from(decoded);
      if (data['type'] != 'sos') return;

      _scheduleSosNavigationFromData(data, delay: delay);
    } catch (e) {
      debugPrint('[NotificationService] local payload decode failed: $e');
    }
  }

  Future<bool> _isCurrentUserFamily(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (!userDoc.exists) {
      debugPrint('[NotificationService] users/$uid tidak ditemukan');
      return false;
    }

    final userType = userDoc.data()?['userType'] as String?;
    debugPrint('[NotificationService] Firestore userType: $userType');
    return _isFamilyUserType(userType);
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

  String get _platformName {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'android';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'ios';
    }
    return defaultTargetPlatform.name;
  }
}
