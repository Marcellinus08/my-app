// Standalone GPS accuracy testing tool - entry point terpisah dari aplikasi utama.
// Jalankan dengan: flutter run -t lib/testing/gps_accuracy_test_screen.dart
// Tidak diimpor oleh lib/main.dart dan tidak menulis data ke database.
//
// Tool ini murni membaca data lokasi dari perangkat lewat Geolocator.
// Nilai yang diuji adalah Position.accuracy, yaitu estimasi akurasi horizontal
// dalam meter yang dilaporkan oleh provider lokasi perangkat.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GpsAccuracyTestApp());
}

class GpsAccuracyTestApp extends StatelessWidget {
  const GpsAccuracyTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Accuracy Test',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const GpsAccuracyTestScreen(),
    );
  }
}

class _Sample {
  _Sample({
    required this.time,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.altitude,
    required this.speed,
    required this.heading,
  });

  final DateTime time;
  final double lat;
  final double lng;
  final double accuracy;
  final double altitude;
  final double speed;
  final double heading;
}

class GpsAccuracyTestScreen extends StatefulWidget {
  const GpsAccuracyTestScreen({super.key});

  @override
  State<GpsAccuracyTestScreen> createState() => _GpsAccuracyTestScreenState();
}

class _GpsAccuracyTestScreenState extends State<GpsAccuracyTestScreen> {
  final _placeController = TextEditingController();
  final _specificLocationController = TextEditingController();

  bool _isIndoor = true;
  bool _isLogging = false;
  bool _isSaving = false;
  String _place = '';
  String _specificLocation = '';
  String? _statusMessage;

  final List<_Sample> _samples = [];
  StreamSubscription<Position>? _positionSubscription;

  DateTime? _loggingStartedAt;
  DateTime? _lastUpdateAt;
  Timer? _statusTicker;

  static const _staleDataThreshold = Duration(seconds: 15);

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _statusTicker?.cancel();
    _placeController.dispose();
    _specificLocationController.dispose();
    super.dispose();
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('GPS/lokasi perangkat belum aktif.');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _showSnackBar('Izin lokasi ditolak.');
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar(
        'Izin lokasi ditolak permanen. Aktifkan dari pengaturan aplikasi.',
      );
      return false;
    }

    return true;
  }

  Future<void> _startLogging() async {
    final place = _placeController.text.trim();
    final specificLocation = _specificLocationController.text.trim();

    if (place.isEmpty || specificLocation.isEmpty) {
      _showSnackBar('Isi tempat dan spesifik lokasi.');
      return;
    }

    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

    setState(() {
      _place = place;
      _specificLocation = specificLocation;
      _isLogging = true;
      _samples.clear();
      _loggingStartedAt = DateTime.now();
      _lastUpdateAt = null;
      _statusMessage = null;
    });

    _statusTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          _recordPosition,
          onError: (Object error) {
            if (!mounted) return;
            setState(() => _statusMessage = 'Gagal membaca GPS: $error');
          },
        );
  }

  void _recordPosition(Position position) {
    if (!mounted) return;

    setState(() {
      _lastUpdateAt = DateTime.now();
      _samples.add(
        _Sample(
          time: DateTime.now(),
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          altitude: position.altitude,
          speed: position.speed,
          heading: position.heading,
        ),
      );
    });
  }

  void _stopLogging() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _statusTicker?.cancel();
    _statusTicker = null;
    setState(() => _isLogging = false);
  }

  String _buildCsv() {
    final buffer = StringBuffer(
      'tempat,spesifikLokasi,condition,timestamp,lat,lng,accuracyMeters,'
      'altitudeMeters,speedMetersPerSecond,headingDegrees\n',
    );
    final condition = _isIndoor ? 'indoor' : 'outdoor';
    for (final sample in _samples) {
      buffer.writeln(
        '$_place,$_specificLocation,$condition,${sample.time.toIso8601String()},'
        '${sample.lat},${sample.lng},${sample.accuracy.toStringAsFixed(3)},'
        '${sample.altitude.toStringAsFixed(3)},'
        '${sample.speed.toStringAsFixed(3)},'
        '${sample.heading.toStringAsFixed(3)}',
      );
    }
    return buffer.toString();
  }

  void _copyAsCsv() {
    Clipboard.setData(ClipboardData(text: _buildCsv()));
    _showSnackBar('${_samples.length} sample disalin sebagai CSV');
  }

  Future<void> _downloadCsv() async {
    setState(() => _isSaving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeName = '${_place}_$_specificLocation'.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/gps_accuracy_${safeName}_$timestamp.csv');
      await file.writeAsString(_buildCsv());
      if (!mounted) return;
      _showSnackBar('CSV disimpan di: ${file.path}');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Gagal menyimpan CSV: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildConnectionStatus() {
    final now = DateTime.now();

    if (_statusMessage != null) {
      return Text(
        _statusMessage!,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.red,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    if (_lastUpdateAt == null) {
      final waitedSeconds = now.difference(_loggingStartedAt!).inSeconds;
      final isStale = now.difference(_loggingStartedAt!) > _staleDataThreshold;
      return Text(
        isStale
            ? 'Belum ada data GPS setelah $waitedSeconds detik. '
                  'Pastikan lokasi perangkat aktif dan izin lokasi diberikan.'
            : 'Menunggu data GPS pertama... ($waitedSeconds detik)',
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
          ? 'Tidak ada data GPS baru sejak $secondsSinceUpdate detik lalu.'
          : 'Update GPS terakhir: $secondsSinceUpdate detik lalu',
      style: TextStyle(
        fontSize: 12,
        color: isStale ? Colors.red : Colors.green,
        fontWeight: isStale ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Map<String, double> _stats() {
    if (_samples.isEmpty) return {};
    final accuracies = _samples.map((sample) => sample.accuracy).toList();
    final mean = accuracies.reduce((a, b) => a + b) / accuracies.length;
    final variance =
        accuracies
            .map((value) => pow(value - mean, 2))
            .reduce((a, b) => a + b) /
        accuracies.length;
    return {
      'mean': mean,
      'std': sqrt(variance),
      'max': accuracies.reduce(max),
      'min': accuracies.reduce(min),
    };
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats();
    final latestSample = _samples.isEmpty ? null : _samples.last;

    return Scaffold(
      appBar: AppBar(title: const Text('GPS Accuracy Test')),
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
              'Metode uji: membaca nilai accuracy horizontal dari GPS/lokasi '
              'perangkat secara langsung. Tidak memakai ground truth Google '
              'Maps dan tidak menghitung selisih koordinat.',
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
            if (latestSample != null) ...[
              Text(
                'Akurasi terakhir: ${latestSample.accuracy.toStringAsFixed(2)} m',
              ),
              Text(
                'Koordinat terakhir: ${latestSample.lat.toStringAsFixed(7)}, '
                '${latestSample.lng.toStringAsFixed(7)}',
              ),
            ],
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Rata-rata akurasi: ${stats['mean']!.toStringAsFixed(2)} m'),
              Text('Std dev akurasi: ${stats['std']!.toStringAsFixed(2)} m'),
              Text(
                'Min / Max akurasi: ${stats['min']!.toStringAsFixed(2)} / '
                '${stats['max']!.toStringAsFixed(2)} m',
              ),
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
