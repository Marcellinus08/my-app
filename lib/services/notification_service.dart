import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String sosEmergencyChannelId = 'sos_emergency_channel';
  static const String sosEmergencyChannelName = 'SOS Emergency';
  static const String sosEmergencyChannelDescription = 'Notifikasi darurat SOS';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _localNotificationsInitialized = false;

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

    await _localNotifications.initialize(initializationSettings);

    const androidChannel = AndroidNotificationChannel(
      sosEmergencyChannelId,
      sosEmergencyChannelName,
      description: sosEmergencyChannelDescription,
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    _localNotificationsInitialized = true;
    debugPrint(
      '[NotificationService] Android SOS notification channel dibuat: '
      '$sosEmergencyChannelId',
    );
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
