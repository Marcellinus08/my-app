import 'package:flutter/material.dart';

// App Constants
class AppConstants {
  static const String appName = 'Smart Cane Assistant';
  static const String appVersion = '1.0.0';
}

// Colors - Elegant & Sophisticated
class AppColors {
  // Primary gradient colors - Deep Purple/Blue
  static const Color primary = Color(0xFF667EEA); // Elegant Purple-Blue
  static const Color primaryLight = Color(0xFF7C8FF5);
  static const Color primaryDark = Color(0xFF5A67D8);
  
  static const Color accent = Color(0xFFFF6B9D); // Rose Pink
  static const Color accentLight = Color(0xFFFF8DB5);
  static const Color accentDark = Color(0xFFE54E82);
  
  // Secondary colors
  static const Color secondary = Color(0xFF00C9A7); // Teal
  static const Color secondaryLight = Color(0xFF4FDCC1);
  
  // Background & Surface - Softer tones
  static const Color background = Color(0xFFFAFBFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF5F7FA);
  
  // Text colors
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);
  
  // Status colors
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);
  
  // Bluetooth status
  static const Color bluetoothConnected = Color(0xFF10B981);
  static const Color bluetoothDisconnected = Color(0xFF94A3B8);
  
  // Gradient definitions - Sophisticated multi-color gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFFF6B9D), Color(0xFFFEC163)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF00C9A7), Color(0xFF00B09B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient elegantGradient = LinearGradient(
    colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2), Color(0xFFDA22FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// Text Styles - Modern & Bold
class AppTextStyles {
  static const TextStyle heading1 = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.2,
  );
  
  static const TextStyle heading2 = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.2,
  );
  
  static const TextStyle heading3 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );
  
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.5,
  );
  
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );
  
  static const TextStyle bodySmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );
  
  static const TextStyle button = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0.5,
  );
  
  static const TextStyle caption = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
  );
}

// User Types
enum UserType {
  tunanetra,
  family,
}

// Routes
class AppRoutes {
  static const String splash = '/';
  static const String roleSelection = '/role-selection';
  static const String login = '/login';
  static const String register = '/register';
  
  // Tunanetra routes
  static const String tunaNetraHome = '/tunanetra/home';
  static const String tunaNetraNavigation = '/tunanetra/navigation';
  static const String tunaNetraBluetooth = '/tunanetra/bluetooth';
  static const String tunaNetraSettings = '/tunanetra/settings';
  
  // Family routes
  static const String familyHome = '/family/home';
  static const String familyMonitoring = '/family/monitoring';
  static const String familySettings = '/family/settings';
}
