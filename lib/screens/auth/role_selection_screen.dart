import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../utils/constants.dart';
import '../../services/tts_service.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> 
    with TickerProviderStateMixin {
  final TtsService _ttsService = TtsService();
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _rotationController;
  
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeTts();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.elasticOut),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _initializeTts() async {
    await _ttsService.initialize();
    // Announce screen untuk user tunanetra
    await _ttsService.speak(
      'Selamat datang di ${AppConstants.appName}. Pilih peran Anda: Pengguna Tunanetra atau Keluarga'
    );
  }

  void _selectRole(UserType userType) {
    if (userType == UserType.tunanetra) {
      _ttsService.speak('Anda memilih sebagai Pengguna Tunanetra');
    } else {
      _ttsService.speak('Anda memilih sebagai Keluarga');
    }
    
    // Navigate to login with selected role
    Navigator.pushNamed(
      context,
      AppRoutes.login,
      arguments: userType,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.background,
              const Color(0xFFE3F2FD),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            // Animated rotating circles background
            ...List.generate(3, (index) {
              return AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  final angle = _rotationController.value * 2 * math.pi + (index * math.pi / 1.5);
                  final size = 150.0 + (index * 50);
                  final distance = 180.0 + (index * 40);
                  
                  return Positioned(
                    left: MediaQuery.of(context).size.width / 2 + 
                          math.cos(angle) * distance - size / 2,
                    top: MediaQuery.of(context).size.height / 2 + 
                         math.sin(angle) * distance - size / 2,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.primaryLight.withOpacity(0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
            
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Animated Logo
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: Hero(
                          tag: 'app_logo',
                          child: Center(
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.95),
                                    Colors.white.withOpacity(0.85),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(32),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.3),
                                    blurRadius: 40,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 20),
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.9),
                                    blurRadius: 20,
                                    spreadRadius: -5,
                                    offset: const Offset(-8, -8),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.6),
                                  width: 2.5,
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: const Icon(
                                  Icons.accessibility_new,
                                  size: 70,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 50),
                    
                    // Animated Title
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
                              child: Text(
                                'Pilih Peran Anda',
                                style: AppTextStyles.heading1.copyWith(
                                  color: Colors.white,
                                  fontSize: 36,
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            Text(
                              'Silakan pilih sebagai pengguna atau keluarga',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 50),
                    
                    // Animated Buttons
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          children: [
                            _ModernRoleButton(
                              icon: Icons.person_rounded,
                              title: 'Pengguna Tunanetra',
                              subtitle: 'Saya adalah pengguna tongkat pintar',
                              gradient: AppColors.primaryGradient,
                              onTap: () => _selectRole(UserType.tunanetra),
                              onHover: () => _ttsService.announceButton('Pengguna Tunanetra'),
                            ),
                            const SizedBox(height: 20),
                            
                            _ModernRoleButton(
                              icon: Icons.family_restroom_rounded,
                              title: 'Keluarga',
                              subtitle: 'Saya ingin memonitor keluarga saya',
                              gradient: AppColors.accentGradient,
                              onTap: () => _selectRole(UserType.family),
                              onHover: () => _ttsService.announceButton('Keluarga'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModernRoleButton extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final LinearGradient gradient;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _ModernRoleButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    required this.onHover,
  });

  @override
  State<_ModernRoleButton> createState() => _ModernRoleButtonState();
}

class _ModernRoleButtonState extends State<_ModernRoleButton> 
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (hovering) {
            setState(() => _isHovered = hovering);
            if (hovering) {
              _hoverController.forward();
              widget.onHover();
            } else {
              _hoverController.reverse();
            }
          },
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  Colors.white.withOpacity(0.95),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: widget.gradient.colors.first.withOpacity(_isHovered ? 0.3 : 0.2),
                  blurRadius: _isHovered ? 40 : 30,
                  spreadRadius: 0,
                  offset: Offset(0, _isHovered ? 20 : 15),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  spreadRadius: -5,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: widget.gradient.colors.first.withOpacity(_isHovered ? 0.2 : 0.1),
                width: _isHovered ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Icon with gradient background
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: widget.gradient,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: widget.gradient.colors.first.withOpacity(0.4),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.icon,
                    size: 45,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 20),
                
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => widget.gradient.createShader(bounds),
                        child: Text(
                          widget.title,
                          style: AppTextStyles.heading3.copyWith(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.subtitle,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Arrow with gradient
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.gradient.colors.first.withOpacity(0.15),
                        widget.gradient.colors.first.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ShaderMask(
                    shaderCallback: (bounds) => widget.gradient.createShader(bounds),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white,
                      size: _isHovered ? 24 : 22,
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
}
