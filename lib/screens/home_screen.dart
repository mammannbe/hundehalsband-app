import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/dog_collar_bluetooth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _radarController;
  late Animation<double> _radarRotation;

  @override
  void initState() {
    super.initState();
    
    // Radar Animation Setup
    _radarController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _radarRotation = Tween<double>(begin: 0, end: 1).animate(_radarController);
    
    // Auto-connect when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bluetoothService = context.read<DogCollarBluetoothService>();
      bluetoothService.startScanning();
      
      // Start radar animation if dog connected
      if (bluetoothService.dogConnectionActive) {
        _radarController.repeat();
      }
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DogCollarBluetoothService>(
      builder: (context, bluetoothService, child) {
        // Control radar animation based on connection
        if (bluetoothService.dogConnectionActive) {
          if (!_radarController.isAnimating) {
            _radarController.repeat();
          }
        } else {
          _radarController.stop();
        }

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            title: const Text('🐕 Hundehalsband Control'),
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
            elevation: 2,
            actions: [
              // BLE Connection Status Icon
              IconButton(
                icon: bluetoothService.isConnected
                    ? const Icon(Icons.bluetooth_connected)
                    : bluetoothService.isScanning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.bluetooth_disabled),
                onPressed: bluetoothService.isConnected
                    ? () => bluetoothService.disconnect()
                    : bluetoothService.isScanning
                        ? null
                        : () => bluetoothService.startScanning(),
                tooltip: bluetoothService.isConnected
                    ? 'Verbindung trennen'
                    : bluetoothService.isScanning
                        ? 'Suche läuft...'
                        : 'Verbinden',
              ),
              
              // Debug Info Button
              IconButton(
                icon: const Icon(Icons.bug_report),
                onPressed: () {
                  bluetoothService.printDebugInfo();
                  _showDebugDialog(context, bluetoothService);
                },
                tooltip: 'Debug Info',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Connection Status Card
                _buildConnectionStatusCard(bluetoothService),
                
                const SizedBox(height: 20),
                
                // Distance Radar Display
                _buildDistanceRadarCard(bluetoothService),
                
                const SizedBox(height: 20),
                
                // Battery Status Row
                _buildBatteryStatusRow(bluetoothService),
                
                const SizedBox(height: 24),
                
                // Main Vibrate Button
                _buildMainVibrateButton(bluetoothService),
                
                const SizedBox(height: 16),
                
                // Pattern Buttons Row
                _buildPatternButtons(bluetoothService),
                
                const SizedBox(height: 20),
                
                // Signal Strength Card
                _buildSignalStrengthCard(bluetoothService),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================================
  // CONNECTION STATUS CARD
  // ============================================================================
  Widget _buildConnectionStatusCard(DogCollarBluetoothService bluetoothService) {
    Color statusColor = bluetoothService.isConnected 
      ? (bluetoothService.dogConnectionActive ? Colors.green : Colors.orange)
      : Colors.red;
    
    IconData statusIcon = bluetoothService.isConnected 
      ? (bluetoothService.dogConnectionActive ? Icons.pets : Icons.warning)
      : Icons.bluetooth_disabled;

    String statusText = bluetoothService.dogConnectionActive 
      ? '🐕 Hund ist erreichbar' 
      : bluetoothService.isConnected
        ? '⚠️ Hund außer Reichweite'
        : '❌ Keine Verbindung';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor.withOpacity(0.1),
              ),
              child: Icon(statusIcon, color: statusColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bluetoothService.connectionStatus,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 14,
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // DISTANCE RADAR DISPLAY CARD
  // ============================================================================
  Widget _buildDistanceRadarCard(DogCollarBluetoothService bluetoothService) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              '🎯 Hund Orten',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 20),
            
            // Animated Radar Display
            _buildAnimatedRadar(bluetoothService),
            
            const SizedBox(height: 16),
            
            // Distance and RSSI Info
            if (bluetoothService.dogConnectionActive) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'RSSI: ${bluetoothService.rssiValue} dBm',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      'Qualität: ${bluetoothService.signalQuality}%',
                      style: TextStyle(
                        fontSize: 14,
                        color: _getSignalColor(bluetoothService.signalQuality),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // ANIMATED RADAR WIDGET
  // ============================================================================
  Widget _buildAnimatedRadar(DogCollarBluetoothService bluetoothService) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Radar Circles (Background)
          ...List.generate(3, (index) => 
            Container(
              width: 200 - (index * 50),
              height: 200 - (index * 50),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: bluetoothService.dogConnectionActive 
                    ? Colors.green.withOpacity(0.3 - (index * 0.1))
                    : Colors.grey.withOpacity(0.3 - (index * 0.1)),
                  width: 2,
                ),
              ),
            ),
          ),
          
          // Rotating Radar Sweep
          if (bluetoothService.dogConnectionActive)
            AnimatedBuilder(
              animation: _radarRotation,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _radarRotation.value * 2 * 3.14159,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          Colors.transparent,
                          Colors.green.withOpacity(0.3),
                          Colors.green.withOpacity(0.6),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.3, 0.5, 1.0],
                      ),
                    ),
                  ),
                );
              },
            ),
          
          // Center Content
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: bluetoothService.dogConnectionActive ? Colors.green : Colors.grey,
                width: 3,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (bluetoothService.dogConnectionActive) ...[
                  Text(
                    '${bluetoothService.distanceMeters.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const Text(
                    'Meter',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else ...[
                  Icon(
                    Icons.signal_wifi_off,
                    size: 32,
                    color: Colors.grey[400],
                  ),
                  Text(
                    'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Dog Position Indicator (if connected)
          if (bluetoothService.dogConnectionActive)
            Positioned(
              top: 30,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green,
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.pets,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================================
  // BATTERY STATUS ROW
  // ============================================================================
  Widget _buildBatteryStatusRow(DogCollarBluetoothService bluetoothService) {
    return Row(
      children: [
        Expanded(
          child: _buildBatteryCard(
            'Sender',
            bluetoothService.senderBattery,
            Icons.radio,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildBatteryCard(
            'Hund',
            bluetoothService.receiverBattery,
            Icons.pets,
            Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildBatteryCard(String title, int batteryLevel, IconData icon, Color accentColor) {
    Color batteryColor = _getBatteryColor(batteryLevel);
    
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildBatteryIndicator(batteryLevel, batteryColor),
            const SizedBox(height: 8),
            TweenAnimationBuilder<int>(
              duration: const Duration(milliseconds: 1000),
              tween: IntTween(begin: 0, end: batteryLevel),
              builder: (context, animatedLevel, child) {
                return Text(
                  '$animatedLevel%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: batteryColor,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryIndicator(int batteryLevel, Color batteryColor) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 60,
          height: 30,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[400]!, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Positioned(
          right: -4,
          child: Container(
            width: 4,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(2),
                bottomRight: Radius.circular(2),
              ),
            ),
          ),
        ),
        Positioned(
          left: 2,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 1500),
            tween: Tween(begin: 0.0, end: (56 * batteryLevel / 100).clamp(0.0, 56.0)),
            curve: Curves.easeOutCubic,
            builder: (context, animatedWidth, child) {
              return Container(
                width: animatedWidth,
                height: 26,
                decoration: BoxDecoration(
                  color: batteryColor,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: batteryColor.withOpacity(0.3),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (batteryLevel <= 20)
          const Icon(
            Icons.warning,
            color: Colors.white,
            size: 16,
          ),
      ],
    );
  }

  // ============================================================================
  // MAIN VIBRATE BUTTON
  // ============================================================================
  Widget _buildMainVibrateButton(DogCollarBluetoothService bluetoothService) {
    bool isEnabled = bluetoothService.isConnected && bluetoothService.dogConnectionActive;
    
    return Center(
      child: GestureDetector(
        onTap: isEnabled ? () => _sendVibration(bluetoothService, 1) : null,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 1000),
          tween: Tween(begin: 0.8, end: 1.0),
          curve: Curves.elasticOut,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isEnabled
                      ? const RadialGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF1E40AF)],
                          stops: [0.3, 1.0],
                        )
                      : RadialGradient(
                          colors: [Colors.grey[400]!, Colors.grey[600]!],
                          stops: const [0.3, 1.0],
                        ),
                  boxShadow: isEnabled
                      ? [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.4),
                            blurRadius: 25,
                            spreadRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.vibration,
                        size: 52,
                        color: isEnabled ? Colors.white : Colors.grey[600],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'VIBRATION',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isEnabled ? Colors.white : Colors.grey[600],
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isEnabled ? 'BEREIT' : 'OFFLINE',
                        style: TextStyle(
                          fontSize: 12,
                          color: isEnabled 
                              ? Colors.white.withOpacity(0.8) 
                              : Colors.grey[500],
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================================
  // PATTERN BUTTONS
  // ============================================================================
  Widget _buildPatternButtons(DogCollarBluetoothService bluetoothService) {
    bool isEnabled = bluetoothService.isConnected && bluetoothService.dogConnectionActive;
    
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isEnabled ? () => _sendVibration(bluetoothService, 2) : null,
            icon: const Icon(Icons.double_arrow),
            label: const Text('Doppelt'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isEnabled ? () => _sendEmergencyVibration(bluetoothService) : null,
            icon: const Icon(Icons.warning),
            label: const Text('NOTFALL'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // SIGNAL STRENGTH CARD
  // ============================================================================
  Widget _buildSignalStrengthCard(DogCollarBluetoothService bluetoothService) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Empfangsqualität',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSignalBars(bluetoothService),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bluetoothService.dogConnectionActive 
                          ? '${bluetoothService.rssiValue} dBm' 
                          : '--- dBm',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _getSignalColor(bluetoothService.signalQuality),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getSignalQualityText(bluetoothService.signalQuality, bluetoothService.dogConnectionActive),
                      style: TextStyle(
                        fontSize: 12,
                        color: _getSignalColor(bluetoothService.signalQuality),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalBars(DogCollarBluetoothService bluetoothService) {
    int signalStrength = _getSignalStrength(bluetoothService.signalQuality);
    
    return Row(
      children: List.generate(5, (index) {
        bool isActive = bluetoothService.dogConnectionActive && index < signalStrength;
        return Container(
          margin: const EdgeInsets.only(right: 3),
          width: 8,
          height: 20 + (index * 5).toDouble(),
          decoration: BoxDecoration(
            color: isActive 
                ? _getSignalColor(bluetoothService.signalQuality)
                : Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  // ============================================================================
  // ACTION METHODS
  // ============================================================================
  
  Future<void> _sendVibration(DogCollarBluetoothService bluetoothService, int pattern) async {
    bool success = await bluetoothService.sendVibrateCommand(pattern: pattern);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Vibration senden fehlgeschlagen'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendEmergencyVibration(DogCollarBluetoothService bluetoothService) async {
    bool success = await bluetoothService.sendEmergencyCall();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Notfall-Vibration senden fehlgeschlagen'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🚨 Notfall-Rückruf gesendet!'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _showDebugDialog(BuildContext context, DogCollarBluetoothService bluetoothService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🐛 Debug Info'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _debugRow('BLE Verbunden', bluetoothService.isConnected ? '✅' : '❌'),
              _debugRow('Hund Verbunden', bluetoothService.dogConnectionActive ? '✅' : '❌'),
              _debugRow('Status', bluetoothService.connectionStatus),
              const Divider(),
              _debugRow('RSSI', '${bluetoothService.rssiValue} dBm'),
              _debugRow('Distanz', '${bluetoothService.distanceMeters.toStringAsFixed(1)} m'),
              _debugRow('Signal Qualität', '${bluetoothService.signalQuality}%'),
              const Divider(),
              _debugRow('Sender Akku', '${bluetoothService.senderBattery}%'),
              _debugRow('Empfänger Akku', '${bluetoothService.receiverBattery}%'),
              _debugRow('Gepairt', bluetoothService.devicePaired ? '✅' : '❌'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
          TextButton(
            onPressed: () {
              bluetoothService.startScanning();
              Navigator.of(context).pop();
            },
            child: const Text('Neu verbinden'),
          ),
        ],
      ),
    );
  }

  Widget _debugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================
  
  Color _getBatteryColor(int batteryLevel) {
    if (batteryLevel <= 20) return Colors.red;
    if (batteryLevel <= 40) return Colors.orange;
    if (batteryLevel <= 60) return Colors.yellow[700]!;
    return Colors.green;
  }

  Color _getSignalColor(int signalQuality) {
    if (signalQuality >= 70) return Colors.green;
    if (signalQuality >= 50) return Colors.orange;
    if (signalQuality <= 0) return Colors.grey;
    return Colors.red;
  }

  int _getSignalStrength(int signalQuality) {
    if (signalQuality >= 80) return 5; // Excellent
    if (signalQuality >= 60) return 4; // Good
    if (signalQuality >= 40) return 3; // Fair
    if (signalQuality >= 20) return 2; // Poor
    if (signalQuality > 0) return 1;   // Very Poor
    return 0; // No signal
  }

  String _getSignalQualityText(int signalQuality, bool isConnected) {
    if (!isConnected) return 'Getrennt';
    
    if (signalQuality >= 80) return 'Ausgezeichnet';
    if (signalQuality >= 60) return 'Gut';
    if (signalQuality >= 40) return 'Mittelmäßig';
    if (signalQuality >= 20) return 'Schwach';
    if (signalQuality > 0) return 'Sehr schwach';
    return 'Kein Signal';
  }
}