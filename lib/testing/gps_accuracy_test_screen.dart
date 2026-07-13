// Standalone GPS accuracy testing tool — entry point terpisah dari aplikasi utama.
// Jalankan dengan: flutter run -t lib/testing/gps_accuracy_test_screen.dart
// Tidak diimpor oleh lib/main.dart, tidak mengubah kode aplikasi produksi,
// dan TIDAK menulis data baru ke database.
//
// Tool ini hanya MEMBACA (read-only) data yang sudah ditulis aplikasi utama
// ke Firebase Realtime Database di path live_tracking/{userId} — path yang sama
// yang dipakai layar live tracking keluarga (lib/services/realtime_live_tracking_service.dart).
// Supaya ada data untuk dibaca, buka aplikasi Teman Arah yang biasa di HP dan
// aktifkan navigasi/home tracking dengan akun yang sama saat sesi uji berjalan.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:path_provider/path_provider.dart';

import '../firebase_options.dart';
import '../services/realtime_live_tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const GpsAccuracyTestApp());
}

class GpsAccuracyTestApp extends StatelessWidget {
  const GpsAccuracyTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Accuracy Test',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == null) {
          return const _LoginScreen();
        }
        return GpsAccuracyTestScreen(userId: snapshot.data!.uid);
      },
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen();

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login — GPS Accuracy Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sample {
  _Sample({
    required this.time,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.errorMeters,
  });

  final DateTime time;
  final double lat;
  final double lng;
  final double? accuracy;
  final double errorMeters;
}

class GpsAccuracyTestScreen extends StatefulWidget {
  const GpsAccuracyTestScreen({super.key, required this.userId});

  final String userId;

  @override
  State<GpsAccuracyTestScreen> createState() => _GpsAccuracyTestScreenState();
}

class _GpsAccuracyTestScreenState extends State<GpsAccuracyTestScreen> {
  final _placeController = TextEditingController();
  final _specificLocationController = TextEditingController();
  final _groundTruthLatController = TextEditingController();
  final _groundTruthLngController = TextEditingController();

  bool _isIndoor = true;
  bool _isLogging = false;
  bool _isSaving = false;
  double? _groundTruthLat;
  double? _groundTruthLng;
  String _place = '';
  String _specificLocation = '';

  final List<_Sample> _samples = [];
  StreamSubscription<Map<String, dynamic>?>? _liveTrackingSubscription;

  DateTime? _loggingStartedAt;
  DateTime? _lastUpdateAt;
  Timer? _statusTicker;

  static const _staleDataThreshold = Duration(seconds: 15);

  @override
  void dispose() {
    _liveTrackingSubscription?.cancel();
    _statusTicker?.cancel();
    _placeController.dispose();
    _specificLocationController.dispose();
    _groundTruthLatController.dispose();
    _groundTruthLngController.dispose();
    super.dispose();
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  void _startLogging() {
    final groundTruthLat = double.tryParse(_groundTruthLatController.text.trim());
    final groundTruthLng = double.tryParse(_groundTruthLngController.text.trim());
    final place = _placeController.text.trim();
    final specificLocation = _specificLocationController.text.trim();

    if (place.isEmpty ||
        specificLocation.isEmpty ||
        groundTruthLat == null ||
        groundTruthLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi tempat, spesifik lokasi, dan koordinat ground truth'),
        ),
      );
      return;
    }

    setState(() {
      _place = place;
      _specificLocation = specificLocation;
      _groundTruthLat = groundTruthLat;
      _groundTruthLng = groundTruthLng;
      _isLogging = true;
      _samples.clear();
      _loggingStartedAt = DateTime.now();
      _lastUpdateAt = null;
    });

    // Ticker cuma untuk refresh tampilan "X detik lalu", tidak memengaruhi data.
    _statusTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Read-only: mendengarkan data live_tracking/{userId} yang sudah ditulis
    // aplikasi utama, tidak menulis apa pun ke database.
    _liveTrackingSubscription =
        RealtimeLiveTrackingService.instance.watch(widget.userId).listen((data) {
      if (data == null) return;
      final lat = data['lat'];
      final lng = data['lng'];
      if (lat is! num || lng is! num) return;

      final errorMeters = _distanceMeters(
        _groundTruthLat!,
        _groundTruthLng!,
        lat.toDouble(),
        lng.toDouble(),
      );

      setState(() {
        _lastUpdateAt = DateTime.now();
        _samples.add(_Sample(
          time: DateTime.now(),
          lat: lat.toDouble(),
          lng: lng.toDouble(),
          accuracy: (data['accuracy'] as num?)?.toDouble(),
          errorMeters: errorMeters,
        ));
      });
    });
  }

  void _stopLogging() {
    _liveTrackingSubscription?.cancel();
    _liveTrackingSubscription = null;
    _statusTicker?.cancel();
    _statusTicker = null;
    setState(() => _isLogging = false);
  }

  String _buildCsv() {
    final buffer = StringBuffer(
      'tempat,spesifikLokasi,condition,timestamp,lat,lng,accuracy,errorMeters\n',
    );
    final condition = _isIndoor ? 'indoor' : 'outdoor';
    for (final sample in _samples) {
      buffer.writeln(
        '$_place,$_specificLocation,$condition,${sample.time.toIso8601String()},'
        '${sample.lat},${sample.lng},${sample.accuracy ?? ''},'
        '${sample.errorMeters.toStringAsFixed(3)}',
      );
    }
    return buffer.toString();
  }

  void _copyAsCsv() {
    Clipboard.setData(ClipboardData(text: _buildCsv()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_samples.length} sample disalin sebagai CSV')),
    );
  }

  Future<void> _downloadCsv() async {
    setState(() => _isSaving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeName = '${_place}_$_specificLocation'
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/gps_accuracy_${safeName}_$timestamp.csv');
      await file.writeAsString(_buildCsv());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV disimpan di: ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan CSV: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildConnectionStatus() {
    final now = DateTime.now();

    if (_lastUpdateAt == null) {
      final waitedSeconds = now.difference(_loggingStartedAt!).inSeconds;
      final isStale = now.difference(_loggingStartedAt!) > _staleDataThreshold;
      return Text(
        isStale
            ? '⚠ Belum ada data masuk setelah $waitedSeconds detik. '
                'Pastikan aplikasi Teman Arah utama sedang aktif navigasi/'
                'home tracking dengan akun yang sama.'
            : 'Menunggu data pertama... ($waitedSeconds detik)',
        style: TextStyle(
          fontSize: 12,
          color: isStale ? Colors.red : Colors.grey,
          fontWeight: isStale ? FontWeight.bold : FontWeight.normal,
        ),
      );
    }

    final secondsSinceUpdate = now.difference(_lastUpdateAt!).inSeconds;
    final isStale = now.difference(_lastUpdateAt!) > _staleDataThreshold;
    return Text(
      isStale
          ? '⚠ Tidak ada data baru sejak $secondsSinceUpdate detik lalu. '
              'Cek apakah aplikasi utama masih aktif tracking.'
          : 'Update terakhir: $secondsSinceUpdate detik lalu',
      style: TextStyle(
        fontSize: 12,
        color: isStale ? Colors.red : Colors.green,
        fontWeight: isStale ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Map<String, double> _stats() {
    if (_samples.isEmpty) return {};
    final errors = _samples.map((s) => s.errorMeters).toList();
    final mean = errors.reduce((a, b) => a + b) / errors.length;
    final variance =
        errors.map((e) => pow(e - mean, 2)).reduce((a, b) => a + b) / errors.length;
    return {
      'mean': mean,
      'std': sqrt(variance),
      'max': errors.reduce(max),
      'min': errors.reduce(min),
    };
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats();
    return Scaffold(
      appBar: AppBar(title: const Text('GPS Accuracy Test (read-only)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _placeController,
              enabled: !_isLogging,
              decoration: const InputDecoration(
                labelText: 'Tempat (contoh: TULT Lantai 1)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _specificLocationController,
              enabled: !_isLogging,
              decoration: const InputDecoration(
                labelText: 'Spesifik lokasi (contoh: dekat jendela)',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _groundTruthLatController,
                    enabled: !_isLogging,
                    decoration: const InputDecoration(labelText: 'Ground truth lat'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _groundTruthLngController,
                    enabled: !_isLogging,
                    decoration: const InputDecoration(labelText: 'Ground truth lng'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Indoor')),
                ButtonSegment(value: false, label: Text('Outdoor')),
              ],
              selected: {_isIndoor},
              onSelectionChanged: _isLogging
                  ? null
                  : (value) => setState(() => _isIndoor = value.first),
            ),
            const SizedBox(height: 16),
            const Text(
              'Pastikan aplikasi Teman Arah utama sedang aktif navigasi/home '
              'tracking di HP dengan akun yang sama, supaya live_tracking '
              'terus terupdate untuk dibaca di sini.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLogging ? _stopLogging : _startLogging,
              style: FilledButton.styleFrom(
                backgroundColor: _isLogging ? Colors.red : null,
              ),
              child: Text(_isLogging ? 'Stop Logging' : 'Start Logging'),
            ),
            if (_isLogging) ...[
              const SizedBox(height: 12),
              _buildConnectionStatus(),
            ],
            const SizedBox(height: 16),
            Text('Sample terkumpul: ${_samples.length}'),
            if (stats.isNotEmpty) ...[
              Text('Mean error: ${stats['mean']!.toStringAsFixed(2)} m'),
              Text('Std dev: ${stats['std']!.toStringAsFixed(2)} m'),
              Text('Min / Max: ${stats['min']!.toStringAsFixed(2)} / '
                  '${stats['max']!.toStringAsFixed(2)} m'),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _samples.isEmpty ? null : _copyAsCsv,
              child: const Text('Copy hasil sebagai CSV ke clipboard'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: (_samples.isEmpty || _isSaving) ? null : _downloadCsv,
              child: Text(_isSaving ? 'Menyimpan...' : 'Download CSV ke file'),
            ),
          ],
        ),
      ),
    );
  }
}
