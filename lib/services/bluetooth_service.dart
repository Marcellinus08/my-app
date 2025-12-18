import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';

/// Bluetooth Service untuk koneksi ke tongkat pintar
class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _targetCharacteristic;
  StreamSubscription? _deviceStateSubscription;
  
  final StreamController<bool> _connectionStateController = 
      StreamController<bool>.broadcast();
  final StreamController<String> _dataController = 
      StreamController<String>.broadcast();

  Stream<bool> get connectionStateStream => _connectionStateController.stream;
  Stream<String> get dataStream => _dataController.stream;
  bool get isConnected => _connectedDevice != null;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // Scan for Bluetooth devices
  Future<List<ScanResult>> scanDevices({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      // Check if Bluetooth is supported
      if (await FlutterBluePlus.isSupported == false) {
        print("Bluetooth not supported by this device");
        return [];
      }

      // Start scanning
      await FlutterBluePlus.startScan(timeout: timeout);
      
      // Wait for scan results
      await Future.delayed(timeout);
      
      // Stop scanning
      await FlutterBluePlus.stopScan();
      
      // Return empty list for web compatibility
      return [];
    } catch (e) {
      print('Error scanning devices: $e');
      return [];
    }
  }

  // Connect to a specific device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      // Disconnect if already connected
      if (_connectedDevice != null) {
        await disconnect();
      }

      // Connect to device
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;

      // Listen to connection state
      _deviceStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _connectionStateController.add(false);
          _connectedDevice = null;
        } else if (state == BluetoothConnectionState.connected) {
          _connectionStateController.add(true);
        }
      });

      // Discover services
      // Simplified for web compatibility
      try {
        // This will work on mobile platforms
        await device.discoverServices();
      } catch (e) {
        print('Service discovery not supported on this platform: $e');
      }

      _connectionStateController.add(true);
      return true;
    } catch (e) {
      print('Error connecting to device: $e');
      _connectionStateController.add(false);
      return false;
    }
  }

  // Send data to device
  Future<bool> sendData(String data) async {
    if (_targetCharacteristic == null || _connectedDevice == null) {
      print('Device not connected or characteristic not found');
      return false;
    }

    try {
      await _targetCharacteristic!.write(data.codeUnits);
      return true;
    } catch (e) {
      print('Error sending data: $e');
      return false;
    }
  }

  // Disconnect from device
  Future<void> disconnect() async {
    try {
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _deviceStateSubscription?.cancel();
        _connectedDevice = null;
        _targetCharacteristic = null;
        _connectionStateController.add(false);
      }
    } catch (e) {
      print('Error disconnecting: $e');
    }
  }

  void dispose() {
    _deviceStateSubscription?.cancel();
    _connectionStateController.close();
    _dataController.close();
    disconnect();
  }
}
