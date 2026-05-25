import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/download_provider.dart';

class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Maps'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header description
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Download map regions for offline use. Cached tiles will be '
              'available even without an internet connection.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // Build a card for each available region
          for (final region in availableRegions)
            _RegionCard(region: region, downloadState: downloadState),
        ],
      ),
    );
  }
}

class _RegionCard extends ConsumerWidget {
  final DownloadableRegion region;
  final DownloadState downloadState;

  const _RegionCard({
    required this.region,
    required this.downloadState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDownloading = downloadState.status == DownloadStatus.downloading;
    final isCompleted = downloadState.status == DownloadStatus.completed;
    final isError = downloadState.status == DownloadStatus.error;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Region info header
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            leading: CircleAvatar(
              backgroundColor: isCompleted
                  ? Colors.green.shade100
                  : isError
                      ? Colors.red.shade100
                      : theme.colorScheme.primaryContainer,
              child: Icon(
                isCompleted
                    ? Icons.check_circle
                    : isError
                        ? Icons.error
                        : Icons.map,
                color: isCompleted
                    ? Colors.green.shade700
                    : isError
                        ? Colors.red.shade700
                        : theme.colorScheme.primary,
              ),
            ),
            title: Text(
              region.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'Zoom levels ${region.minZoom}–${region.maxZoom}',
              style: theme.textTheme.bodySmall,
            ),
          ),

          // Status & stats section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDownloading) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: downloadState.progress / 100,
                            minHeight: 8,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${downloadState.progress.toStringAsFixed(1)}%',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Downloading tiles…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],

                if (isCompleted) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.storage, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        '${downloadState.tileCount} tiles  •  ${downloadState.formattedSize}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.check, size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Ready for offline use',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],

                if (isError) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.warning_amber, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Download failed. Tap to retry.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (downloadState.tileCount > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${downloadState.tileCount} tiles partially cached (${downloadState.formattedSize})',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Delete button (only when tiles exist)
                if (isCompleted || (isError && downloadState.tileCount > 0))
                  TextButton.icon(
                    onPressed: isDownloading
                        ? null
                        : () => _confirmDelete(context, ref),
                    icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                    label: Text(
                      'Delete',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),

                const SizedBox(width: 8),

                // Download / Re-download button
                if (!isDownloading)
                  FilledButton.icon(
                    onPressed: () {
                      ref.read(downloadProvider.notifier).startDownload(region);
                    },
                    icon: Icon(isCompleted ? Icons.refresh : Icons.download),
                    label: Text(isCompleted
                        ? 'Re-download'
                        : isError
                            ? 'Retry'
                            : 'Download'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Offline Map?'),
        content: Text(
          'This will remove all cached tiles for ${region.name}. '
          'You will need to re-download them for offline use.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ref.read(downloadProvider.notifier).deleteDownload();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Offline map deleted')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
