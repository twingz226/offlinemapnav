import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_provider.dart';

class OfflineSearchBar extends ConsumerWidget {
  const OfflineSearchBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search offline places...',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      onChanged: (query) {
        ref.read(searchQueryProvider.notifier).state = query;
      },
    );
  }
}

