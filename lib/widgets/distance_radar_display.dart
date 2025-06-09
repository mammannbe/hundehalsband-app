import 'package:flutter/material.dart';

class DistanceRadarDisplay extends StatefulWidget {
  final double distance; // in meters
  final bool isConnected;

  const DistanceRadarDisplay({
    super.key,
    required this.distance,
    required this.isConnected,
  });

  @override
  State<DistanceRadarDisplay> createState() => _DistanceRadarDisplayState();
}

class _DistanceRadarDisplayState extends State<DistanceRadarDisplay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late AnimationController _colorController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _colorController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));

    if (widget.isConnected) {
      _startAnimations();
    }
    
    _scaleController.forward();
  }

  void _startAnimations() {
    _pulseController.repeat(reverse: true);
  }

  void _stopAnimations() {
    _pulseController.stop();
  }

  @override
  void didUpdateWidget(DistanceRadarDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isConnected != oldWidget.isConnected) {
      if (widget.isConnected) {
        _startAnimations();
      } else {
        _stopAnimations();
      }
    }
    
    // Trigger color animation when distance changes significantly
    if ((widget.distance - oldWidget.distance).abs() > 2.0) {
      _colorController.forward().then((_) => _colorController.reverse());
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  // ============================================================================
  // RADAR CALCULATIONS - BASED ON CALIBRATED RSSI
  // ============================================================================
  
  /// Berechne Ring-Größe: Je näher = größer (invertiert)
  double _getRadarSize(double distance) {
    if (!widget.isConnected) return 80.0;
    
    // 0.5m = 200px (äußerster Kreis), 200m = 60px (innerster Kreis)
    const double minSize = 60.0;
    const double maxSize = 200.0;
    
    // Logarithmische Skalierung für bessere Visualisierung
    double normalizedDistance = (distance.clamp(0.5, 200.0) / 200.0);
    double logDistance = (1.0 - normalizedDistance); // Invertiert
    
    return minSize + (logDistance * (maxSize - minSize));
  }

  /// Berechne Farbe basierend auf Distanz
  Color _getDistanceColor(double distance) {
    if (!widget.isConnected) return Colors.grey;
    
    if (distance <= 2.0) return const Color(0xFF10B981); // Grün - Sehr nah
    if (distance <= 8.0) return const Color(0xFF84CC16); // Hellgrün - Nah
    if (distance <= 20.0) return const Color(0xFFEAB308); // Gelb - Mittel
    if (distance <= 50.0) return const Color(0xFFF97316); // Orange - Weit
    return const Color(0xFFEF4444); // Rot - Sehr weit
  }

  /// Berechne Puls-Intensität: Je näher = intensiver
  double _getPulseIntensity(double distance) {
    if (!widget.isConnected) return 0.3;
    
    // Je näher, desto intensiver der Puls
    double intensity = 1.0 - (distance.clamp(0.5, 100.0) / 100.0);
    return (intensity * 0.7 + 0.3).clamp(0.3, 1.0); // Min 0.3, Max 1.0
  }

  /// Formatiere Distanz für Anzeige
  String _formatDistance(double distance) {
    if (distance < 1.0) {
      return distance.toStringAsFixed(1);
    } else if (distance < 10.0) {
      return distance.toStringAsFixed(1);
    } else if (distance < 100.0) {
      return distance.round().toString();
    } else {
      return '${distance.round()}';
    }
  }

  /// Status-Text basierend auf Entfernung
  String _getStatusText(double distance) {
    if (!widget.isConnected) return '⚫ Nicht verbunden';
    
    if (distance <= 2.0) return '🟢 Sehr nah!';
    if (distance <= 8.0) return '🔵 In der Nähe';
    if (distance <= 20.0) return '🟡 Mittlere Entfernung';
    if (distance <= 50.0) return '🟠 Weit entfernt';
    return '🔴 Sehr weit entfernt';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Column(
            children: [
              // Radar Container
              SizedBox(
                width: 320,
                height: 320,
                child: widget.isConnected
                    ? _buildActiveRadar()
                    : _buildInactiveRadar(),
              ),
              
              const SizedBox(height: 20),
              
              // Status Text mit Animation
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Text(
                  key: ValueKey(widget.isConnected ? widget.distance.round() : -1),
                  _getStatusText(widget.distance),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _getDistanceColor(widget.distance),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveRadar() {
    final double radarSize = _getRadarSize(widget.distance);
    final Color radarColor = _getDistanceColor(widget.distance);
    final double pulseIntensity = _getPulseIntensity(widget.distance);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Hintergrund-Raster (statische Kreise)
        ...List.generate(4, (index) {
          double radius = 60.0 + (index * 40.0);
          return Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey.withOpacity(0.2),
                width: 1,
              ),
            ),
          );
        }),

        // Haupt-Radar-Ring mit smooth Animation
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 1000),
                tween: Tween(begin: 60.0, end: radarSize),
                curve: Curves.easeOutCubic,
                builder: (context, animatedSize, child) {
                  return Container(
                    width: animatedSize,
                    height: animatedSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: radarColor.withOpacity(0.1),
                      border: Border.all(
                        color: radarColor,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: radarColor.withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),

        // Sekundärer Puls-Ring für extra Smoothness
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value * 0.9,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 1000),
                tween: Tween(begin: 50.0, end: radarSize * 0.85),
                curve: Curves.easeOutCubic,
                builder: (context, animatedSize, child) {
                  return Container(
                    width: animatedSize,
                    height: animatedSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: radarColor.withOpacity(0.05),
                      border: Border.all(
                        color: radarColor.withOpacity(0.6),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),

        // Ping-Effekt Ring
        TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: (2000 / pulseIntensity).round()),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, progress, child) {
            return AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                double pingSize = radarSize * 0.7 * (1.0 + progress * 0.3);
                return Container(
                  width: pingSize,
                  height: pingSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: radarColor.withOpacity(0.15 * (1.0 - progress)),
                  ),
                );
              },
            );
          },
          onEnd: () {
            // Restart ping animation
            setState(() {});
          },
        ),

        // Zentrum mit Distanz-Anzeige (komplett gefüllt)
        TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 1000),
          tween: ColorTween(
            begin: Colors.grey,
            end: radarColor,
          ),
          builder: (context, animatedColor, child) {
            return Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: animatedColor,
                boxShadow: [
                  BoxShadow(
                    color: (animatedColor ?? Colors.grey).withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                  const BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Distanz-Zahl
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 800),
                    tween: Tween(begin: 0.0, end: widget.distance),
                    curve: Curves.easeOutCubic,
                    builder: (context, animatedDistance, child) {
                      return Text(
                        _formatDistance(animatedDistance),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      );
                    },
                  ),
                  // "Meter" Text
                  const Text(
                    'Meter',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildInactiveRadar() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Statische Hintergrund-Kreise
        ...List.generate(4, (index) {
          double radius = 60.0 + (index * 40.0);
          return Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey.withOpacity(0.3),
                width: 1,
              ),
            ),
          );
        }),

        // Inaktives Zentrum
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[400],
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '---',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              Text(
                'Offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
        ),

        // Disconnected Icon
        Positioned(
          top: 60,
          child: Icon(
            Icons.signal_wifi_off,
            size: 40,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }
}