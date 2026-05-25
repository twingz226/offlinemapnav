import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../providers/navigation_provider.dart';



class HudNavigationPage extends ConsumerStatefulWidget {
  const HudNavigationPage({super.key});

  @override
  ConsumerState<HudNavigationPage> createState() => _HudNavigationPageState();
}

class _HudNavigationPageState extends ConsumerState<HudNavigationPage> {
  bool _isProjectorMode = false;

  IconData _getTurnIcon(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('left')) {
      return Icons.turn_left_rounded;
    } else if (lower.contains('right')) {
      return Icons.turn_right_rounded;
    } else if (lower.contains('arrive')) {
      return Icons.place_rounded;
    } else if (lower.contains('straight')) {
      return Icons.arrow_upward_rounded;
    }
    return Icons.navigation_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationProvider);
    final activeRoute = navState.activeRoute;

    // Safety fallback: if navigation ends, close the HUD screen automatically
    if (!navState.isNavigating || activeRoute == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context);
        }
      });
      return const Scaffold(backgroundColor: Colors.black);
    }

    final speedMps = navState.snappedPosition?.speed ?? 0.0;
    final speedKmh = speedMps * 3.6;
    final speedLimit = navState.currentSpeedLimit;
    final isSpeeding = speedKmh > speedLimit * 1.1;

    final steps = activeRoute.steps;
    final currentStep = navState.currentStepIndex < steps.length
        ? steps[navState.currentStepIndex]
        : null;
    final turnInstruction = currentStep?.instruction ?? 'Drive safely';

    // HUD Projector transformation
    Widget content = Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top Section: Turn-by-Turn Instruction
          Column(
            children: [
              Icon(
                _getTurnIcon(turnInstruction),
                size: 110,
                color: Colors.cyanAccent,
              ),
              const SizedBox(height: 12),
              Text(
                turnInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          // Middle Section: Speedometer & Speed Limit Sign
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Speed Display
              Column(
                children: [
                  Text(
                    speedKmh.toStringAsFixed(0),
                    style: TextStyle(
                      color: isSpeeding ? Colors.redAccent : Colors.greenAccent,
                      fontSize: 84,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2,
                    ),
                  ),
                  const Text(
                    'km/h',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 48),
              // Speed Limit Sign Circle
              _SpeedLimitSign(limit: speedLimit, isSpeeding: isSpeeding),
            ],
          ),

          // Bottom Section: Navigation Telemetry Data
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _TelemetryItem(
                    label: 'REMAINING',
                    value: navState.formattedRemainingDistance,
                    color: Colors.white,
                  ),
                  _TelemetryItem(
                    label: 'ETA',
                    value: navState.formattedETA,
                    color: Colors.cyanAccent,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // Action Buttons: HUD Toggle and Exit
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Toggle Windshield Projection Mode
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isProjectorMode = !_isProjectorMode;
                      });
                    },
                    icon: Icon(
                      _isProjectorMode ? Icons.screen_rotation : Icons.flip,
                      color: Colors.cyanAccent,
                    ),
                    label: Text(
                      _isProjectorMode ? 'Normal Mode' : 'Projector HUD',
                      style: const TextStyle(color: Colors.cyanAccent),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.cyanAccent, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Exit HUD Button
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade900,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Exit HUD'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    // Apply Vertical/Horizontal Mirror Transform for Windshield Projection Mode
    if (_isProjectorMode) {
      content = Transform(
        alignment: Alignment.center,
        // Flip vertically and rotate 180deg to mirror on windshield reflections correctly
        transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0)
          ..rotateZ(math.pi),
        child: content,
      );
    }



    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: content),
    );
  }
}

class _TelemetryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _TelemetryItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _SpeedLimitSign extends StatefulWidget {
  final double limit;
  final bool isSpeeding;

  const _SpeedLimitSign({
    required this.limit,
    required this.isSpeeding,
  });

  @override
  State<_SpeedLimitSign> createState() => _SpeedLimitSignState();
}

class _SpeedLimitSignState extends State<_SpeedLimitSign>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    if (widget.isSpeeding) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _SpeedLimitSign oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpeeding && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isSpeeding && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + (_pulseController.value * 0.12);
        return Transform.scale(
          scale: widget.isSpeeding ? scale : 1.0,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.isSpeeding ? Colors.red : Colors.red.shade900,
                width: 7,
              ),
              boxShadow: widget.isSpeeding
                  ? [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.6),
                        blurRadius: 16,
                        spreadRadius: 4,
                      )
                    ]
                  : [],

            ),
            alignment: Alignment.center,
            child: Text(
              widget.limit.toStringAsFixed(0),
              style: const TextStyle(
                color: Colors.black,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  }
}
