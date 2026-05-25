import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/network_provider.dart';

class OfflineBanner extends ConsumerWidget {

  const OfflineBanner({super.key});

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) {

    final connectivity =
        ref.watch(connectivityProvider);

    return connectivity.when(

      data: (isOnline) {

        if (isOnline) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          color: Colors.red,

          padding: const EdgeInsets.all(8),

          child: const Text(
            'OFFLINE MODE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
            ),
          ),
        );
      },

      loading: () =>
          const SizedBox.shrink(),

      error: (_, __) =>
          const SizedBox.shrink(),
    );
  }
}
