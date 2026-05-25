import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/gpx_service.dart';

class TripHistoryPage extends StatefulWidget {
  const TripHistoryPage({super.key});

  @override
  State<TripHistoryPage> createState() => _TripHistoryPageState();
}

class _TripHistoryPageState extends State<TripHistoryPage> {
  final GPXService _gpxService = GPXService();
  List<_ParsedTrack> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    setState(() => _isLoading = true);
    try {
      final files = await _gpxService.listRecordedTracks();
      final List<_ParsedTrack> parsed = [];
      
      for (final entity in files) {
        if (entity is File && entity.path.endsWith('.gpx')) {
          final content = await entity.readAsString();
          parsed.add(_parseGPX(entity.path, content));
        }
      }
      setState(() {
        _tracks = parsed;
      });
    } catch (e) {
      debugPrint('Error loading tracks: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  _ParsedTrack _parseGPX(String filePath, String content) {
    // Regex matching for metadata values
    final nameMatch = RegExp(r'<name>(.*?)</name>').firstMatch(content);
    final distanceMatch = RegExp(r'<distance_km>(.*?)</distance_km>').firstMatch(content);
    final durationMatch = RegExp(r'<duration_sec>(.*?)</duration_sec>').firstMatch(content);
    final maxSpeedMatch = RegExp(r'<max_speed_kmh>(.*?)</max_speed_kmh>').firstMatch(content);
    final avgSpeedMatch = RegExp(r'<avg_speed_kmh>(.*?)</avg_speed_kmh>').firstMatch(content);
    final timeMatch = RegExp(r'<time>(.*?)</time>').firstMatch(content);

    final name = nameMatch?.group(1) ?? 'Unnamed Track';
    final distance = double.tryParse(distanceMatch?.group(1) ?? '0.0') ?? 0.0;
    final durationSec = int.tryParse(durationMatch?.group(1) ?? '0') ?? 0;
    final maxSpeed = double.tryParse(maxSpeedMatch?.group(1) ?? '0.0') ?? 0.0;
    final avgSpeed = double.tryParse(avgSpeedMatch?.group(1) ?? '0.0') ?? 0.0;
    
    DateTime? startTime;
    if (timeMatch != null) {
      startTime = DateTime.tryParse(timeMatch.group(1) ?? '');
    }

    return _ParsedTrack(
      filePath: filePath,
      name: name,
      distanceKm: distance,
      durationSeconds: durationSec,
      maxSpeedKmh: maxSpeed,
      avgSpeedKmh: avgSpeed,
      startTime: startTime ?? File(filePath).statSync().modified,
    );
  }

  String _formatDuration(int totalSecs) {
    final int hours = totalSecs ~/ 3600;
    final int minutes = (totalSecs % 3600) ~/ 60;
    final int seconds = totalSecs % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  Future<void> _deleteTrack(String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip Log'),
        content: const Text('Are you sure you want to permanently delete this recorded trip?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _gpxService.deleteTrack(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip log deleted')),
      );
      _loadTracks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorded Trips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTracks,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) {
                    final track = _tracks[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.name,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Recorded on: ${track.startTime.toLocal().toString().substring(0, 16)}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                                  onPressed: () => _deleteTrack(track.filePath),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            // Metrics Grid Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildMetric(
                                  context,
                                  icon: Icons.directions_walk,
                                  label: 'Distance',
                                  value: '${track.distanceKm.toStringAsFixed(2)} km',
                                ),
                                _buildMetric(
                                  context,
                                  icon: Icons.timer,
                                  label: 'Duration',
                                  value: _formatDuration(track.durationSeconds),
                                ),
                                _buildMetric(
                                  context,
                                  icon: Icons.speed,
                                  label: 'Avg Speed',
                                  value: '${track.avgSpeedKmh.toStringAsFixed(1)} km/h',
                                ),
                                _buildMetric(
                                  context,
                                  icon: Icons.bolt,
                                  label: 'Max Speed',
                                  value: '${track.maxSpeedKmh.toStringAsFixed(1)} km/h',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // File Location footer
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Text(
                                'Path: .../GPX_Tracks/${track.filePath.split('/').last}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[500],
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildMetric(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[500], fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.route_outlined,
              size: 80,
              color: theme.colorScheme.secondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 20),
            Text(
              'No Recorded Trips Yet',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Your recorded routes will appear here. Start a trip recording on the Map page to log your metrics.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParsedTrack {
  final String filePath;
  final String name;
  final double distanceKm;
  final int durationSeconds;
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final DateTime startTime;

  _ParsedTrack({
    required this.filePath,
    required this.name,
    required this.distanceKm,
    required this.durationSeconds,
    required this.maxSpeedKmh,
    required this.avgSpeedKmh,
    required this.startTime,
  });
}
