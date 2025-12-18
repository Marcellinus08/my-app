import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'utils/constants.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/role_selection_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/tunanetra/tunanetra_home_screen.dart';
import 'screens/tunanetra/navigation_screen.dart';
import 'screens/tunanetra/bluetooth_screen.dart';
import 'screens/tunanetra/settings_screen.dart';
import 'screens/family/family_home_screen.dart';
import 'services/tts_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Initialize TTS Service
        Provider<TtsService>(
          create: (_) => TtsService()..initialize(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MaterialApp(
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
          AppRoutes.roleSelection: (context) => const RoleSelectionScreen(),
          AppRoutes.login: (context) => const LoginScreen(),
          AppRoutes.register: (context) => const RegisterScreen(),
          
          // Tunanetra routes
          AppRoutes.tunaNetraHome: (context) => const TunaNetraHomeScreen(),
          AppRoutes.tunaNetraNavigation: (context) => const NavigationScreen(),
          AppRoutes.tunaNetraBluetooth: (context) => const BluetoothScreen(),
          AppRoutes.tunaNetraSettings: (context) => const TunaNetraSettingsScreen(),
          
          // Family routes
          AppRoutes.familyHome: (context) => const FamilyHomeScreen(),
          // TODO: Add familyMonitoring and familySettings
        },
      ),
    );
  }
}
