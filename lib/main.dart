import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/smart_cane_ble_service.dart';
import 'utils/constants.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/tunanetra/tunanetra_home_screen.dart';
import 'screens/tunanetra/navigation_screen.dart';
import 'screens/tunanetra/ebook_screen.dart';
import 'screens/tunanetra/settings_screen.dart';
import 'screens/family/family_home_screen.dart';
import 'screens/family/family_history_screen.dart';
import 'screens/family/emergency_sos_screen.dart';
import 'screens/family/family_manage_places_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[MAIN] background message received');
  debugPrint('[MAIN] background payload data: ${message.data}');

  if (message.data['type'] == 'sos') {
    await NotificationService.showBackgroundSosFullScreenNotification(message);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    print('\n🔥🔥🔥 [FIREBASE INITIALIZATION START] 🔥🔥🔥');

    // Initialize Firebase
    print('📡 Calling Firebase.initializeApp()...');
    final startInit = DateTime.now();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        print('❌ Firebase.initializeApp() timed out after 30s!');
        throw Exception('Firebase initialization timeout');
      },
    );

    final initTime = DateTime.now().difference(startInit).inSeconds;
    print('✅ Firebase initialized successfully in ${initTime}s!');

    print('\n🔥🔥🔥 [FIREBASE INITIALIZATION COMPLETE] 🔥🔥🔥\n');
  } catch (e) {
    print('\n❌ CRITICAL: Firebase initialization error:');
    print('   Error type: ${e.runtimeType}');
    print('   Error message: $e');
    print('   This will cause Auth and Firestore to fail!');
    print('   → Check Firebase Console: https://console.firebase.google.com/');
    print('   → Verify package name matches');
    print('   → Verify google-services.json is correct\n');
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await NotificationService.instance.initialize(
    navigatorKey: appNavigatorKey,
    requestPermission: false,
  );
  final initialSosPayload = NotificationService.instance
      .takeInitialSosPayload();
  final initialSosMonitoringPayload = NotificationService.instance
      .takeInitialSosMonitoringPayload();

  runApp(
    MyApp(
      initialSosPayload: initialSosPayload,
      initialSosMonitoringPayload: initialSosMonitoringPayload,
    ),
  );
}

/// Test Firebase Auth connection
Future<bool> _testAuthConnection() async {
  try {
    print('  Testing Auth.currentUser...');
    final user = FirebaseAuth.instance.currentUser;
    print('  Current user: ${user?.email ?? "none (expected for new app)"}');
    return true;
  } catch (e) {
    print('  ❌ Auth connection failed: $e');
    return false;
  }
}

class MyApp extends StatefulWidget {
  final Map<String, dynamic>? initialSosPayload;
  final Map<String, dynamic>? initialSosMonitoringPayload;

  const MyApp({
    super.key,
    this.initialSosPayload,
    this.initialSosMonitoringPayload,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final _AppLifecycleBleObserver _bleLifecycleObserver;
  bool _hasStartedBleAutoReconnect = false;

  @override
  void initState() {
    super.initState();
    _bleLifecycleObserver = _AppLifecycleBleObserver(
      shouldUseBle: _isTunaNetraUser,
    );
    WidgetsBinding.instance.addObserver(_bleLifecycleObserver);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBleAutoReconnect();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_bleLifecycleObserver);
    super.dispose();
  }

  Future<bool> _isTunaNetraUser() async {
    final authService = AuthService();
    if (!authService.isAuthenticated) return false;

    final userType = await authService.getUserType();
    return userType == UserType.tunanetra;
  }

  Future<void> _startBleAutoReconnect() async {
    if (_hasStartedBleAutoReconnect) return;

    final shouldUseBle = await _isTunaNetraUser();
    if (!shouldUseBle) {
      debugPrint('[MAIN] BLE auto reconnect dilewati: user bukan tunanetra');
      return;
    }

    _hasStartedBleAutoReconnect = true;
    unawaited(
      SmartCaneBleService.instance.initializeAutoReconnect(
        maxAttempts: 5,
        log: (message) => debugPrint(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      navigatorObservers: [routeObserver],
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.accent,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,

        // High contrast theme for accessibility
        textTheme: const TextTheme(
          headlineLarge: AppTextStyles.heading1,
          headlineMedium: AppTextStyles.heading2,
          headlineSmall: AppTextStyles.heading3,
          bodyLarge: AppTextStyles.bodyLarge,
          bodyMedium: AppTextStyles.bodyMedium,
        ),

        // Button theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            textStyle: AppTextStyles.button,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.fixed,
        ),
      ),

      // Routes
      initialRoute: widget.initialSosPayload != null
          ? AppRoutes.sosFullScreen
          : widget.initialSosMonitoringPayload != null
          ? AppRoutes.familyMonitoring
          : AppRoutes.splash,
      onGenerateInitialRoutes: (initialRoute) {
        if (widget.initialSosPayload != null) {
          return [
            MaterialPageRoute(
              settings: RouteSettings(
                name: AppRoutes.sosFullScreen,
                arguments: widget.initialSosPayload,
              ),
              builder: (_) =>
                  EmergencySosScreen(sosData: widget.initialSosPayload!),
            ),
          ];
        }

        if (widget.initialSosMonitoringPayload != null) {
          final args = _sosMonitoringArgs(widget.initialSosMonitoringPayload!);
          return [
            MaterialPageRoute(
              settings: RouteSettings(
                name: AppRoutes.familyMonitoring,
                arguments: args,
              ),
              builder: (_) => FamilyHistoryScreen(
                targetUid: args['targetUid'] as String? ?? '',
                familyId: args['familyId'] as String? ?? '',
                initialSosData: _extractSosRouteData(args),
              ),
            ),
          ];
        }

        return [
          MaterialPageRoute(
            settings: const RouteSettings(name: AppRoutes.splash),
            builder: (_) => const SplashScreen(),
          ),
        ];
      },
      routes: {
        AppRoutes.splash: (context) => const SplashScreen(),
        AppRoutes.login: (context) => const LoginScreen(),
        AppRoutes.register: (context) => const RegisterScreen(),

        // Tunanetra routes
        AppRoutes.tunaNetraHome: (context) => const TunaNetraHomeScreen(),
        AppRoutes.tunaNetraNavigation: (context) => const NavigationScreen(),
        AppRoutes.tunaNetraEbook: (context) => const EbookScreen(),
        AppRoutes.tunaNetraSettings: (context) =>
            const TunaNetraSettingsScreen(),

        // Family routes
        AppRoutes.familyHome: (context) {
          final args =
              ModalRoute.of(context)?.settings.arguments
                  as Map<String, dynamic>?;
          return FamilyHomeScreen(
            targetUid: args?['targetUid'] as String? ?? '',
            familyId: args?['familyId'] as String? ?? '',
            initialSosData: _extractSosRouteData(args),
          );
        },
        AppRoutes.familyMonitoring: (context) {
          final args =
              ModalRoute.of(context)?.settings.arguments
                  as Map<String, dynamic>?;
          return FamilyHistoryScreen(
            targetUid:
                args?['targetUid'] as String? ??
                args?['userId'] as String? ??
                '',
            familyId:
                args?['familyId'] as String? ??
                args?['familyUid'] as String? ??
                '',
            initialSosData: _extractSosRouteData(args),
          );
        },
        AppRoutes.sosFullScreen: (context) {
          final args =
              ModalRoute.of(context)?.settings.arguments
                  as Map<String, dynamic>?;
          return EmergencySosScreen(sosData: args ?? const {});
        },
        AppRoutes.familyManagePlaces: (context) =>
            const FamilyManagePlacesScreen(),
        // TODO: Add familySettings
      },
    );
  }
}

class _AppLifecycleBleObserver extends WidgetsBindingObserver {
  _AppLifecycleBleObserver({required this.shouldUseBle});

  final Future<bool> Function() shouldUseBle;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_reconnectIfAllowed());
  }

  Future<void> _reconnectIfAllowed() async {
    if (!await shouldUseBle()) {
      debugPrint('[MAIN] BLE resume reconnect dilewati: user bukan tunanetra');
      return;
    }

    unawaited(
      SmartCaneBleService.instance.initializeAutoReconnect(
        maxAttempts: 3,
        log: (message) => debugPrint(message),
      ),
    );
  }
}

Map<String, dynamic>? _extractSosRouteData(Map<String, dynamic>? args) {
  if (args == null) return null;

  final sosData = args['sosData'];
  if (sosData is Map<String, dynamic>) {
    return sosData;
  }

  if (args['fromSos'] == true) {
    return {
      'type': 'sos',
      'userId': args['userId'] ?? args['targetUid'],
      'familyUid': args['familyUid'] ?? args['familyId'],
      'userName': args['userName'],
      'lat': args['lat'],
      'lng': args['lng'],
      'batteryLevel': args['batteryLevel'],
      'smartCaneBatteryLevel': args['smartCaneBatteryLevel'],
      'currentTripId': args['currentTripId'],
      'sosId': args['sosId'],
    };
  }

  return null;
}

Map<String, dynamic> _sosMonitoringArgs(Map<String, dynamic> payload) {
  final userId = payload['userId']?.toString() ?? '';
  final familyUid = payload['familyUid']?.toString() ?? '';

  return {
    'fromSos': true,
    'userId': userId,
    'targetUid': userId,
    'familyUid': familyUid,
    'familyId': familyUid,
    'lat': payload['lat'],
    'lng': payload['lng'],
    'batteryLevel': payload['batteryLevel'],
    'smartCaneBatteryLevel': payload['smartCaneBatteryLevel'],
    'currentTripId': payload['currentTripId'],
    'userName': payload['userName'] ?? 'Pengguna',
    'sosId': payload['sosId'],
    'sosData': payload,
  };
}
