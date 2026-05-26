import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_provider.dart';
import '../providers/cache_provider.dart';
import 'trip_history_page.dart';
import 'navigation_routes_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final cacheState = ref.watch(cacheProvider);

    final isDarkMode = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            Theme.of(context).brightness == Brightness.dark);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.dark_mode),
            title: const Text('Dark Mode'),
            subtitle: Text(
              themeMode == ThemeMode.system
                  ? 'System default'
                  : themeMode == ThemeMode.dark
                      ? 'Enabled'
                      : 'Disabled',
            ),
            trailing: Switch(
              value: isDarkMode,
              onChanged: (value) {
                ref.read(themeProvider.notifier).state =
                    value ? ThemeMode.dark : ThemeMode.light;
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Cache Size'),
            subtitle: Text(
              cacheState.isLoading
                  ? 'Calculating size...'
                  : 'Cached: ${cacheState.tileCount} tiles (${cacheState.formattedSize})',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Manage Cache'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Map tiles are saved locally to allow offline usage.',
                      ),
                      const SizedBox(height: 16),
                      Text('Total Tiles: ${cacheState.tileCount}'),
                      Text('Total Size: ${cacheState.formattedSize}'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    if (cacheState.tileCount > 0)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context).colorScheme.onError,
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Clearing offline map cache...'),
                                duration: Duration(seconds: 1),
                            ),
                          );
                          await ref.read(cacheProvider.notifier).clearCache();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Cache cleared successfully'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Clear Cache'),
                      ),
                  ],
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.route_outlined),
            title: const Text('Recorded Trips'),
            subtitle: const Text('View and manage your saved GPX tracks'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TripHistoryPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.alt_route),
            title: const Text('Navigation Routes'),
            subtitle: const Text('View calculated routes and their average speeds'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NavigationRoutesPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            trailing: const Icon(Icons.chevron_right),

            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'MapWay',
                applicationVersion: '1.0.0',
                applicationIcon: const CircleAvatar(
                  child: Icon(Icons.map),
                ),
                applicationLegalese: '© 2026 MapWay Contributors',
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'MapWay is a privacy-first mapping and navigation '
                    'app designed for areas with poor or no internet connection. '
                    'It utilizes offline map storage, GPS tracking, saved locations, '
                    'and custom offline region downloads.',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

