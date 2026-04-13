import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'utils/constants.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/tunanetra/tunanetra_home_screen.dart';
import 'screens/tunanetra/navigation_screen.dart';
import 'screens/tunanetra/bluetooth_screen.dart';
import 'screens/tunanetra/ebook_screen.dart';
import 'screens/tunanetra/smartcane_monitoring_screen.dart';
import 'screens/tunanetra/settings_screen.dart';
import 'screens/family/family_home_screen.dart';

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
  
  runApp(const MyApp());
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
        ),
        
        // Routes
        initialRoute: AppRoutes.splash,
        routes: {
          AppRoutes.splash: (context) => const SplashScreen(),
          AppRoutes.login: (context) => const LoginScreen(),
          AppRoutes.register: (context) => const RegisterScreen(),
          
          // Tunanetra routes
          AppRoutes.tunaNetraHome: (context) => const TunaNetraHomeScreen(),
          AppRoutes.tunaNetraNavigation: (context) => const NavigationScreen(),
          AppRoutes.tunaNetraBluetooth: (context) => const BluetoothScreen(),
          AppRoutes.tunaNetraEbook: (context) => const EbookScreen(),
          AppRoutes.tunaNetraSmartcane: (context) => const SmartcaneMonitoringScreen(),
          AppRoutes.tunaNetraSettings: (context) => const TunaNetraSettingsScreen(),
          
          // Family routes
          AppRoutes.familyHome: (context) => const FamilyHomeScreen(),
          // TODO: Add familyMonitoring and familySettings
        },
    );
  }
}