import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../services/tts_service.dart';
import '../../services/bluetooth_service.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  final TtsService _ttsService = TtsService();
  final BluetoothService _bluetoothService = BluetoothService();
  bool _isScanning = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _ttsService.speak('Halaman Bluetooth. Hubungkan tongkat pintar Anda');
    
    // Listen to connection state
    _bluetoothService.connectionStateStream.listen((connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
        _ttsService.announceBluetoothStatus(connected);
      }
    });
  }

  Future<void> _scanDevices() async {
    setState(() => _isScanning = true);
    _ttsService.speak('Memindai perangkat Bluetooth');
    
    // Simulate scanning
    await Future.delayed(const Duration(seconds: 3));
    
    if (mounted) {
      setState(() => _isScanning = false);
      _ttsService.speak('Pemindaian selesai');
      
      _showDeviceDialog();
    }
  }

  void _showDeviceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Perangkat Ditemukan', style: AppTextStyles.heading3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bluetooth, size: 40, color: AppColors.primary),
              title: const Text('Smart Cane #1234', style: AppTextStyles.bodyLarge),
              subtitle: const Text('Tongkat Pintar'),
              onTap: () {
                Navigator.pop(context);
                _connectDevice();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('TUTUP', style: AppTextStyles.bodyMedium),
          ),
        ],
      ),
    );
  }

  void _connectDevice() async {
    _ttsService.speak('Menghubungkan ke tongkat pintar');
    
    // Simulate connection
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      setState(() => _isConnected = true);
      _ttsService.speak('Berhasil terhubung ke tongkat pintar');
    }
  }

  void _disconnect() async {
    _ttsService.speak('Memutuskan koneksi');
    await _bluetoothService.disconnect();
    
    if (mounted) {
      setState(() => _isConnected = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFAFBFC),
              AppColors.secondary.withOpacity(0.08),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Elegant Header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      color: AppColors.secondary.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.secondary.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppColors.successGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, size: 24),
                        color: Colors.white,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          _ttsService.speak('Kembali');
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ShaderMask(
                        shaderCallback: (bounds) => AppColors.successGradient.createShader(bounds),
                        child: Text(
                          'Bluetooth',
                          style: AppTextStyles.heading3.copyWith(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Status Card with glassmorphism
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white,
                              Colors.white.withOpacity(0.95),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: (_isConnected 
                                  ? AppColors.success 
                                  : AppColors.textSecondary).withOpacity(0.15),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                          ],
                          border: Border.all(
                            color: (_isConnected 
                                ? AppColors.success 
                                : AppColors.textSecondary).withOpacity(0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: _isConnected
                                    ? AppColors.successGradient
                                    : LinearGradient(
                                        colors: [
                                          AppColors.textSecondary.withOpacity(0.7),
                                          AppColors.textSecondary.withOpacity(0.5),
                                        ],
                                      ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isConnected
                                        ? AppColors.success
                                        : AppColors.textSecondary).withOpacity(0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isConnected 
                                    ? Icons.bluetooth_connected_rounded 
                                    : Icons.bluetooth_disabled_rounded,
                                size: 70,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ShaderMask(
                              shaderCallback: (bounds) => (_isConnected
                                  ? AppColors.successGradient
                                  : LinearGradient(
                                      colors: [
                                        AppColors.textSecondary,
                                        AppColors.textSecondary.withOpacity(0.7),
                                      ],
                                    )).createShader(bounds),
                              child: Text(
                                _isConnected ? 'Terhubung' : 'Tidak Terhubung',
                                style: AppTextStyles.heading2.copyWith(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (_isConnected) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  'Smart Cane #1234',
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      
                      // Action Buttons
                      if (!_isConnected) ...[
                        Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isScanning ? null : _scanDevices,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: _isScanning
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 3,
                                        ),
                                      ),
                                      SizedBox(width: 15),
                                      Text(
                                        'MEMINDAI...',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.search_rounded, size: 28, color: Colors.white),
                                      const SizedBox(width: 12),
                                      Text(
                                        'PINDAI PERANGKAT',
                                        style: AppTextStyles.button.copyWith(
                                          fontSize: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ] else ...[
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.error,
                                AppColors.error.withOpacity(0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.error.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _disconnect,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.bluetooth_disabled_rounded, size: 28, color: Colors.white),
                                const SizedBox(width: 12),
                                Text(
                                  'PUTUSKAN KONEKSI',
                                  style: AppTextStyles.button.copyWith(
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 30),
                      
                      // Info Card with glassmorphism
                      Container(
                        padding: const EdgeInsets.all(24),
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
                              color: AppColors.info.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(
                            color: AppColors.info.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.info.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.info_outline_rounded,
                                    color: AppColors.info,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  'Informasi',
                                  style: AppTextStyles.heading3.copyWith(
                                    color: AppColors.info,
                                    fontSize: 20,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            ...[
                              '• Pastikan Bluetooth aktif di perangkat Anda',
                              '• Nyalakan tongkat pintar',
                              '• Tongkat harus dalam jangkauan (max 10 meter)',
                              '• Koneksi akan otomatis tersambung saat Anda dekat',
                            ].map((text) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: AppColors.info,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      text.substring(2),
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        height: 1.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
