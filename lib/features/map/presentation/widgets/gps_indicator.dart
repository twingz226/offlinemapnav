import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/location_provider.dart';

class GPSIndicator extends ConsumerWidget {

  const GPSIndicator({super.key});

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) {

    final location =
        ref.watch(locationProvider);

    return location.when(

      data: (pos) {

        return Chip(
          avatar: const Icon(
            Icons.gps_fixed,
            color: Colors.green,
          ),

          label: Text(
            'Accuracy ${pos?.accuracy.toStringAsFixed(1)}m',
          ),
        );
      },

      loading: () => const Chip(
        avatar: CircularProgressIndicator(strokeWidth: 2),
        label: Text('Searching GPS'),
      ),

      error: (_, __) => const Chip(
        avatar: Icon(Icons.gps_off, color: Colors.red),
        label: Text('GPS Error'),
      ),
    );
  }
}
