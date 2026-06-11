import 'package:flutter/material.dart';
import 'dart:async';
import '../../utils/constants.dart';
import '../../services/auth_service.dart';
import '../../services/pending_registration_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Main animation controller
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Start animations
    _mainController.forward();

    // Fade animation
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Scale animation with bounce effect
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.2, 0.7, curve: Curves.elasticOut),
      ),
    );

    // Slide animation from bottom
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _mainController,
            curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic),
          ),
        );

    // Check authentication status and navigate accordingly after 3.5 seconds
    Timer(const Duration(milliseconds: 3500), () async {
      if (mounted) {
        final authService = AuthService();
        final pendingRegistration = await PendingRegistrationService().load();

        // Check if user is already logged in
        if (authService.isAuthenticated) {
          if (pendingRegistration != null) {
            print(
              '[SPLASH] Pending email registration found, resuming registration...',
            );
            Navigator.pushReplacementNamed(context, AppRoutes.register);
            return;
          }

          print('[SPLASH] User is authenticated, checking user type...');

          // Get user type
          final userType = await authService.getUserType();

          if (userType == UserType.tunanetra) {
            print('[SPLASH] User is Tunanetra, navigating to home...');
            Navigator.pushReplacementNamed(context, AppRoutes.tunaNetraHome);
          } else if (userType == UserType.family) {
            print('[SPLASH] User is Family, navigating to family home...');
            Navigator.pushReplacementNamed(
              context,
              AppRoutes.familyHome,
              arguments: {'familyId': authService.currentUserId ?? ''},
            );
          } else {
            print('[SPLASH] User type not found, going to login');
            Navigator.pushReplacementNamed(context, AppRoutes.login);
          }
        } else {
          print('[SPLASH] User is not authenticated, navigating to login...');
          Navigator.pushReplacementNamed(context, AppRoutes.login);
        }
      }
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: AppColors.primaryDark,
        child: Stack(
          children: [
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Logo
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Image.asset(
                      'assets/images/logo_fix.png',
                      width: 160,
                      height: 160,
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(height: 50),

                  // Animated App Name
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Text(
                        'Teman Arah',
                        style: AppTextStyles.heading1.copyWith(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Simple Subtitle Description
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Temani Setiap Langkah',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                  const SizedBox(height: 100),

                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: const _SplashLoadingLine(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashLoadingLine extends StatefulWidget {
  const _SplashLoadingLine();

  @override
  State<_SplashLoadingLine> createState() => _SplashLoadingLineState();
}

class _SplashLoadingLineState extends State<_SplashLoadingLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fillAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _fillAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Indikator memuat aplikasi',
      child: SizedBox(
        width: 220,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 4,
            color: Colors.white.withValues(alpha: 0.3),
            child: AnimatedBuilder(
              animation: _fillAnimation,
              builder: (context, child) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _fillAnimation.value,
                    heightFactor: 1,
                    child: child,
                  ),
                );
              },
              child: Container(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
