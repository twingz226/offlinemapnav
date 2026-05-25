import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

class CompassWidget extends StatelessWidget {
  const CompassWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CompassEvent>(
      stream: FlutterCompass.events,
      builder: (context, snapshot) {
        final direction = snapshot.data?.heading ?? 0;
        final radians = direction * (math.pi / 180) * -1;

        return Transform.rotate(
          angle: radians,
          child: const Icon(
            Icons.navigation,
            size: 60,
            color: Colors.blueAccent,
          ),
        );
      },
    );
  }
}
