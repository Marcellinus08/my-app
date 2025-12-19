import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../utils/constants.dart';
import '../../services/tts_service.dart';
import '../../services/stt_service.dart';

class TunaNetraHomeScreen extends StatefulWidget {
  const TunaNetraHomeScreen({super.key});

  @override
  State<TunaNetraHomeScreen> createState() => _TunaNetraHomeScreenState();
}

class _TunaNetraHomeScreenState extends State<TunaNetraHomeScreen> 
    with TickerProviderStateMixin {
  final TtsService _ttsService = TtsService();
  final SttService _sttService = SttService();
  bool _isBluetoothConnected = false;
  bool _isListening = false;
  
  late AnimationController _fadeController;
  late AnimationController _rotationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeServices();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _fadeController.forward();
  }

  Future<void> _initializeServices() async {
    await _ttsService.initialize();
    await _sttService.initialize();
    
    _ttsService.speak(
      'Selamat datang di beranda. Anda memiliki empat pilihan menu'
    );
  }

  void _startVoiceAssistant() async {
    if (_isListening) {
      await _sttService.stopListening();
      setState(() => _isListening = false);
      _ttsService.speak('Asisten suara berhenti mendengarkan');
    } else {
      setState(() => _isListening = true);
      _ttsService.speak('Asisten suara aktif. Silakan bicara');
      
      await _sttService.startListening(
        onResult: (text) {
          _handleVoiceCommand(text);
          setState(() => _isListening = false);
        },
      );
    }
  }

  void _handleVoiceCommand(String command) {
    String lowerCommand = command.toLowerCase();
    _ttsService.speak('Anda berkata: $command');
    
    if (lowerCommand.contains('navigasi') || lowerCommand.contains('peta')) {
      _navigateToNavigation();
    } else if (lowerCommand.contains('bluetooth') || lowerCommand.contains('tongkat')) {
      _navigateToBluetooth();
    } else if (lowerCommand.contains('pengaturan') || lowerCommand.contains('setting')) {
      _navigateToSettings();
    } else {
      _ttsService.speak('Maaf, perintah tidak dikenali. Coba lagi.');
    }
  }

  void _navigateToNavigation() {
    _ttsService.speak('Membuka halaman navigasi');
    Navigator.pushNamed(context, AppRoutes.tunaNetraNavigation);
  }

  void _navigateToBluetooth() {
    _ttsService.speak('Membuka halaman bluetooth');
    Navigator.pushNamed(context, AppRoutes.tunaNetraBluetooth);
  }

  void _navigateToSettings() {
    _ttsService.speak('Membuka pengaturan');
    Navigator.pushNamed(context, AppRoutes.tunaNetraSettings);
  }

  void _triggerEmergency() {
    _ttsService.speak('Tombol darurat ditekan');
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.warning_rounded, size: 60, color: Color(0xFFEF4444)),
              ),
              const SizedBox(height: 20),
              const Text(
                'DARURAT',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'Mengirim lokasi Anda ke kontak darurat...',
                style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _ttsService.speak('Batal panggilan darurat');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('BATAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFAFBFC),
              AppColors.primaryLight.withOpacity(0.08),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            // Animated rotating circles background
            ...List.generate(4, (index) {
              return AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  final angle = _rotationController.value * 2 * math.pi + (index * math.pi / 2);
                  final size = 120.0 + (index * 40);
                  final distance = 150.0 + (index * 30);
                  
                  return Positioned(
                    left: MediaQuery.of(context).size.width / 2 + 
                          math.cos(angle) * distance - size / 2,
                    top: MediaQuery.of(context).size.height / 3 + 
                         math.sin(angle) * distance - size / 2,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.primaryLight.withOpacity(0.06),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
            
            // Main content with fade animation
            FadeTransition(
              opacity: _fadeAnimation,
              child: _buildMainContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return SafeArea(
          child: Column(
            children: [
              // Elegant AppBar with glassmorphism
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(24),
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
                      color: AppColors.primary.withOpacity(0.15),
                      blurRadius: 30,
                      spreadRadius: 0,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      spreadRadius: -5,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
                          child: Text(
                            'Beranda',
                            style: AppTextStyles.heading2.copyWith(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Selamat Datang Kembali',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: _isBluetoothConnected 
                            ? AppColors.successGradient
                            : LinearGradient(
                                colors: [
                                  AppColors.textSecondary.withOpacity(0.2),
                                  AppColors.textSecondary.withOpacity(0.1),
                                ],
                              ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: _isBluetoothConnected
                            ? [
                                BoxShadow(
                                  color: AppColors.success.withOpacity(0.3),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ]
                            : [],
                        border: Border.all(
                          color: _isBluetoothConnected
                              ? Colors.white.withOpacity(0.5)
                              : AppColors.textSecondary.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isBluetoothConnected 
                                ? Icons.bluetooth_connected_rounded 
                                : Icons.bluetooth_disabled_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isBluetoothConnected ? 'ON' : 'OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        children: [
                          _ModernMenuCard(
                            icon: Icons.map_rounded,
                            title: 'Navigasi',
                            gradient: AppColors.primaryGradient,
                            onTap: _navigateToNavigation,
                            onHover: () => _ttsService.announceButton('Navigasi'),
                          ),
                          _ModernMenuCard(
                            icon: Icons.bluetooth_rounded,
                            title: 'Bluetooth',
                            gradient: AppColors.successGradient,
                            onTap: _navigateToBluetooth,
                            onHover: () => _ttsService.announceButton('Bluetooth'),
                          ),
                          _ModernMenuCard(
                            icon: _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                            title: 'Asisten',
                            gradient: _isListening ? AppColors.accentGradient : const LinearGradient(
                              colors: [Color(0xFF2196F3), Color(0xFF03A9F4)],
                            ),
                            onTap: _startVoiceAssistant,
                            onHover: () => _ttsService.announceButton('Asisten'),
                          ),
                          _ModernMenuCard(
                            icon: Icons.settings_rounded,
                            title: 'Pengaturan',
                            gradient: const LinearGradient(
                              colors: [Color(0xFF64748B), Color(0xFF475569)],
                            ),
                            onTap: _navigateToSettings,
                            onHover: () => _ttsService.announceButton('Pengaturan'),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      _EmergencyButton(
                        onTap: _triggerEmergency,
                        onHover: () => _ttsService.announceButton('Darurat'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _rotationController.dispose();
    _sttService.dispose();
    super.dispose();
  }
}

class _ModernMenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final LinearGradient gradient;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _ModernMenuCard({
    required this.icon,
    required this.title,
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
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white,
                Colors.white.withOpacity(0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: gradient.colors.first.withOpacity(0.2),
                blurRadius: 25,
                spreadRadius: 0,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                spreadRadius: -5,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: gradient.colors.first.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
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
                child: Icon(icon, size: 42, color: Colors.white),
              ),
              const SizedBox(height: 14),
              ShaderMask(
                shaderCallback: (bounds) => gradient.createShader(bounds),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyButton extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _EmergencyButton({
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
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white,
                Colors.white.withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 0,
                offset: const Offset(0, 15),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                spreadRadius: -5,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: AppColors.accent.withOpacity(0.15),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  size: 38,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 18),
              ShaderMask(
                shaderCallback: (bounds) => AppColors.accentGradient.createShader(bounds),
                child: const Text(
                  'TOMBOL DARURAT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
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
