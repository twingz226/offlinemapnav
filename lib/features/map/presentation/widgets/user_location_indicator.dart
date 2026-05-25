import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';

class UserLocationIndicator extends StatefulWidget {
  final Position? userPosition;
  final bool isNavigating;

  const UserLocationIndicator({
    super.key,
    required this.userPosition,
    this.isNavigating = false,
  });

  @override
  State<UserLocationIndicator> createState() => _UserLocationIndicatorState();
}

class _UserLocationIndicatorState extends State<UserLocationIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  StreamSubscription<CompassEvent>? _compassSubscription;
  
  // Track target heading in degrees (can grow beyond [0, 360] to ensure shortest-path rotation)
  double _targetHeading = 0.0;
  double _lastRawHeading = 0.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _startCompassListening();
  }

  void _startCompassListening() {
    _compassSubscription?.cancel();
    _compassSubscription = FlutterCompass.events?.listen((event) {
      final double? heading = event.heading;
      if (heading != null && mounted) {
        _updateHeading(heading);
      }
    });
  }

  void _updateHeading(double newRawHeading) {
    setState(() {
      // Calculate shortest-path rotation to prevent 360-degree spins
      double diff = newRawHeading - _lastRawHeading;
      
      // Normalize diff to [-180, 180]
      diff = (diff + 180) % 360;
      if (diff < 0) diff += 360;
      diff -= 180;

      _targetHeading += diff;
      _lastRawHeading = newRawHeading;
    });
  }

  @override
  void didUpdateWidget(covariant UserLocationIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the compass stream is not emitting, we fall back to the GPS heading when moving
    if (widget.userPosition != null && widget.userPosition!.speed > 0.8) {
      final gpsHeading = widget.userPosition!.heading;
      if (gpsHeading > 0 && gpsHeading != _lastRawHeading) {
        _updateHeading(gpsHeading);
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _compassSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showChevron = widget.isNavigating ||
        (widget.userPosition != null && widget.userPosition!.speed > 0.8);

    final double radians = _targetHeading * math.pi / 180;

    return Center(
      child: SizedBox(
        width: 160,
        height: 160,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Pulsing Halo (always visible to denote active GPS signal)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 24 + (76 * _pulseController.value),
                  height: 24 + (76 * _pulseController.value),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.25 * (1.0 - _pulseController.value)),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.4 * (1.0 - _pulseController.value)),
                      width: 1.5,
                    ),
                  ),
                );
              },
            ),

            // 2. Smoothly animated direction indicator
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: radians, end: radians),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              builder: (context, animatedRadians, child) {
                return Transform.rotate(
                  angle: animatedRadians,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Directional Cone (compass/orientation flashlight)
                      // Only show when not in navigation mode (or when stationary)
                      if (!showChevron)
                        CustomPaint(
                          size: const Size(160, 160),
                          painter: DirectionConePainter(
                            color: Colors.blueAccent.shade400,
                          ),
                        ),

                      // Chevron for navigation/movement mode
                      if (showChevron)
                        Positioned(
                          top: 48, // slightly offset forward along the heading
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CustomPaint(
                              painter: NavigationChevronPainter(
                                color: Colors.blueAccent.shade700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),

            // 3. Central Dot (only when not showing the chevron as the main indicator)
            if (!showChevron)
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.shade700,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            
            // 4. Subtle center dot when showing chevron to tie it back to exact position
            if (showChevron)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DirectionConePainter extends CustomPainter {
  final Color color;

  DirectionConePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;
    final Offset center = Offset(width / 2, height / 2);
    final double radius = width / 2;

    // Outer gradient cone
    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.45),
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, width, height))
      ..style = PaintingStyle.fill;

    // Span angle is 50 degrees (converted to radians)
    const double sweepAngle = 50 * math.pi / 180;
    // We want the arc to point straight UP (North = -pi / 2)
    const double startAngle = -math.pi / 2 - sweepAngle / 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      true,
      paint,
    );

    // Draw high-tech side lines for the flashlight beam
    final double halfSweep = sweepAngle / 2;
    final double leftAngle = -math.pi / 2 - halfSweep;
    final double rightAngle = -math.pi / 2 + halfSweep;

    final Offset leftEnd = Offset(
      center.dx + radius * math.cos(leftAngle),
      center.dy + radius * math.sin(leftAngle),
    );
    final Offset rightEnd = Offset(
      center.dx + radius * math.cos(rightAngle),
      center.dy + radius * math.sin(rightAngle),
    );

    final linePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.6),
          color.withValues(alpha: 0.2),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, width, height))
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(center, leftEnd, linePaint);
    canvas.drawLine(center, rightEnd, linePaint);
  }

  @override
  bool shouldRepaint(covariant DirectionConePainter oldDelegate) => false;
}

class NavigationChevronPainter extends CustomPainter {
  final Color color;

  NavigationChevronPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final double w = size.width;
    final double h = size.height;

    // Draw a modern, sharp chevron pointing UP
    path.moveTo(w / 2, 0);
    path.lineTo(w, h);
    path.lineTo(w / 2, h * 0.72);
    path.lineTo(0, h);
    path.close();

    // Draw subtle shadow first
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant NavigationChevronPainter oldDelegate) => false;
}
