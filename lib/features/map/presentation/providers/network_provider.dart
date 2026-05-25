import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider =
    StreamProvider<bool>((ref) async* {
  // Yield initial connectivity state immediately
  try {
    final initialResults = await Connectivity().checkConnectivity();
    yield !initialResults.contains(ConnectivityResult.none);
  } catch (_) {
    yield false;
  }

  await for (final results
      in Connectivity().onConnectivityChanged) {
    yield !results.contains(ConnectivityResult.none);
  }
});

