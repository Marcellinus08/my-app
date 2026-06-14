import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SmartCaneBleService extends ChangeNotifier {
  SmartCaneBleService._();

  static final SmartCaneBleService instance = SmartCaneBleService._();
  static const String _rememberedCaneCodeKey = 'smart_cane_ble_code';
  static const String _rememberedCaneNameKey = 'smart_cane_ble_name';
  static const String _rememberedCaneRemoteIdKey = 'smart_cane_ble_remote_id';
  static const String _rememberedCaneAutoConnectKey =
      'smart_cane_ble_auto_connect';
  static final Guid _smartCaneServiceUuid = Guid(
    '0000a001-0000-1000-8000-00805f9b34fb',
  );
  static final Guid _sensorCharacteristicUuid = Guid(
    '0000a002-0000-1000-8000-00805f9b34fb',
  );

  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _sensorSubscription;
  final StreamController<SmartCaneSensorData> _sensorController =
      StreamController<SmartCaneSensorData>.broadcast();
  final StreamController<SmartCaneBatteryData> _batteryController =
      StreamController<SmartCaneBatteryData>.broadcast();
  final StreamController<SmartCaneButtonEvent> _buttonEventController =
      StreamController<SmartCaneButtonEvent>.broadcast();

  BluetoothDevice? _connectedDevice;
  String? _connectedBleName;
  SmartCaneSensorData? _latestSensorData;
  DateTime? _latestSensorReceivedAt;
  SmartCaneBatteryData? _latestBatteryData;
  bool _isConnecting = false;
  bool _isAutoConnecting = false;
  bool _navigationHazardAnnouncementsEnabled = false;
  String _sensorPayloadBuffer = '';
  // True setelah koneksi penuh berhasil (sensor subscribe). Diset false saat
  // user memutus koneksi secara sengaja agar auto-reconnect tidak terpicu.
  bool _shouldAutoReconnectOnDisconnect = false;

  BluetoothDevice? get connectedDevice => _connectedDevice;
  String? get connectedBleName => _connectedBleName;
  SmartCaneSensorData? get latestSensorData => _latestSensorData;
  SmartCaneBatteryData? get latestBatteryData => _latestBatteryData;
  Stream<SmartCaneSensorData> get sensorDataStream => _sensorController.stream;
  Stream<SmartCaneBatteryData> get batteryDataStream =>
      _batteryController.stream;
  Stream<SmartCaneButtonEvent> get buttonEventStream =>
      _buttonEventController.stream;
  bool get isConnecting => _isConnecting;
  bool get isAutoConnecting => _isAutoConnecting;
  bool get isConnected => _connectedDevice != null;
  bool get navigationHazardAnnouncementsEnabled =>
      _navigationHazardAnnouncementsEnabled;
  bool get isSensorRunning {
    final data = _latestSensorData;
    return isConnected &&
        _hasFreshSensorData &&
        data != null &&
        data.hasSensorOutput;
  }

  bool get isModelRunning {
    final data = _latestSensorData;
    return isConnected &&
        _hasFreshSensorData &&
        data != null &&
        data.hasModelOutput;
  }

  bool get isSmartCaneReady => isConnected && isSensorRunning && isModelRunning;

  void setNavigationHazardAnnouncementsEnabled(bool enabled) {
    if (_navigationHazardAnnouncementsEnabled == enabled) return;
    _navigationHazardAnnouncementsEnabled = enabled;
    notifyListeners();
  }

  bool get _hasFreshSensorData {
    final receivedAt = _latestSensorReceivedAt;
    if (receivedAt == null) return false;
    return DateTime.now().difference(receivedAt) <= const Duration(seconds: 10);
  }

  String deviceName(BluetoothDevice device) {
    final platformName = device.platformName.trim();
    final name = platformName.isNotEmpty ? platformName : device.advName.trim();
    return name.isEmpty ? 'Unknown BLE Device' : name;
  }

  Future<void> connectToDevice(
    BluetoothDevice device, {
    required void Function(String message) log,
    required void Function(String status) updateStatus,
  }) async {
    final name = deviceName(device);
    updateStatus('Connecting ke $name...');
    log('[BLE-STEP-06] Mencoba connect ke $name...');

    _isConnecting = true;
    notifyListeners();

    try {
      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          _connectedDevice = device;
          _connectedBleName = deviceName(device);
          notifyListeners();
        } else if (state == BluetoothConnectionState.disconnected &&
            _connectedDevice?.remoteId == device.remoteId) {
          final shouldReconnect =
              _shouldAutoReconnectOnDisconnect && !_isAutoConnecting;
          _sensorSubscription?.cancel();
          _sensorSubscription = null;
          _connectedDevice = null;
          _connectedBleName = null;
          _latestBatteryData = null;
          _latestSensorData = null;
          _latestSensorReceivedAt = null;
          _sensorPayloadBuffer = '';
          _shouldAutoReconnectOnDisconnect = false;
          updateStatus('Belum terhubung');
          notifyListeners();

          if (shouldReconnect) {
            unawaited(
              initializeAutoReconnect(
                force: true,
                maxAttempts: 3,
                log: debugPrint,
              ),
            );
          }
        }
      });

      if (device.isDisconnected) {
        await device.connect(timeout: const Duration(seconds: 15), mtu: null);
      }

      _connectedDevice = device;
      _connectedBleName = name;
      updateStatus('Terhubung ke $name');
      log('[BLE-STEP-07] Berhasil connect ke Raspberry Pi');
      notifyListeners();

      log('[BLE-STEP-09] Discovering services...');
      final services = await device.discoverServices(
        subscribeToServicesChanged: false,
      );
      log('[BLE-STEP-10] Service ditemukan: ${services.length} service');
      await _subscribeSensorData(device, services: services, log: log);
    } catch (error) {
      updateStatus('Gagal terhubung');
      log('[BLE-STEP-08] Gagal connect: $error');

      try {
        await device.disconnect();
      } catch (_) {
        // Device may already be disconnected after a failed GATT attempt.
      }
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> _subscribeSensorData(
    BluetoothDevice device, {
    required List<BluetoothService> services,
    required void Function(String message) log,
  }) async {
    final sensorCharacteristic = _findCharacteristic(
      services: services,
      serviceUuid: _smartCaneServiceUuid,
      characteristicUuid: _sensorCharacteristicUuid,
    );

    if (sensorCharacteristic == null) {
      log('[SMARTCANE_BLE] characteristic sensor a002 tidak ditemukan');
      return;
    }

    await _sensorSubscription?.cancel();
    _sensorPayloadBuffer = '';

    _sensorSubscription = sensorCharacteristic.onValueReceived.listen((value) {
      _handleSensorPayloadChunk(value, log: log);
    });

    await sensorCharacteristic.setNotifyValue(true);
    log('[SMARTCANE_BLE] ultrasonic notify subscribed');
    _shouldAutoReconnectOnDisconnect = true;
  }

  BluetoothCharacteristic? _findCharacteristic({
    required List<BluetoothService> services,
    required Guid serviceUuid,
    required Guid characteristicUuid,
  }) {
    for (final service in services) {
      if (service.uuid != serviceUuid) continue;
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == characteristicUuid) {
          return characteristic;
        }
      }
    }
    return null;
  }

  void _handleSensorPayloadChunk(
    List<int> value, {
    required void Function(String message) log,
  }) {
    if (value.isEmpty) return;

    final chunk = utf8.decode(value, allowMalformed: true).trim();
    if (chunk.isEmpty) return;

    if (_tryPublishButtonEvent(chunk)) {
      _sensorPayloadBuffer = '';
      return;
    }

    final parsedBatteryDirect = SmartCaneBatteryData.tryParse(chunk);
    if (parsedBatteryDirect != null) {
      _publishBatteryData(parsedBatteryDirect);
      _sensorPayloadBuffer = '';
      return;
    }

    final parsedDirect = SmartCaneSensorData.tryParse(chunk);
    if (parsedDirect != null) {
      _publishSensorData(parsedDirect);
      _sensorPayloadBuffer = '';
      return;
    }

    _sensorPayloadBuffer += chunk;
    final startIndex = _sensorPayloadBuffer.indexOf('{');
    final endIndex = _sensorPayloadBuffer.lastIndexOf('}');

    if (startIndex >= 0 && endIndex > startIndex) {
      final jsonPayload = _sensorPayloadBuffer.substring(
        startIndex,
        endIndex + 1,
      );
      if (_tryPublishButtonEvent(jsonPayload)) {
        _sensorPayloadBuffer = _sensorPayloadBuffer.substring(endIndex + 1);
        return;
      }
      final parsedBatteryBuffered = SmartCaneBatteryData.tryParse(jsonPayload);
      if (parsedBatteryBuffered != null) {
        _publishBatteryData(parsedBatteryBuffered);
        _sensorPayloadBuffer = _sensorPayloadBuffer.substring(endIndex + 1);
        return;
      }
      final parsedBuffered = SmartCaneSensorData.tryParse(jsonPayload);
      if (parsedBuffered != null) {
        _publishSensorData(parsedBuffered);
        _sensorPayloadBuffer = _sensorPayloadBuffer.substring(endIndex + 1);
        return;
      }
    }

    if (_sensorPayloadBuffer.length > 512) {
      _sensorPayloadBuffer = '';
    }
  }

  void _publishSensorData(SmartCaneSensorData data) {
    _latestSensorData = data;
    _latestSensorReceivedAt = DateTime.now();
    _sensorController.add(data);
    notifyListeners();
  }

  void _publishBatteryData(SmartCaneBatteryData data) {
    _latestBatteryData = data;
    _batteryController.add(data);
    notifyListeners();
  }

  bool _tryPublishButtonEvent(String payload) {
    final event = SmartCaneButtonEvent.tryParse(payload);
    if (event == null) return false;
    debugPrint('[SMARTCANE_BUTTON] event diterima: ${event.type}');
    _buttonEventController.add(event);
    return true;
  }

  Future<void> initializeAutoReconnect({
    bool force = false,
    int maxAttempts = 3,
    void Function(String message)? log,
    void Function(String status)? updateStatus,
  }) async {
    if (_connectedDevice != null || _isConnecting || _isAutoConnecting) return;

    final prefs = await SharedPreferences.getInstance();
    final shouldAutoConnect =
        prefs.getBool(_rememberedCaneAutoConnectKey) ?? false;
    final savedRemoteId = prefs.getString(_rememberedCaneRemoteIdKey);
    final savedBleName = prefs.getString(_rememberedCaneNameKey);

    if (!force &&
        (!shouldAutoConnect ||
            savedRemoteId == null ||
            savedRemoteId.trim().isEmpty)) {
      log?.call(
        '[BLE-STEP-17] Auto reconnect dilewati: belum ada tongkat tersimpan',
      );
      return;
    }

    if (savedRemoteId == null || savedRemoteId.trim().isEmpty) {
      log?.call('[BLE-STEP-17] Auto reconnect dilewati: remoteId kosong');
      return;
    }

    _isAutoConnecting = true;
    notifyListeners();
    updateStatus?.call(
      savedBleName == null
          ? 'Menghubungkan ulang tongkat...'
          : 'Menghubungkan ulang $savedBleName...',
    );
    log?.call('[BLE-STEP-17] Auto reconnect BLE dimulai: $savedRemoteId');

    try {
      if (!await FlutterBluePlus.isSupported) {
        log?.call('[BLE-STEP-17] Auto reconnect dilewati: BLE tidak didukung');
        return;
      }

      var adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on &&
          defaultTargetPlatform == TargetPlatform.android) {
        try {
          await FlutterBluePlus.turnOn(timeout: 20);
        } catch (error) {
          log?.call('[BLE-STEP-17] Gagal menyalakan Bluetooth: $error');
        }
        adapterState = await FlutterBluePlus.adapterState.first;
      }

      if (adapterState != BluetoothAdapterState.on) {
        updateStatus?.call('Bluetooth belum aktif');
        log?.call('[BLE-STEP-17] Auto reconnect dilewati: Bluetooth OFF');
        return;
      }

      final hasPermission = await _ensureBlePermissions();
      if (!hasPermission) {
        updateStatus?.call('Izin Bluetooth atau lokasi belum diberikan.');
        log?.call('[BLE-STEP-17] Auto reconnect dilewati: izin belum lengkap');
        return;
      }

      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        if (_connectedDevice != null) return;

        log?.call(
          '[BLE-STEP-17] Auto reconnect percobaan $attempt/$maxAttempts',
        );

        final directDevice = BluetoothDevice.fromId(savedRemoteId);
        await connectToDevice(
          directDevice,
          log: log ?? debugPrint,
          updateStatus: updateStatus ?? (_) {},
        );

        if (_connectedDevice != null) {
          if (_connectedBleName == 'Unknown BLE Device' &&
              savedBleName != null &&
              savedBleName.trim().isNotEmpty) {
            _connectedBleName = savedBleName;
            updateStatus?.call('Terhubung ke $savedBleName');
            notifyListeners();
          }
          log?.call('[BLE-STEP-17] Auto reconnect berhasil');
          return;
        }

        final matchedResult = await _scanForRememberedDevice(
          savedRemoteId: savedRemoteId,
          log: log,
        );

        if (matchedResult != null) {
          await connectToDevice(
            matchedResult.device,
            log: log ?? debugPrint,
            updateStatus: updateStatus ?? (_) {},
          );

          if (_connectedDevice != null) {
            log?.call('[BLE-STEP-17] Auto reconnect berhasil');
            return;
          }
        }

        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(seconds: 2 + attempt));
        }
      }

      updateStatus?.call('Belum terhubung');
      log?.call('[BLE-STEP-17] Auto reconnect gagal: tongkat tidak ditemukan');
    } catch (error) {
      updateStatus?.call('Belum terhubung');
      log?.call('[BLE-STEP-17] Auto reconnect gagal: $error');
    } finally {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      _isAutoConnecting = false;
      notifyListeners();
    }
  }

  Future<ScanResult?> _scanForRememberedDevice({
    required String savedRemoteId,
    void Function(String message)? log,
  }) async {
    StreamSubscription<List<ScanResult>>? scanSubscription;
    final scanResults = <DeviceIdentifier, ScanResult>{};

    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          scanResults[result.device.remoteId] = result;
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));

      return scanResults.values.cast<ScanResult?>().firstWhere(
        (result) => result?.device.remoteId.toString() == savedRemoteId,
        orElse: () => null,
      );
    } catch (error) {
      log?.call('[BLE-STEP-17] Scan fallback auto reconnect gagal: $error');
      return null;
    } finally {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      await scanSubscription?.cancel();
    }
  }

  Future<void> saveRememberedCane({
    required String caneCode,
    required String bleName,
    required String remoteId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rememberedCaneCodeKey, caneCode);
    await prefs.setString(_rememberedCaneNameKey, bleName);
    await prefs.setString(_rememberedCaneRemoteIdKey, remoteId);
    await prefs.setBool(_rememberedCaneAutoConnectKey, true);
    debugPrint(
      '[BLE-STEP-17] Tongkat disimpan untuk auto reconnect: $remoteId',
    );
  }

  Future<String?> getRememberedCaneRemoteId() async {
    final prefs = await SharedPreferences.getInstance();
    final shouldAutoConnect =
        prefs.getBool(_rememberedCaneAutoConnectKey) ?? false;
    if (!shouldAutoConnect) return null;

    final remoteId = prefs.getString(_rememberedCaneRemoteIdKey)?.trim();
    if (remoteId == null || remoteId.isEmpty) return null;
    return remoteId;
  }

  Future<bool> isRememberedCaneDevice(BluetoothDevice device) async {
    final remoteId = await getRememberedCaneRemoteId();
    if (remoteId == null) return false;
    return device.remoteId.toString() == remoteId;
  }

  Future<void> clearRememberedCane() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberedCaneCodeKey);
    await prefs.remove(_rememberedCaneNameKey);
    await prefs.remove(_rememberedCaneRemoteIdKey);
    await prefs.setBool(_rememberedCaneAutoConnectKey, false);
  }

  Future<bool> _ensureBlePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final currentStatuses = await Future.wait(
      permissions.map((permission) => permission.status),
    );

    if (currentStatuses.every((status) => status.isGranted)) return true;

    final requestedStatuses = await permissions.request();
    return requestedStatuses.values.every((status) => status.isGranted);
  }

  Future<void> disconnect({
    required void Function(String message) log,
    required void Function(String status) updateStatus,
  }) async {
    final device = _connectedDevice;
    if (device == null) {
      _latestBatteryData = null;
      _latestSensorData = null;
      _latestSensorReceivedAt = null;
      _sensorPayloadBuffer = '';
      updateStatus('Belum terhubung');
      log('[BLE-STEP-12] Disconnect dilewati: belum ada device terhubung');
      notifyListeners();
      return;
    }

    try {
      await device.disconnect();
      await _sensorSubscription?.cancel();
      _sensorSubscription = null;
      _connectedDevice = null;
      _connectedBleName = null;
      _latestBatteryData = null;
      _latestSensorData = null;
      _latestSensorReceivedAt = null;
      _sensorPayloadBuffer = '';
      updateStatus('Belum terhubung');
      log('[BLE-STEP-12] Disconnect berhasil');
      notifyListeners();
    } catch (error) {
      log('[BLE-STEP-12] Disconnect gagal: $error');
    }
  }
}

@immutable
class SmartCaneButtonEvent {
  const SmartCaneButtonEvent({required this.type, required this.timestamp});

  final String type;
  final DateTime timestamp;

  bool get isVoiceAssistant => isVoiceAssistantStart;
  bool get isVoiceAssistantStart => type == 'voice_assistant_start';
  bool get isVoiceAssistantStop => type == 'voice_assistant_stop';
  bool get isSos => type == 'sos';

  static SmartCaneButtonEvent? tryParse(String payload) {
    final directType = _normalizeType(payload);
    if (directType != null) {
      return SmartCaneButtonEvent(type: directType, timestamp: DateTime.now());
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;

      final rawEvent = (decoded['event'] ?? decoded['type'] ?? decoded['e'])
          ?.toString();
      if (rawEvent == null || rawEvent.trim().isEmpty) return null;

      final type = _normalizeType(rawEvent);
      if (type == null) return null;

      return SmartCaneButtonEvent(
        type: type,
        timestamp: SmartCaneSensorData._readTimestamp(decoded['timestamp']),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _normalizeType(String value) {
    final event = value.toLowerCase().trim();
    return switch (event) {
      'va' ||
      'voice' ||
      'voice_assistant' ||
      'stt' ||
      'va_down' ||
      'voice_down' ||
      'voice_start' ||
      'stt_start' ||
      'hold_start' => 'voice_assistant_start',
      'va_up' ||
      'voice_up' ||
      'voice_stop' ||
      'stt_stop' ||
      'hold_end' => 'voice_assistant_stop',
      'sos' => 'sos',
      _ => null,
    };
  }
}

@immutable
class SmartCaneBatteryData {
  const SmartCaneBatteryData({
    required this.percentage,
    required this.timestamp,
    this.voltage,
    this.currentMa,
    this.powerMw,
  });

  final int percentage;
  final DateTime timestamp;
  final double? voltage;
  final double? currentMa;
  final double? powerMw;

  String get percentageText => '$percentage%';

  static SmartCaneBatteryData? tryParse(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;

      final hasBatteryKey =
          decoded.containsKey('battery') ||
          decoded.containsKey('batteryPct') ||
          decoded.containsKey('batteryPercent') ||
          decoded.containsKey('b');
      if (!hasBatteryKey) return null;

      final rawPercentage = SmartCaneSensorData._readDouble(
        decoded['battery'] ??
            decoded['batteryPct'] ??
            decoded['batteryPercent'] ??
            decoded['b'],
      );
      if (rawPercentage == null) return null;

      return SmartCaneBatteryData(
        percentage: rawPercentage.round().clamp(0, 100),
        timestamp: SmartCaneSensorData._readTimestamp(
          decoded['timestamp'] ?? decoded['t'],
        ),
        voltage: SmartCaneSensorData._readDouble(
          decoded['voltage'] ?? decoded['v'],
        ),
        currentMa: SmartCaneSensorData._readDouble(
          decoded['currentMa'] ?? decoded['current'] ?? decoded['c'],
        ),
        powerMw: SmartCaneSensorData._readDouble(
          decoded['powerMw'] ?? decoded['power'] ?? decoded['p'],
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

@immutable
class SmartCaneSensorData {
  const SmartCaneSensorData({
    required this.distanceCm,
    required this.status,
    required this.message,
    required this.timestamp,
    this.mlLabel,
    this.mlConfidence,
    this.leftCm,
    this.centerCm,
    this.rightCm,
    this.decision,
  });

  final double? distanceCm;
  final String status;
  final String message;
  final DateTime timestamp;
  final String? mlLabel;
  final double? mlConfidence;
  final double? leftCm;
  final double? centerCm;
  final double? rightCm;
  final String? decision;

  bool get isDanger => status.toLowerCase() == 'danger';
  bool get isWarning => status.toLowerCase() == 'warning';
  bool get hasSensorOutput =>
      distanceCm != null ||
      leftCm != null ||
      centerCm != null ||
      rightCm != null;

  bool get hasModelOutput {
    final modelDecision = decision?.trim();
    final objectLabel = mlLabel?.trim();
    return (modelDecision != null && modelDecision.isNotEmpty) ||
        (objectLabel != null && objectLabel.isNotEmpty) ||
        mlConfidence != null;
  }

  String? get detectedObjectLabel => _detectedObjectLabel;
  String? get guidanceDecisionText => _decisionText;

  String get distanceText {
    final distance = distanceCm;
    if (distance == null) return 'jarak tidak tersedia';
    return '${distance.toStringAsFixed(1)} cm';
  }

  String get displayText {
    final lines = <String>[];

    if (leftCm != null || centerCm != null || rightCm != null) {
      lines.add(
        'Kiri ${_formatCm(leftCm)} | Tengah ${_formatCm(centerCm)} | Kanan ${_formatCm(rightCm)}',
      );
    }

    final decisionText = _decisionText;
    if (decisionText != null) {
      lines.add('Keputusan: $decisionText');
    }

    final statusMessage = _statusDisplayMessage;
    if (statusMessage.isNotEmpty) {
      lines.add(statusMessage);
    }

    return lines.join('\n');
  }

  String? get _decisionText {
    final rawDecision = decision?.trim();
    if (rawDecision == null || rawDecision.isEmpty) return null;

    return switch (rawDecision.toLowerCase()) {
      'maju' => 'Maju',
      'kiri' || 'belok kiri' || 'left' => 'Pindah ke kiri',
      'kanan' || 'belok kanan' || 'right' => 'Pindah ke kanan',
      'stop' || 'berhenti' => 'Berhenti',
      _ => rawDecision,
    };
  }

  String _formatCm(double? value) {
    if (value == null) return '-';
    return '${value.round()} cm';
  }

  String get _statusDisplayMessage {
    return switch (status.toLowerCase()) {
      'safe' => 'Aman',
      'warning' => _hazardMessage('Hati-hati, hambatan'),
      'danger' => _hazardMessage('Bahaya, hambatan'),
      _ => _cleanDisplayMessage(message),
    };
  }

  String _hazardMessage(String baseMessage) {
    final objectLabel = _detectedObjectLabel;
    if (objectLabel == null) return baseMessage;
    return '$baseMessage: $objectLabel';
  }

  String? get _detectedObjectLabel {
    final directLabel = _normalizeObjectLabel(mlLabel);
    if (directLabel != null) return directLabel;

    final match = RegExp(
      r'(objek|object)\s*terdeteksi\s*:\s*([^.]+)',
      caseSensitive: false,
    ).firstMatch(message);

    if (match == null) return null;
    return _normalizeObjectLabel(match.group(2));
  }

  String? _normalizeObjectLabel(String? value) {
    final label = value?.trim();
    if (label == null || label.isEmpty) return null;

    final normalized = label.toLowerCase();
    if (normalized == 'none' ||
        normalized == 'unknown' ||
        normalized == 'tidak ada' ||
        normalized == 'no detection' ||
        normalized == 'no object' ||
        normalized == 'tidak terdeteksi' ||
        normalized == '-') {
      return null;
    }

    return _translateObjectLabel(label);
  }

  String _translateObjectLabel(String label) {
    return switch (label.toLowerCase()) {
      'person' => 'orang',
      'bicycle' => 'sepeda',
      'car' => 'mobil',
      'motorcycle' || 'motorbike' => 'motor',
      'bus' => 'bus',
      'truck' => 'truk',
      'traffic light' => 'lampu lalu lintas',
      'bench' => 'bangku',
      'chair' => 'kursi',
      'dog' => 'anjing',
      'cat' => 'kucing',
      'backpack' => 'tas',
      'umbrella' => 'payung',
      'bottle' => 'botol',
      'cup' => 'gelas',
      'cell phone' || 'phone' => 'ponsel',
      'laptop' => 'laptop',
      'potted plant' => 'tanaman',
      _ => label,
    };
  }

  String _cleanDisplayMessage(String value) {
    return value
        .replaceAll(
          RegExp(r'\s*berhenti\s*sementara\.?', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'\s*(disarankan|saran|rekomendasi)\s*(untuk\s*)?(belok\s*)?(ke\s*)?(kiri|kanan|maju|berhenti)\.?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\s*(objek|object)\s*terdeteksi\s*:\s*[^.]+\.?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\s*arah\s*(kiri|kanan|maju|depan|belakang)\s+lebih\s+aman\.?',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  static SmartCaneSensorData? tryParse(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;

      final status = _normalizeStatus(decoded['status'] ?? decoded['s']);
      return SmartCaneSensorData(
        distanceCm: _readDouble(
          decoded['distanceCm'] ?? decoded['distance'] ?? decoded['d'],
        ),
        status: status,
        message:
            (decoded['message'] ??
                    decoded['msg'] ??
                    decoded['m'] ??
                    _defaultMessage(status))
                .toString(),
        timestamp: _readTimestamp(decoded['timestamp'] ?? decoded['t']),
        mlLabel: (decoded['mlLabel'] ?? decoded['label'] ?? decoded['object'])
            ?.toString(),
        mlConfidence: _readDouble(
          decoded['mlConfidence'] ?? decoded['confidence'],
        ),
        leftCm: _readDouble(decoded['left'] ?? decoded['l']),
        centerCm: _readDouble(decoded['center'] ?? decoded['c']),
        rightCm: _readDouble(decoded['right'] ?? decoded['r']),
        decision: (decoded['decision'] ?? decoded['dir'] ?? decoded['a'])
            ?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  static double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime _readTimestamp(dynamic value) {
    if (value is num) {
      final raw = value.toInt();
      if (raw > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      }
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static String _normalizeStatus(dynamic value) {
    final status = (value ?? 'unknown').toString().toLowerCase();
    return switch (status) {
      'd' => 'danger',
      'w' => 'warning',
      's' => 'safe',
      _ => status,
    };
  }

  static String _defaultMessage(String status) {
    return switch (status.toLowerCase()) {
      'danger' => 'Bahaya, hambatan dekat',
      'warning' => 'Hati-hati, ada hambatan',
      'safe' => 'Jalur aman',
      _ => 'Data sensor diterima',
    };
  }
}
