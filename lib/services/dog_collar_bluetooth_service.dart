import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as dart;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DogCollarBluetoothService extends ChangeNotifier {
  // ============================================================================
  // BLE SERVICE CONSTANTS - MATCHING ESP32 SENDER
  // ============================================================================
  static const String serviceUuid = "12345678-1234-1234-1234-123456789abc";
  static const String commandCharUuid = "12345678-1234-1234-1234-123456789abd";
  static const String statusCharUuid = "12345678-1234-1234-1234-123456789abe";
  static const String deviceName = "DogCollar_TX";

  // ============================================================================
  // CONNECTION STATE VARIABLES
  // ============================================================================
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;
  StreamSubscription<List<int>>? _statusSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  bool _isScanning = false;
  bool _isConnected = false;
  bool _dogConnectionActive = false;
  String _connectionStatus = "Getrennt";

  // ============================================================================
  // HARDWARE DATA FROM ESP32 SENDER
  // ============================================================================
  int _senderBattery = 0;        // Sender Akkustand
  int _receiverBattery = 0;      // Empfänger/Hund Akkustand  
  int _rssiValue = -100;         // RSSI zum Empfänger
  int _signalQuality = 0;        // Signalqualität 0-100%
  double _distanceMeters = 0.0;  // Geschätzte Entfernung
  int _uptime = 0;               // Sender Uptime
  bool _devicePaired = false;    // ESP-NOW Pairing Status

  // ============================================================================
  // GETTERS
  // ============================================================================
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get dogConnectionActive => _dogConnectionActive;
  String get connectionStatus => _connectionStatus;
  int get senderBattery => _senderBattery;
  int get receiverBattery => _receiverBattery;
  int get rssiValue => _rssiValue;
  int get signalQuality => _signalQuality;
  double get distanceMeters => _distanceMeters;
  bool get devicePaired => _devicePaired;

  // ============================================================================
  // BLE INITIALIZATION
  // ============================================================================
  Future<void> initialize() async {
    debugPrint("🔧 Initialisiere DogCollarBluetoothService...");
    
    // Check if Bluetooth is supported and enabled
    if (await FlutterBluePlus.isSupported == false) {
      debugPrint("❌ Bluetooth nicht unterstützt auf diesem Gerät");
      return;
    }

    // Listen to Bluetooth adapter state
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      debugPrint("📡 Bluetooth Adapter State: $state");
      if (state == BluetoothAdapterState.on) {
        startScanning();
      } else {
        _updateConnectionStatus("Bluetooth ausgeschaltet");
      }
    });

    // Start scanning if Bluetooth is already on
    if (await FlutterBluePlus.isOn) {
      startScanning();
    }
  }

  // ============================================================================
  // DEVICE SCANNING
  // ============================================================================
  Future<void> startScanning() async {
    if (_isScanning) return;
    
    debugPrint("🔍 Starte BLE Scan nach '$deviceName'...");
    _isScanning = true;
    _updateConnectionStatus("Suche Sender...");
    notifyListeners();

    try {
      // Stop any previous scan
      await FlutterBluePlus.stopScan();
      
      // Start scanning with service filter
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          if (result.device.platformName == deviceName) {
            debugPrint("✅ DogCollar_TX gefunden! RSSI: ${result.rssi}");
            stopScanning();
            connectToDevice(result.device);
            return;
          }
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        withServices: [Guid(serviceUuid)],
      );

      // Handle scan timeout
      Timer(const Duration(seconds: 10), () {
        if (_isScanning) {
          stopScanning();
          _updateConnectionStatus("Sender nicht gefunden");
        }
      });

    } catch (e) {
      debugPrint("❌ Scan Fehler: $e");
      _isScanning = false;
      _updateConnectionStatus("Scan Fehler: $e");
      notifyListeners();
    }
  }

  void stopScanning() {
    if (!_isScanning) return;
    
    debugPrint("🛑 Stoppe BLE Scan");
    _isScanning = false;
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    notifyListeners();
  }

  // ============================================================================
  // DEVICE CONNECTION
  // ============================================================================
  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      debugPrint("🔗 Verbinde mit ${device.platformName}...");
      _updateConnectionStatus("Verbinde...");

      // Listen to connection state changes
      _connectionSubscription = device.connectionState.listen((state) {
        debugPrint("📱 Connection State: $state");
        
        if (state == BluetoothConnectionState.connected) {
          _isConnected = true;
          _connectedDevice = device;
          _updateConnectionStatus("Verbunden");
          _discoverServices();
        } else if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
        notifyListeners();
      });

      // Connect to device
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

    } catch (e) {
      debugPrint("❌ Verbindungsfehler: $e");
      _updateConnectionStatus("Verbindung fehlgeschlagen: $e");
      notifyListeners();
    }
  }

  // ============================================================================
  // SERVICE DISCOVERY & CHARACTERISTIC SETUP
  // ============================================================================
  Future<void> _discoverServices() async {
    if (_connectedDevice == null) return;

    try {
      debugPrint("🔍 Entdecke Services...");
      
      List<BluetoothService> services = await _connectedDevice!.discoverServices();
      
      for (BluetoothService service in services) {
        debugPrint("📋 Service gefunden: ${service.serviceUuid}");
        
        if (service.serviceUuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          debugPrint("✅ DogCollar Service gefunden!");
          
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            String charUuid = characteristic.characteristicUuid.toString().toLowerCase();
            
            if (charUuid == commandCharUuid.toLowerCase()) {
              _commandCharacteristic = characteristic;
              debugPrint("✅ Command Characteristic gefunden");
              
            } else if (charUuid == statusCharUuid.toLowerCase()) {
              _statusCharacteristic = characteristic;
              debugPrint("✅ Status Characteristic gefunden");
              
              // Subscribe to status notifications
              await _setupStatusNotifications();
            }
          }
          
          if (_commandCharacteristic != null && _statusCharacteristic != null) {
            _updateConnectionStatus("Einsatzbereit");
            debugPrint("🎉 Alle Characteristics gefunden - System bereit!");
            
            // Request initial status
            await _requestStatus();
          }
          break;
        }
      }
      
    } catch (e) {
      debugPrint("❌ Service Discovery Fehler: $e");
      _updateConnectionStatus("Service Discovery fehlgeschlagen");
    }
  }

  Future<void> _setupStatusNotifications() async {
    if (_statusCharacteristic == null) return;

    try {
      // Enable notifications
      await _statusCharacteristic!.setNotifyValue(true);
      
      // Listen to status updates
      _statusSubscription = _statusCharacteristic!.lastValueStream.listen(
        (value) {
          _handleStatusUpdate(value);
        },
        onError: (error) {
          debugPrint("❌ Status Notification Fehler: $error");
        },
      );
      
      debugPrint("✅ Status Notifications aktiviert");
      
    } catch (e) {
      debugPrint("❌ Status Notification Setup Fehler: $e");
    }
  }

  // ============================================================================
  // STATUS DATA PROCESSING - WITH RECEIVER DISCONNECTION HANDLING
  // ============================================================================
  void _handleStatusUpdate(List<int> value) {
    try {
      String jsonString = utf8.decode(value);
      debugPrint("📊 Status Update: $jsonString");
      
      Map<String, dynamic> statusData = json.decode(jsonString);
      
      // Parse ESP32 status data
      _devicePaired = statusData['paired'] ?? false;
      _dogConnectionActive = statusData['connected'] ?? false;
      _senderBattery = statusData['senderBattery'] ?? 0;
      _uptime = statusData['uptime'] ?? 0;
      
      // WICHTIG: Der RSSI aus dem JSON ist der ESP-NOW RSSI (Sender → Hund)!
      int receivedRssi = statusData['rssi'] ?? -100;
      int receivedReceiverBattery = statusData['receiverBattery'] ?? 0;
      
      // ========================================================================
      // 🚨 EMPFÄNGER-TRENNUNG BEHANDLUNG
      // ========================================================================
      
      // Prüfe auf Empfänger-Trennung basierend auf ESP32 Status
      bool receiverDisconnected = !_dogConnectionActive || 
                                  receivedRssi == 0 || 
                                  receivedRssi == -100 ||
                                  receivedReceiverBattery == 0;
      
      if (receiverDisconnected) {
        debugPrint("🔌 EMPFÄNGER GETRENNT ERKANNT!");
        debugPrint("  - dogConnectionActive: $_dogConnectionActive");
        debugPrint("  - receivedRssi: $receivedRssi");
        debugPrint("  - receivedReceiverBattery: $receivedReceiverBattery");
        
        // Reset alle empfängerbezogenen Werte
        _receiverBattery = 0;
        _rssiValue = 0;
        _distanceMeters = 0.0;
        _signalQuality = 0;
        
        debugPrint("✅ Empfänger-Werte zurückgesetzt");
        
      } else {
        // Empfänger verbunden - normale Aktualisierung
        _receiverBattery = receivedReceiverBattery;
        
        if (receivedRssi != -100 && receivedRssi != 0) {
          _rssiValue = receivedRssi;
          debugPrint("🐕 Hund-RSSI aktualisiert: $_rssiValue dBm (ESP-NOW)");
          
          // Signalqualität und Entfernung nur bei gültigen RSSI-Werten berechnen
          _signalQuality = _calculateSignalQuality(_rssiValue);
          _distanceMeters = _calculateDistance(_rssiValue);
          
          debugPrint("📏 Berechnete Hund-Entfernung: ${_distanceMeters.toStringAsFixed(1)}m");
          debugPrint("📶 Signal-Qualität: $_signalQuality% (basierend auf $_rssiValue dBm)");
        }
      }
      
      // ========================================================================
      // CONNECTION STATUS UPDATE
      // ========================================================================
      if (_dogConnectionActive && !receiverDisconnected) {
        _updateConnectionStatus("🐕 Hund verbunden");
      } else if (_devicePaired) {
        _updateConnectionStatus("⚠️ Hund nicht erreichbar");
      } else {
        _updateConnectionStatus("🔍 Suche Hund...");
      }
      
      // Debug-Info für Disconnect-Handling
      if (receiverDisconnected) {
        debugPrint("📋 DISCONNECT STATUS:");
        debugPrint("  🔋 Empfänger Akku: $_receiverBattery%");
        debugPrint("  📡 Hund RSSI: $_rssiValue dBm");
        debugPrint("  📏 Distanz: ${_distanceMeters}m");
        debugPrint("  📶 Signal: $_signalQuality%");
        debugPrint("  🔗 Verbunden: $_dogConnectionActive");
      }
      
      notifyListeners();
      
    } catch (e) {
      debugPrint("❌ Status Parsing Fehler: $e");
      
      // Bei Parse-Fehlern auch Disconnect annehmen
      _handleEmergencyDisconnect("JSON Parse Error");
    }
  }
  
  // ============================================================================
  // EMERGENCY DISCONNECT HANDLING
  // ============================================================================
  void _handleEmergencyDisconnect(String reason) {
    debugPrint("🚨 EMERGENCY DISCONNECT: $reason");
    
    _dogConnectionActive = false;
    _receiverBattery = 0;
    _rssiValue = 0;
    _distanceMeters = 0.0;
    _signalQuality = 0;
    
    _updateConnectionStatus("❌ Verbindungsfehler");
    notifyListeners();
  }

  // ============================================================================
  // DISTANCE CALCULATION FROM RSSI - WITH DISCONNECT HANDLING
  // ============================================================================
  double _calculateDistance(int rssi) {
    // Bei Trennung oder ungültigen RSSI-Werten → 0.0m
    if (rssi == 0 || rssi == -100 || !_dogConnectionActive) {
      debugPrint("📏 Distanz = 0.0m (Hund getrennt oder ungültiger RSSI: $rssi)");
      return 0.0;
    }
    
    // Simple RSSI to distance conversion (rough approximation)
    // Formula: Distance = 10^((Tx Power - RSSI) / (10 * N))
    // Tx Power = -20 dBm (ESP32 default), N = 2 (free space)
    
    double txPower = -20.0; // ESP32 transmission power
    double pathLoss = 2.0;  // Path loss exponent (2 = free space)
    
    if (rssi < -90) return 100.0; // Maximum distance
    
    double distance = _pow(10, (txPower - rssi) / (10 * pathLoss));
    return distance.clamp(0.0, 100.0); // Limit to reasonable range
  }

  // ============================================================================
  // SIGNAL QUALITY CALCULATION - WITH DISCONNECT HANDLING  
  // ============================================================================
  int _calculateSignalQuality(int rssi) {
    // Bei Trennung oder ungültigen RSSI-Werten → 0%
    if (rssi == 0 || rssi == -100 || !_dogConnectionActive) {
      debugPrint("📶 Signal Quality = 0% (Hund getrennt oder ungültiger RSSI: $rssi)");
      return 0;
    }
    
    // Convert RSSI to signal quality (0-100%)
    int quality = ((rssi + 100) * 100 / 70).round().clamp(0, 100);
    return quality;
  }

  // ============================================================================
  // VIBRATION COMMANDS - WITH CONNECTION CHECK
  // ============================================================================
  Future<bool> sendVibrateCommand({
    int pattern = 1,    // 1=Single, 2=Double  
    int intensity = 255, // 0-255
    int duration = 1000, // milliseconds
  }) async {
    
    // Prüfe BLE-Verbindung zum Sender
    if (_commandCharacteristic == null) {
      debugPrint("❌ Command Characteristic nicht verfügbar");
      return false;
    }
    
    // Prüfe Verbindung zum Hund
    if (!_dogConnectionActive) {
      debugPrint("❌ Vibration nicht möglich - Hund nicht verbunden!");
      debugPrint("  dogConnectionActive: $_dogConnectionActive");
      debugPrint("  receiverBattery: $_receiverBattery%");
      debugPrint("  rssi: $_rssiValue dBm");
      return false;
    }

    try {
      // Create command data matching ESP32 format:
      // Byte 0: Pattern (1=Single, 2=Double)
      // Byte 1: Intensity (0-255) 
      // Byte 2-3: Duration (milliseconds, big-endian)
      
      List<int> commandData = [
        pattern,
        intensity,
        (duration >> 8) & 0xFF, // High byte
        duration & 0xFF,        // Low byte
      ];
      
      debugPrint("📤 Sende Vibrations-Command: Pattern=$pattern, Intensity=$intensity, Duration=${duration}ms");
      debugPrint("🐕 Hund-Status: Verbunden ✅, Akku: $_receiverBattery%, RSSI: $_rssiValue dBm");
      
      await _commandCharacteristic!.write(
        commandData,
        withoutResponse: false,
      );
      
      debugPrint("✅ Vibrations-Command gesendet");
      return true;
      
    } catch (e) {
      debugPrint("❌ Vibrations-Command Fehler: $e");
      return false;
    }
  }

  // Convenience methods with connection validation
  Future<bool> sendSingleVibration() async {
    if (!_dogConnectionActive) {
      debugPrint("❌ Single Vibration abgebrochen - Hund nicht verbunden");
      return false;
    }
    return sendVibrateCommand(pattern: 1, intensity: 255, duration: 1000);
  }

  Future<bool> sendDoubleVibration() async {
    if (!_dogConnectionActive) {
      debugPrint("❌ Double Vibration abgebrochen - Hund nicht verbunden");
      return false;
    }
    return sendVibrateCommand(pattern: 2, intensity: 255, duration: 4000);
  }

  Future<bool> sendEmergencyCall() async {
    if (!_dogConnectionActive) {
      debugPrint("❌ Emergency Call abgebrochen - Hund nicht verbunden");
      return false;
    }
    return sendVibrateCommand(pattern: 2, intensity: 255, duration: 3000);
  }

  // ============================================================================
  // STATUS REQUEST
  // ============================================================================
  Future<void> _requestStatus() async {
    if (_statusCharacteristic == null) return;

    try {
      // Read current status
      List<int> value = await _statusCharacteristic!.read();
      _handleStatusUpdate(value);
      
    } catch (e) {
      debugPrint("❌ Status Request Fehler: $e");
    }
  }

  // ============================================================================
  // DISCONNECTION HANDLING
  // ============================================================================
  void _handleDisconnection() {
    debugPrint("🔌 BLE Verbindung getrennt");
    
    _isConnected = false;
    _dogConnectionActive = false;
    _connectedDevice = null;
    _commandCharacteristic = null;
    _statusCharacteristic = null;
    
    // Reset auch alle Empfänger-Werte bei BLE-Trennung
    _receiverBattery = 0;
    _rssiValue = 0;
    _distanceMeters = 0.0;
    _signalQuality = 0;
    
    _statusSubscription?.cancel();
    _connectionSubscription?.cancel();
    
    _updateConnectionStatus("Verbindung verloren");
    
    // Auto-reconnect after delay
    Timer(const Duration(seconds: 3), () {
      if (!_isConnected) {
        startScanning();
      }
    });
    
    notifyListeners();
  }

  Future<void> disconnect() async {
    try {
      stopScanning();
      
      _statusSubscription?.cancel();
      _connectionSubscription?.cancel();
      
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
      
      _isConnected = false;
      _dogConnectionActive = false;
      _connectedDevice = null;
      _commandCharacteristic = null;
      _statusCharacteristic = null;
      
      // Reset alle Werte bei manuellem Disconnect
      _receiverBattery = 0;
      _rssiValue = 0;
      _distanceMeters = 0.0;
      _signalQuality = 0;
      
      _updateConnectionStatus("Getrennt");
      notifyListeners();
      
    } catch (e) {
      debugPrint("❌ Disconnect Fehler: $e");
    }
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================
  void _updateConnectionStatus(String status) {
    _connectionStatus = status;
    debugPrint("📱 Status: $status");
  }

  // Math import helper for pow function
  double _pow(double base, double exponent) {
    return dart.pow(base, exponent).toDouble();
  }

  // ============================================================================
  // CLEANUP
  // ============================================================================
  @override
  void dispose() {
    disconnect();
    super.dispose();
  }

  // ============================================================================
  // DEBUG METHODS
  // ============================================================================
  void printDebugInfo() {
    debugPrint("\n=== DogCollarBluetoothService Debug Info ===");
    debugPrint("Connected: $_isConnected");
    debugPrint("Dog Connection: $_dogConnectionActive");
    debugPrint("Sender Battery: $_senderBattery%");
    debugPrint("Receiver Battery: $_receiverBattery%");
    debugPrint("RSSI: $_rssiValue dBm");
    debugPrint("Signal Quality: $_signalQuality%");
    debugPrint("Distance: ${_distanceMeters.toStringAsFixed(1)}m");
    debugPrint("Status: $_connectionStatus");
    debugPrint("=====================================\n");
  }
}