import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../services/tts_service.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final TtsService _ttsService = TtsService();

  @override
  void initState() {
    super.initState();
    _initializeTts();
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.background,
              const Color(0xFFF0F4FF),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Elegant Logo with glassmorphism
                Hero(
                  tag: 'app_logo',
                  child: Center(
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.9),
                            Colors.white.withOpacity(0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 30,
                            spreadRadius: 0,
                            offset: const Offset(0, 15),
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.8),
                            blurRadius: 15,
                            spreadRadius: -5,
                            offset: const Offset(-5, -5),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: const Icon(
                          Icons.accessibility_new,
                          size: 65,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 50),
                
                // Title with elegant gradient
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFFDA22FF)],
                  ).createShader(bounds),
                  child: Text(
                    'Pilih Peran Anda',
                    style: AppTextStyles.heading1.copyWith(
                      color: Colors.white,
                      fontSize: 34,
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
                const SizedBox(height: 50),
                
                // Tunanetra Button - Modern Card
                _ModernRoleButton(
                  icon: Icons.person_rounded,
                  title: 'Pengguna Tunanetra',
                  subtitle: 'Saya adalah pengguna tongkat pintar',
                  gradient: AppColors.primaryGradient,
                  onTap: () => _selectRole(UserType.tunanetra),
                  onHover: () => _ttsService.announceButton('Pengguna Tunanetra'),
                ),
                const SizedBox(height: 20),
                
                // Family Button - Modern Card
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
      ),
    );
  }
}

class _ModernRoleButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onHover: (hovering) {
          if (hovering) onHover();
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
                color: gradient.colors.first.withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 0,
                offset: const Offset(0, 15),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                spreadRadius: -5,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: gradient.colors.first.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Icon with gradient background
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.colors.first.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
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
                      shaderCallback: (bounds) => gradient.createShader(bounds),
                      child: Text(
                        title,
                        style: AppTextStyles.heading3.copyWith(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
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
                      gradient.colors.first.withOpacity(0.15),
                      gradient.colors.first.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ShaderMask(
                  shaderCallback: (bounds) => gradient.createShader(bounds),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
