import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/dog_collar_bluetooth_service.dart';
import 'screens/home_screen.dart';

// ============================================================================
// MAIN FUNCTION
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Request Bluetooth permissions
  await _requestPermissions();
  
  runApp(const DogCollarApp());
}

// ============================================================================
// PERMISSION HANDLING
// ============================================================================
Future<void> _requestPermissions() async {
  debugPrint("🔐 Prüfe Bluetooth Berechtigungen...");
  
  // Required permissions for BLE
  Map<Permission, PermissionStatus> permissions = await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.location, // Required for BLE scanning on Android
  ].request();
  
  // Check if all permissions granted
  bool allGranted = permissions.values.every((status) => status.isGranted);
  
  if (allGranted) {
    debugPrint("✅ Alle Bluetooth Berechtigungen erteilt");
  } else {
    debugPrint("⚠️ Einige Bluetooth Berechtigungen fehlen:");
    permissions.forEach((permission, status) {
      if (!status.isGranted) {
        debugPrint("  - $permission: $status");
      }
    });
  }
}

// ============================================================================
// MAIN APP
// ============================================================================
class DogCollarApp extends StatefulWidget {
  const DogCollarApp({super.key});

  @override
  State<DogCollarApp> createState() => _DogCollarAppState();
}

class _DogCollarAppState extends State<DogCollarApp> {
  late DogCollarBluetoothService bluetoothService;

  @override
  void initState() {
    super.initState();
    bluetoothService = DogCollarBluetoothService();
    
    // Initialize Bluetooth service after app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeBluetoothService();
    });
  }

  Future<void> _initializeBluetoothService() async {
    try {
      debugPrint("🚀 Initialisiere Bluetooth Service...");
      await bluetoothService.initialize();
      debugPrint("✅ Bluetooth Service initialisiert");
    } catch (e) {
      debugPrint("❌ Bluetooth Service Initialisierung fehlgeschlagen: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: bluetoothService,
      child: MaterialApp(
        title: '🐕 Hundehalsband Control',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 2,
          ),
          cardTheme: CardThemeData(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
            ),
          ),
        ),
        home: const HomeScreen(),
        
        // Debug Banner für Development
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              // Debug overlay in development mode
              if (kDebugMode)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  right: 10,
                  child: Consumer<DogCollarBluetoothService>(
                    builder: (context, bluetoothService, child) {
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "DEBUG",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "BLE: ${bluetoothService.isConnected ? '✅' : '❌'}",
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                            Text(
                              "Dog: ${bluetoothService.dogConnectionActive ? '🐕' : '❌'}",
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                            if (bluetoothService.isConnected)
                              Text(
                                "RSSI: ${bluetoothService.rssiValue}",
                                style: const TextStyle(color: Colors.white, fontSize: 10),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// DEBUG HELPERS
// ============================================================================
const bool kDebugMode = true; // Set to false for production

void debugPrint(String message) {
  if (kDebugMode) {
    print("[${DateTime.now().toString().split(' ')[1].substring(0, 8)}] $message");
  }
}