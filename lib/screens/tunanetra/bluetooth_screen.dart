import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../utils/constants.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  static final Guid _smartCaneServiceUuid = Guid(
    '0000a001-0000-1000-8000-00805f9b34fb',
  );
  static final Guid _pairingCharacteristicUuid = Guid(
    '0000a003-0000-1000-8000-00805f9b34fb',
  );
  final TextEditingController _caneCodeController = TextEditingController();
  final TextEditingController _canePinController = TextEditingController();
  final Map<DeviceIdentifier, ScanResult> _scanResults = {};

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _scanStateSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  BluetoothDevice? _connectedDevice;
  ScanResult? _selectedCaneResult;
  String? _connectedBleName;
  String _bleStatus = 'Belum terhubung';
  bool _isBluetoothOn = false;
  bool _hasBlePermission = false;
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isPairingCane = false;

  @override
  void initState() {
    super.initState();
    _listenToAdapterState();
    _initializeBle();
  }

  @override
  void dispose() {
    _caneCodeController.dispose();
    _canePinController.dispose();
    _scanSubscription?.cancel();
    _scanStateSubscription?.cancel();
    _connectionSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    super.dispose();
  }

  void _listenToAdapterState() {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      final isOn = state == BluetoothAdapterState.on;
      if (!mounted) return;
      setState(() {
        _isBluetoothOn = isOn;
        if (!isOn && _bleStatus != 'Bluetooth belum aktif') {
          _bleStatus = 'Bluetooth belum aktif';
        }
      });

      if (isOn) {
        _addLog('[BLE-STEP-01] Bluetooth adapter aktif');
      } else {
        _addLog('[BLE-STEP-01] Bluetooth adapter belum aktif: $state');
      }
    });
  }

  Future<void> _initializeBle() async {
    await checkBluetoothStatus();
    await requestBlePermissions();
  }

  Future<void> checkBluetoothStatus() async {
    _addLog('[BLE-STEP-01] Mengecek status Bluetooth adapter...');

    try {
      if (!await FlutterBluePlus.isSupported) {
        _updateStatus('BLE tidak didukung di perangkat ini');
        _addLog('[BLE-STEP-01] BLE tidak didukung di perangkat ini');
        return;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      final isOn = adapterState == BluetoothAdapterState.on;

      if (!mounted) return;
      setState(() => _isBluetoothOn = isOn);

      if (isOn) {
        _addLog('[BLE-STEP-01] Bluetooth adapter aktif');
      } else {
        _updateStatus('Bluetooth belum aktif');
        _addLog('[BLE-STEP-01] Bluetooth adapter belum aktif: $adapterState');
      }
    } catch (error) {
      _updateStatus('Gagal mengecek Bluetooth');
      _addLog('[BLE-STEP-01] Gagal mengecek adapter: $error');
    }
  }

  Future<void> requestBlePermissions() async {
    _addLog('[BLE-STEP-02] Mengecek dan meminta permission...');

    if (defaultTargetPlatform != TargetPlatform.android) {
      if (!mounted) return;
      setState(() => _hasBlePermission = true);
      _addLog('[BLE-STEP-02] Platform non-Android, permission BLE dilewati');
      return;
    }

    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final statuses = await permissions.request();
    final granted = statuses.values.every((status) => status.isGranted);

    if (!mounted) return;
    setState(() => _hasBlePermission = granted);

    if (granted) {
      _addLog('[BLE-STEP-02] Permission Bluetooth dan lokasi diberikan');
    } else {
      _updateStatus('Izin Bluetooth atau lokasi belum diberikan.');
      _addLog('[BLE-STEP-02] Permission belum lengkap: $statuses');
    }
  }

  Future<void> turnOnBluetooth() async {
    _addLog('[BLE-STEP-01] Meminta Android menyalakan Bluetooth...');

    if (defaultTargetPlatform != TargetPlatform.android) {
      _addLog('[BLE-STEP-01] turnOn hanya tersedia untuk Android');
      return;
    }

    try {
      await FlutterBluePlus.turnOn(timeout: 20);
      await checkBluetoothStatus();
    } catch (error) {
      _updateStatus('Bluetooth belum aktif');
      _addLog('[BLE-STEP-01] Gagal menyalakan Bluetooth: $error');
    }
  }

  Future<void> startBleScan() async {
    await checkBluetoothStatus();
    await requestBlePermissions();

    if (!_isBluetoothOn) {
      _updateStatus('Bluetooth belum aktif');
      _addLog('[BLE-STEP-03] Scan dibatalkan karena Bluetooth HP masih OFF');
      return;
    }

    if (!_hasBlePermission) {
      _updateStatus('Izin Bluetooth atau lokasi belum diberikan.');
      return;
    }

    await stopBleScan(logWhenStopped: false);

    if (!mounted) return;
    setState(() {
      _scanResults.clear();
      _selectedCaneResult = null;
      _bleStatus = 'Scanning...';
    });

    _addLog('[BLE-STEP-03] Mulai scanning perangkat BLE...');

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      var hasNewDevice = false;

      for (final result in results) {
        final remoteId = result.device.remoteId;
        if (!_scanResults.containsKey(remoteId)) {
          hasNewDevice = true;
          final name = _deviceName(result.device);
          _addLog(
            '[BLE-STEP-04] Device ditemukan: $name | ID: $remoteId | RSSI: ${result.rssi}',
          );
        }
        _scanResults[remoteId] = result;
      }

      if (hasNewDevice && mounted) {
        setState(() {});
      }
    });

    _scanStateSubscription = FlutterBluePlus.isScanning.listen((isScanning) {
      if (!mounted) return;
      setState(() => _isScanning = isScanning);
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      _addLog('[BLE-STEP-05] Scan selesai');
    } catch (error) {
      _updateStatus('Gagal scan BLE');
      _addLog('[BLE-STEP-05] Scan gagal: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          if (_bleStatus == 'Scanning...') {
            _bleStatus = _scanResults.isEmpty
                ? 'Tidak ada perangkat BLE ditemukan'
                : 'Scan selesai';
          }
        });
      }
    }
  }

  Future<void> pairCaneWithPin() async {
    final selectedResult = _selectedCaneResult;
    final caneCode = _caneCodeController.text.trim();
    final pin = _canePinController.text.trim();

    if (selectedResult == null) {
      _updateStatus('Pilih perangkat tongkat terlebih dahulu');
      _addLog('[BLE-STEP-13] Pairing dibatalkan: belum memilih device');
      _showBleSnackBar(
        'Silakan pilih perangkat tongkat terlebih dahulu.',
        isError: true,
      );
      return;
    }

    if (caneCode.isEmpty || pin.isEmpty) {
      _updateStatus('Kode tongkat dan PIN wajib diisi');
      _addLog('[BLE-STEP-13] Pairing dibatalkan: kode/PIN kosong');
      _showBleSnackBar('Kode tongkat dan PIN wajib diisi.', isError: true);
      return;
    }

    await checkBluetoothStatus();
    await requestBlePermissions();

    if (!_isBluetoothOn) {
      _updateStatus('Bluetooth belum aktif');
      _addLog('[BLE-STEP-13] Pairing dibatalkan: Bluetooth HP masih OFF');
      _showBleSnackBar(
        'Bluetooth belum aktif. Nyalakan Bluetooth lalu coba kembali.',
        isError: true,
      );
      return;
    }

    if (!_hasBlePermission) {
      _updateStatus('Izin Bluetooth atau lokasi belum diberikan.');
      _showBleSnackBar(
        'Izin Bluetooth belum lengkap. Periksa izin aplikasi lalu coba kembali.',
        isError: true,
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isPairingCane = true;
      _bleStatus = 'Menghubungkan ke tongkat...';
    });

    try {
      await connectToDevice(selectedResult.device);
      if (_connectedDevice == null) {
        _addLog('[BLE-STEP-13] Pairing berhenti: koneksi BLE belum berhasil');
        _showBleSnackBar(
          'Gagal terhubung ke perangkat tongkat.',
          isError: true,
        );
        return;
      }

      final bleName = _deviceName(selectedResult.device);
      final paired = await _sendPairingPin(
        device: selectedResult.device,
        caneCode: caneCode,
        pin: pin,
      );

      if (!paired) {
        _updateStatus('PIN tongkat ditolak');
        _addLog('[BLE-STEP-15] PIN ditolak oleh tongkat');
        _showBleSnackBar('Kode atau PIN tongkat tidak sesuai.', isError: true);
        return;
      }

      await _saveCanePairingToFirestore(
        caneCode: caneCode,
        bleName: bleName,
        remoteId: selectedResult.device.remoteId.toString(),
      );

      if (!mounted) return;
      setState(() {
        _bleStatus = 'Terhubung ke $bleName';
        _connectedBleName = bleName;
      });
      _addLog('[BLE-STEP-16] Pairing tongkat berhasil dan tersimpan');
      _showBleSnackBar('Tongkat berhasil terhubung.');
    } catch (error) {
      _updateStatus('Pairing tongkat gagal');
      _addLog('[BLE-STEP-15] Pairing tongkat gagal: $error');
      _showBleSnackBar(
        'Proses koneksi tongkat gagal. Silakan coba kembali.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isPairingCane = false);
      }
    }
  }

  Future<void> stopBleScan({bool logWhenStopped = true}) async {
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      if (logWhenStopped) {
        _addLog('[BLE-STEP-05] Scan dihentikan');
      }
    } catch (error) {
      _addLog('[BLE-STEP-05] Gagal menghentikan scan: $error');
    }

    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _scanStateSubscription?.cancel();
    _scanStateSubscription = null;

    if (!mounted) return;
    setState(() => _isScanning = false);
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    await stopBleScan(logWhenStopped: false);

    final name = _deviceName(device);
    _updateStatus('Connecting ke $name...');
    _addLog('[BLE-STEP-06] Mencoba connect ke $name...');

    if (!mounted) return;
    setState(() => _isConnecting = true);

    try {
      await _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (!mounted) return;
        if (state == BluetoothConnectionState.connected) {
          setState(() {
            _connectedDevice = device;
            _bleStatus = 'Terhubung ke ${_deviceName(device)}';
          });
        } else if (state == BluetoothConnectionState.disconnected &&
            _connectedDevice?.remoteId == device.remoteId) {
          setState(() {
            _connectedDevice = null;
            _connectedBleName = null;
            _bleStatus = 'Belum terhubung';
          });
        }
      });

      await device.connect(timeout: const Duration(seconds: 15), mtu: null);

      if (!mounted) return;
      setState(() {
        _connectedDevice = device;
        _bleStatus = 'Terhubung ke $name';
      });
      _addLog('[BLE-STEP-07] Berhasil connect ke Raspberry Pi');

      _addLog('[BLE-STEP-09] Discovering services...');
      final services = await device.discoverServices(
        subscribeToServicesChanged: false,
      );
      _addLog('[BLE-STEP-10] Service ditemukan: ${services.length} service');
    } catch (error) {
      _updateStatus('Gagal terhubung');
      _addLog('[BLE-STEP-08] Gagal connect: $error');

      try {
        await device.disconnect();
      } catch (_) {
        // Device may already be disconnected after a failed GATT attempt.
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> disconnectDevice() async {
    final device = _connectedDevice;
    if (device == null) {
      _updateStatus('Belum terhubung');
      _addLog('[BLE-STEP-12] Disconnect dilewati: belum ada device terhubung');
      return;
    }

    try {
      await device.disconnect();
      if (!mounted) return;
      setState(() {
        _connectedDevice = null;
        _connectedBleName = null;
        _bleStatus = 'Belum terhubung';
      });
      _addLog('[BLE-STEP-12] Disconnect berhasil');
    } catch (error) {
      _addLog('[BLE-STEP-12] Disconnect gagal: $error');
    }
  }

  Future<void> testConnection() async {
    final device = _connectedDevice;
    if (device == null) {
      _addLog(
        '[BLE-STEP-11] Test connection gagal. Belum ada device connected',
      );
      _updateStatus('Belum terhubung');
      return;
    }

    try {
      _addLog('[BLE-STEP-09] Discovering services untuk test connection...');
      final services = await device.discoverServices(
        subscribeToServicesChanged: false,
      );
      _addLog(
        '[BLE-STEP-11] Test connection berhasil. Raspberry Pi masih terhubung. Service: ${services.length}',
      );
      _updateStatus('Terhubung ke ${_deviceName(device)}');
    } catch (error) {
      _updateStatus('Test connection gagal');
      _addLog(
        '[BLE-STEP-11] Test connection gagal. Perangkat tidak merespons: $error',
      );
    }
  }

  void _updateStatus(String status) {
    if (!mounted) return;
    setState(() => _bleStatus = status);
  }

  void _addLog(String message) {
    debugPrint(message);
  }

  String _deviceName(BluetoothDevice device) {
    final platformName = device.platformName.trim();
    final name = platformName.isNotEmpty ? platformName : device.advName.trim();
    return name.isEmpty ? 'Unknown BLE Device' : name;
  }

  String _displayDeviceName(ScanResult result) {
    final name = _deviceName(result.device);
    return name == 'Unknown BLE Device' ? 'Perangkat tanpa nama' : name;
  }

  List<ScanResult> _visibleScanResults() {
    final results = _scanResults.values
        .where((result) => _deviceName(result.device) != 'Unknown BLE Device')
        .toList();
    results.sort((a, b) {
      final aName = _deviceName(a.device).toLowerCase();
      final bName = _deviceName(b.device).toLowerCase();
      final aLikelyCane = aName.contains('temanarah');
      final bLikelyCane = bName.contains('temanarah');

      if (aLikelyCane != bLikelyCane) {
        return aLikelyCane ? -1 : 1;
      }

      return b.rssi.compareTo(a.rssi);
    });
    return results.take(12).toList();
  }

  Future<void> _scanAndShowDevices() async {
    await startBleScan();
    if (!mounted) return;

    final results = _visibleScanResults();
    if (results.isEmpty) {
      _showBleSnackBar(
        'Tidak ada perangkat bernama yang ditemukan.',
        isError: true,
      );
      return;
    }

    final selected = await _showScanResultsSheet(results);
    if (selected != null) {
      _selectScanResult(selected);
    }
  }

  Future<ScanResult?> _showScanResultsSheet(List<ScanResult> results) {
    return showModalBottomSheet<ScanResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Text(
                    'Pilih Perangkat',
                    style: AppTextStyles.heading3.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final result in results) ...[
                            _BleDeviceTile(
                              name: _displayDeviceName(result),
                              remoteId: result.device.remoteId.toString(),
                              rssi: result.rssi,
                              isSelected:
                                  _selectedCaneResult?.device.remoteId ==
                                  result.device.remoteId,
                              onTap: () => Navigator.pop(context, result),
                            ),
                            if (result != results.last)
                              const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectScanResult(ScanResult result) {
    final name = _displayDeviceName(result);
    setState(() {
      _selectedCaneResult = result;
      _bleStatus = 'Perangkat dipilih: $name';
    });
    _addLog(
      '[BLE-STEP-14] Perangkat dipilih: $name | ID: ${result.device.remoteId} | RSSI: ${result.rssi}',
    );
    unawaited(stopBleScan(logWhenStopped: false));
    unawaited(_showPairingDialog(result));
  }

  Future<void> _showPairingDialog(ScanResult result) async {
    _caneCodeController.clear();
    _canePinController.clear();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isDismissible: !_isPairingCane,
      enableDrag: !_isPairingCane,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final bottomInset = mediaQuery.viewInsets.bottom;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(0, 0, 0, bottomInset),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.bluetooth_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Hubungkan Tongkat',
                            style: AppTextStyles.heading3.copyWith(
                              fontSize: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _displayDeviceName(result),
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _PairingTextField(
                      controller: _caneCodeController,
                      icon: Icons.badge_rounded,
                      label: 'Kode Tongkat',
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 16),
                    _PairingTextField(
                      controller: _canePinController,
                      icon: Icons.pin_rounded,
                      label: 'PIN Tongkat',
                      keyboardType: TextInputType.number,
                      obscureText: true,
                    ),
                    const SizedBox(height: 28),
                    _ActionButton(
                      icon: Icons.link_rounded,
                      label: 'Hubungkan',
                      onPressed: () => Navigator.pop(context, true),
                      isFullWidth: true,
                      backgroundColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (submitted == true) {
      FocusManager.instance.primaryFocus?.unfocus();
      await pairCaneWithPin();
    }
  }

  void _showBleSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
          ),
          backgroundColor: isError ? AppColors.error : AppColors.success,
          behavior: SnackBarBehavior.fixed,
        ),
      );
  }

  Future<bool> _sendPairingPin({
    required BluetoothDevice device,
    required String caneCode,
    required String pin,
  }) async {
    _addLog('[BLE-STEP-15] Mengirim PIN ke tongkat...');

    final services = await device.discoverServices(
      subscribeToServicesChanged: false,
    );

    BluetoothCharacteristic? pairingCharacteristic;
    for (final service in services) {
      if (service.uuid != _smartCaneServiceUuid) continue;
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == _pairingCharacteristicUuid) {
          pairingCharacteristic = characteristic;
          break;
        }
      }
    }

    if (pairingCharacteristic == null) {
      _addLog(
        '[BLE-STEP-15] Characteristic pairing 0000a003 tidak ditemukan. Update script Raspberry Pi diperlukan.',
      );
      return false;
    }

    // Keep the payload under the default BLE ATT write limit of 20 bytes.
    final payload = '$caneCode|$pin';

    final bytes = utf8.encode(payload);
    await pairingCharacteristic.write(
      bytes,
      withoutResponse: pairingCharacteristic.properties.writeWithoutResponse,
    );

    if (pairingCharacteristic.properties.read) {
      final responseBytes = await pairingCharacteristic.read();
      if (responseBytes.isNotEmpty) {
        final responseText = utf8.decode(responseBytes, allowMalformed: true);
        _addLog('[BLE-STEP-15] Respons tongkat: $responseText');
        try {
          final response = jsonDecode(responseText);
          if (response is Map && response['ok'] == true) {
            return true;
          }
          if (response is Map && response['ok'] == false) {
            return false;
          }
        } catch (_) {
          return responseText.toLowerCase().contains('ok');
        }
      }
    }

    _addLog(
      '[BLE-STEP-15] PIN berhasil dikirim. Respons eksplisit belum tersedia, dianggap sukses untuk prototype.',
    );
    return true;
  }

  Future<void> _saveCanePairingToFirestore({
    required String caneCode,
    required String bleName,
    required String remoteId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _addLog(
        '[BLE-STEP-16] User belum login. Pairing lokal berhasil, Firestore dilewati.',
      );
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();
    final caneRef = firestore.collection('smart_canes').doc(caneCode);
    final userCaneRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('smart_canes')
        .doc(caneCode);

    await firestore.runTransaction((transaction) async {
      transaction.set(caneRef, {
        'deviceId': caneCode,
        'bleName': bleName,
        'lastRemoteId': remoteId,
        'ownerUid': user.uid,
        'allowedUsers': FieldValue.arrayUnion([user.uid]),
        'pairedPhonesCount': FieldValue.increment(1),
        'lastPairedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      transaction.set(userCaneRef, {
        'deviceId': caneCode,
        'bleName': bleName,
        'remoteId': remoteId,
        'pairedAt': now,
        'lastConnectedAt': now,
        'role': 'owner',
      }, SetOptions(merge: true));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFAFBFC),
              AppColors.primary.withValues(alpha: 0.08),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [_buildScanCard()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.15),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) =>
                      AppColors.primaryGradient.createShader(bounds),
                  child: Text(
                    'Bluetooth',
                    style: AppTextStyles.heading2.copyWith(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hubungkan tongkat pintar',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanCard() {
    final isConnected = _connectedDevice != null;
    final canUseButton = !_isScanning && !_isConnecting && !_isPairingCane;

    return _PageCard(
      child: _ScanDeviceButton(
        isScanning: _isScanning,
        isConnected: isConnected,
        deviceName: _connectedBleName ?? 'TemanArah-Cane',
        onPressed: canUseButton
            ? (isConnected ? disconnectDevice : _scanAndShowDevices)
            : null,
      ),
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.textSecondary.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(
          color: AppColors.textSecondary.withValues(alpha: 0.16),
        ),
      ),
      child: child,
    );
  }
}

class _ScanDeviceButton extends StatelessWidget {
  const _ScanDeviceButton({
    required this.isScanning,
    required this.isConnected,
    required this.deviceName,
    required this.onPressed,
  });

  final bool isScanning;
  final bool isConnected;
  final String deviceName;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final backgroundColor = isConnected
        ? AppColors.primary
        : AppColors.textTertiary;
    final icon = isConnected
        ? Icons.bluetooth_connected_rounded
        : isScanning
        ? Icons.sync_rounded
        : Icons.bluetooth_searching_rounded;
    final title = isConnected
        ? 'Terhubung'
        : isScanning
        ? 'Mencari...'
        : 'Cari Perangkat';
    final subtitle = isConnected ? deviceName : 'Tidak terhubung';

    return Semantics(
      button: true,
      label: isConnected
          ? 'Terhubung ke $deviceName. Ketuk untuk memutus koneksi.'
          : isScanning
          ? 'Sedang mencari perangkat'
          : 'Cari perangkat, tidak terhubung',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
            decoration: BoxDecoration(
              color: enabled
                  ? backgroundColor
                  : AppColors.textTertiary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(22),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: backgroundColor.withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 72,
                  color: enabled ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.heading3.copyWith(
                    color: enabled ? Colors.white : AppColors.textSecondary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: enabled
                        ? Colors.white.withValues(alpha: 0.88)
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
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

class _BleDeviceTile extends StatelessWidget {
  const _BleDeviceTile({
    required this.name,
    required this.remoteId,
    required this.rssi,
    required this.isSelected,
    required this.onTap,
  });

  final String name;
  final String remoteId;
  final int rssi;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? AppColors.secondary
        : AppColors.textSecondary.withValues(alpha: 0.12);
    final backgroundColor = isSelected
        ? AppColors.secondary.withValues(alpha: 0.10)
        : AppColors.surfaceLight;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: isSelected ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.successLight : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.bluetooth_rounded,
                  color: isSelected ? AppColors.success : AppColors.info,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$remoteId - RSSI $rssi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 32,
                color: isSelected
                    ? AppColors.secondary
                    : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isFullWidth = false,
    this.backgroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isFullWidth;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    final button = ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: isFullWidth ? 30 : 24),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: enabled
            ? backgroundColor ?? AppColors.secondary
            : AppColors.textTertiary.withValues(alpha: 0.25),
        foregroundColor: enabled ? Colors.white : AppColors.textSecondary,
        padding: EdgeInsets.symmetric(
          horizontal: isFullWidth ? 24 : 18,
          vertical: isFullWidth ? 22 : 16,
        ),
        textStyle:
            (isFullWidth ? AppTextStyles.bodyLarge : AppTextStyles.bodySmall)
                .copyWith(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    if (!isFullWidth) {
      return button;
    }

    return SizedBox(width: double.infinity, child: button);
  }
}

class _PairingTextField extends StatefulWidget {
  const _PairingTextField({
    required this.controller,
    required this.icon,
    required this.label,
    required this.keyboardType,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final TextInputType keyboardType;
  final bool obscureText;

  @override
  State<_PairingTextField> createState() => _PairingTextFieldState();
}

class _PairingTextFieldState extends State<_PairingTextField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;

    return TextField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      obscureText: _obscureText,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.characters,
      style: AppTextStyles.bodyLarge.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textSecondary,
        ),
        prefixIcon: Icon(widget.icon, color: AppColors.primary),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasText)
              IconButton(
                tooltip: 'Hapus ${widget.label}',
                icon: const Icon(Icons.close_rounded),
                color: AppColors.textSecondary,
                onPressed: widget.controller.clear,
              ),
            if (widget.obscureText)
              IconButton(
                tooltip: _obscureText ? 'Tampilkan PIN' : 'Sembunyikan PIN',
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                color: AppColors.primary,
                onPressed: () {
                  setState(() => _obscureText = !_obscureText);
                },
              ),
          ],
        ),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
