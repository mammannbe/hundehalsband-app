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
  // RSSI DATA - SEPARATED FOR CLARITY
  // ============================================================================
  int _senderBattery = 0;        // Sender Akkustand
  int _receiverBattery = 0;      // Empfänger/Hund Akkustand  
  
  // WICHTIG: Zwei verschiedene RSSI-Werte!
  int _bleRssiValue = -100;      // BLE RSSI: Sender → Smartphone (-28 dBm)
  int _dogRssiValue = -100;      // ESP-NOW RSSI: Sender → Hund (-44 dBm) ← FÜR ENTFERNUNG!
  
  int _signalQuality = 0;        // Signalqualität 0-100% (basierend auf Hund-RSSI)
  double _distanceMeters = 0.0;  // Geschätzte Entfernung (basierend auf Hund-RSSI)
  int _uptime = 0;               // Sender Uptime
  bool _devicePaired = false;    // ESP-NOW Pairing Status

  // ============================================================================
  // GETTERS - UPDATED FOR CLARITY
  // ============================================================================
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get dogConnectionActive => _dogConnectionActive;
  String get connectionStatus => _connectionStatus;
  int get senderBattery => _senderBattery;
  int get receiverBattery => _receiverBattery;
  
  // RSSI Getters mit klarer Benennung
  int get bleRssiValue => _bleRssiValue;      // Für BLE-Verbindungsqualität
  int get rssiValue => _dogRssiValue;         // Für Hund-Entfernung (Hauptwert)
  int get dogRssiValue => _dogRssiValue;      // Explizit für Hund-RSSI
  
  int get signalQuality => _signalQuality;
  double get distanceMeters => _distanceMeters;
  bool get devicePaired => _devicePaired;

  // ============================================================================
  // BLE INITIALIZATION
  // ============================================================================
  Future<void> initialize() async {
    debugPrint("🔧 Initialisiere DogCollarBluetoothService...");
    
    if (await FlutterBluePlus.isSupported == false) {
      debugPrint("❌ Bluetooth nicht unterstützt auf diesem Gerät");
      return;
    }

    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      debugPrint("📡 Bluetooth Adapter State: $state");
      if (state == BluetoothAdapterState.on) {
        startScanning();
      } else {
        _updateConnectionStatus("Bluetooth ausgeschaltet");
      }
    });

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
      await FlutterBluePlus.stopScan();
      
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          // BLE RSSI vom Scan-Result erfassen
          _bleRssiValue = result.rssi;
          debugPrint("📡 BLE Scan RSSI: $_bleRssiValue dBm (Sender → Phone)");
          
          if (result.device.platformName == deviceName) {
            debugPrint("✅ DogCollar_TX gefunden! BLE RSSI: ${result.rssi}");
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
              
              await _setupStatusNotifications();
            }
          }
          
          if (_commandCharacteristic != null && _statusCharacteristic != null) {
            _updateConnectionStatus("Einsatzbereit");
            debugPrint("🎉 Alle Characteristics gefunden - System bereit!");
            
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
      await _statusCharacteristic!.setNotifyValue(true);
      
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
  // STATUS DATA PROCESSING - UPDATED FOR DUAL RSSI
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
      _receiverBattery = statusData['receiverBattery'] ?? 0;
      _uptime = statusData['uptime'] ?? 0;
      
      // WICHTIG: Der RSSI aus dem JSON ist der ESP-NOW RSSI (Sender → Hund)!
      int receivedRssi = statusData['rssi'] ?? -100;
      if (receivedRssi != -100) {
        _dogRssiValue = receivedRssi;
        debugPrint("🐕 Hund-RSSI aktualisiert: $_dogRssiValue dBm (ESP-NOW)");
      }
      
      // Signalqualität basierend auf Hund-RSSI berechnen
      _signalQuality = _calculateSignalQuality(_dogRssiValue);
      
      // Entfernung basierend auf Hund-RSSI berechnen
      _distanceMeters = _calculateDistance(_dogRssiValue);
      
      debugPrint("📏 Berechnete Hund-Entfernung: ${_distanceMeters.toStringAsFixed(1)}m");
      debugPrint("📶 Signal-Qualität: $_signalQuality% (basierend auf $_dogRssiValue dBm)");
      
      // Update connection status based on dog connection
      if (_dogConnectionActive) {
        _updateConnectionStatus("🐕 Hund verbunden");
      } else if (_devicePaired) {
        _updateConnectionStatus("⚠️ Hund nicht erreichbar");
      } else {
        _updateConnectionStatus("🔍 Suche Hund...");
      }
      
      notifyListeners();
      
    } catch (e) {
      debugPrint("❌ Status Parsing Fehler: $e");
    }
  }

  // ============================================================================
  // DISTANCE & SIGNAL CALCULATION - BASED ON DOG RSSI
  // ============================================================================
  // ============================================================================
  // KALIBRIERTE DISTANCE CALCULATION - BASIEREND AUF MESSWERTEN
  // ============================================================================
  double _calculateDistance(int rssi) {
    if (rssi == 0 || rssi == -100) return 0.0;
    
    debugPrint("🔧 Berechne Distanz für RSSI: $rssi dBm");
    
    // Kalibrierungstabelle basierend auf realen Messwerten:
    // RSSI Range    | Distanz | Bemerkung
    // 0 bis -15     | 0.5m    | Sehr nah
    // -15 bis -20   | 1m      | Nah  
    // -37           | 2m      | Mittel-nah
    // -46           | 6m      | Mittel
    // -57           | 8m      | Mittel-weit
    // -65           | 12m     | Weit
    // < -65         | >12m    | Extrapolation bis 200m
    
    double distance;
    
    if (rssi >= -15) {
      // Sehr nah: 0 bis -15 dBm = 0.5m
      distance = 0.5;
      
    } else if (rssi >= -20) {
      // Nah: -15 bis -20 dBm = 0.5m bis 1m (linear interpoliert)
      distance = _linearInterpolation(rssi, -15, -20, 0.5, 1.0);
      
    } else if (rssi >= -37) {
      // -20 bis -37 dBm = 1m bis 2m (linear interpoliert)
      distance = _linearInterpolation(rssi, -20, -37, 1.0, 2.0);
      
    } else if (rssi >= -46) {
      // -37 bis -46 dBm = 2m bis 6m (linear interpoliert)
      distance = _linearInterpolation(rssi, -37, -46, 2.0, 6.0);
      
    } else if (rssi >= -57) {
      // -46 bis -57 dBm = 6m bis 8m (linear interpoliert)
      distance = _linearInterpolation(rssi, -46, -57, 6.0, 8.0);
      
    } else if (rssi >= -65) {
      // -57 bis -65 dBm = 8m bis 12m (linear interpoliert)
      distance = _linearInterpolation(rssi, -57, -65, 8.0, 12.0);
      
    } else {
      // < -65 dBm: Extrapolation für größere Entfernungen
      // Logarithmische Extrapolation für 12m bis 200m
      distance = _extrapolateDistance(rssi);
    }
    
    // Begrenzung der Werte
    distance = distance.clamp(0.5, 200.0);
    
    debugPrint("📏 RSSI $rssi dBm → ${distance.toStringAsFixed(1)}m");
    return distance;
  }

  // ============================================================================
  // HILFSFUNKTIONEN FÜR KALIBRIERTE BERECHNUNG
  // ============================================================================
  
  /// Lineare Interpolation zwischen zwei Punkten
  double _linearInterpolation(int rssi, int rssi1, int rssi2, double dist1, double dist2) {
    // Verhältnis berechnen (0.0 bis 1.0)
    double ratio = (rssi - rssi1) / (rssi2 - rssi1);
    ratio = ratio.clamp(0.0, 1.0);
    
    // Linear interpolieren
    double distance = dist1 + (ratio * (dist2 - dist1));
    
    debugPrint("🔢 Interpolation: RSSI $rssi zwischen ($rssi1→${dist1}m) und ($rssi2→${dist2}m) = ${distance.toStringAsFixed(1)}m");
    return distance;
  }
  
  /// Extrapolation für RSSI-Werte unter -65 dBm (>12m)
  double _extrapolateDistance(int rssi) {
    // Basis: -65 dBm = 12m
    // Logarithmische Extrapolation für realistische große Entfernungen
    
    if (rssi <= -90) {
      // Sehr schwaches Signal: 100m bis 200m
      return _linearInterpolation(rssi, -90, -100, 100.0, 200.0);
    }
    
    // -65 bis -90 dBm: 12m bis 100m (logarithmisch)
    // Formel: distance = 12 * exp(k * (rssi - (-65)))
    // k so wählen, dass -90 dBm ≈ 100m ergibt
    
    double k = 0.08; // Kalibrierungsfaktor
    double baseDistance = 12.0; // Basis bei -65 dBm
    double baseRssi = -65.0;
    
    double distance = baseDistance * _exp(k * (baseRssi - rssi));
    
    debugPrint("🔭 Extrapolation: RSSI $rssi dBm → ${distance.toStringAsFixed(1)}m (logarithmisch)");
    return distance.clamp(12.0, 200.0);
  }
  
  /// Exponentialfunktion (da dart:math als dart importiert ist)
  double _exp(double x) {
    return dart.exp(x);
  }

  // ============================================================================
  // VERBESSERTE SIGNAL QUALITY BERECHNUNG
  // ============================================================================
  int _calculateSignalQuality(int rssi) {
    if (rssi == 0 || rssi == -100) return 0;
    
    // Signalqualität basierend auf kalibrierten Bereichen
    int quality;
    
    if (rssi >= -15) {
      quality = 100; // Exzellent
    } else if (rssi >= -37) {
      quality = 85;  // Sehr gut
    } else if (rssi >= -46) {
      quality = 70;  // Gut  
    } else if (rssi >= -57) {
      quality = 50;  // Mittelmäßig
    } else if (rssi >= -65) {
      quality = 30;  // Schwach
    } else if (rssi >= -80) {
      quality = 15;  // Sehr schwach
    } else {
      quality = 5;   // Extrem schwach
    }
    
    debugPrint("📶 Signal Quality: $rssi dBm → $quality%");
    return quality.clamp(0, 100);
  }

  // ============================================================================
  // EXTENDED DEBUG INFO
  // ============================================================================
  void printCalibrationDebugInfo() {
    debugPrint("\n=== RSSI Kalibrierungs-Debug ===");
    debugPrint("🐕 Aktueller Hund-RSSI: $_dogRssiValue dBm");
    debugPrint("📏 Berechnete Entfernung: ${_distanceMeters.toStringAsFixed(1)}m");
    debugPrint("📶 Signal-Qualität: $_signalQuality%");
    
    // Test verschiedener RSSI-Werte
    debugPrint("\n--- Kalibrierungs-Test ---");
    List<int> testRssi = [-10, -15, -20, -37, -46, -57, -65, -75, -85, -95];
    for (int rssi in testRssi) {
      double dist = _calculateDistance(rssi);
      int qual = _calculateSignalQuality(rssi);
      debugPrint("RSSI $rssi dBm → ${dist.toStringAsFixed(1)}m (Quality: $qual%)");
    }
    debugPrint("============================\n");
  }

  // ============================================================================
  // VIBRATION COMMANDS
  // ============================================================================
  Future<bool> sendVibrateCommand({
    int pattern = 1,    // 1=Single, 2=Double  
    int intensity = 255, // 0-255
    int duration = 1000, // milliseconds
  }) async {
    
    if (_commandCharacteristic == null) {
      debugPrint("❌ Command Characteristic nicht verfügbar");
      return false;
    }

    try {
      List<int> commandData = [
        pattern,
        intensity,
        (duration >> 8) & 0xFF, // High byte
        duration & 0xFF,        // Low byte
      ];
      
      debugPrint("📤 Sende Vibrations-Command: Pattern=$pattern, Intensity=$intensity, Duration=${duration}ms");
      
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

  // Convenience methods for different vibration patterns
  Future<bool> sendSingleVibration() async {
    return sendVibrateCommand(pattern: 1, intensity: 255, duration: 1000);
  }

  Future<bool> sendDoubleVibration() async {
    return sendVibrateCommand(pattern: 2, intensity: 255, duration: 4000);
  }

  Future<bool> sendEmergencyCall() async {
    return sendVibrateCommand(pattern: 2, intensity: 255, duration: 3000);
  }

  // ============================================================================
  // STATUS REQUEST
  // ============================================================================
  Future<void> _requestStatus() async {
    if (_statusCharacteristic == null) return;

    try {
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
    debugPrint("🔌 Verbindung getrennt");
    
    _isConnected = false;
    _dogConnectionActive = false;
    _connectedDevice = null;
    _commandCharacteristic = null;
    _statusCharacteristic = null;
    
    _statusSubscription?.cancel();
    _connectionSubscription?.cancel();
    
    _updateConnectionStatus("Verbindung verloren");
    
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
  // DEBUG METHODS - ENHANCED FOR DUAL RSSI
  // ============================================================================
  void printDebugInfo() {
    debugPrint("\n=== DogCollarBluetoothService Debug Info ===");
    debugPrint("Connected: $_isConnected");
    debugPrint("Dog Connection: $_dogConnectionActive");
    debugPrint("Sender Battery: $_senderBattery%");
    debugPrint("Receiver Battery: $_receiverBattery%");
    debugPrint("📡 BLE RSSI (Phone): $_bleRssiValue dBm");
    debugPrint("🐕 Dog RSSI (ESP-NOW): $_dogRssiValue dBm");
    debugPrint("Signal Quality: $_signalQuality%");
    debugPrint("Distance: ${_distanceMeters.toStringAsFixed(1)}m");
    debugPrint("Status: $_connectionStatus");
    debugPrint("=====================================\n");
  }
}