import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auto_download_provider.dart';

/// A modern, animated overlay that shows the auto-download status.
/// Appears as a floating toast/pill at the bottom of the map.
class AutoDownloadOverlay extends ConsumerStatefulWidget {
  const AutoDownloadOverlay({super.key});

  @override
  ConsumerState<AutoDownloadOverlay> createState() =>
      _AutoDownloadOverlayState();
}

class _AutoDownloadOverlayState extends ConsumerState<AutoDownloadOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  AutoDownloadStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _updateAnimation(AutoDownloadState dlState) {
    final shouldShow = dlState.shouldShowOverlay;
    if (shouldShow && !_slideController.isCompleted) {
      _slideController.forward();
    } else if (!shouldShow && _slideController.value > 0) {
      _slideController.reverse();
    }
    _lastStatus = dlState.status;
  }

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(autoDownloadProvider);
    
    // Schedule animation updates post-frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateAnimation(dlState);
    });

    // Initial trigger
    if (_lastStatus == null) {
      _updateAnimation(dlState);
    }

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: _buildContent(context, dlState),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AutoDownloadState dlState) {
    final isPrompting = dlState.status == AutoDownloadStatus.prompting;
    final isDownloading = dlState.status == AutoDownloadStatus.downloading;
    final isCompleted = dlState.status == AutoDownloadStatus.completed;
    final isError = dlState.status == AutoDownloadStatus.error;

    // Determine colors & icons
    final Color bgColor;
    final Color accentColor;
    final IconData icon;
    final String title;
    final String subtitle;

    if (isPrompting) {
      bgColor = const Color(0xFF1E1E38);
      accentColor = const Color(0xFFFFB74D);
      icon = Icons.location_city_outlined;
      // Show city name prominently
      final placeName = dlState.detectedPlace?.name ?? dlState.regionLabel ?? 'this area';
      title = 'Download $placeName?';
      subtitle = 'Save offline map data for this city.';
    } else if (isDownloading) {
      bgColor = const Color(0xFF1A1A2E);
      accentColor = const Color(0xFF4FC3F7);
      icon = Icons.cloud_download_outlined;
      final placeName = dlState.detectedPlace?.name ?? dlState.regionLabel;
      title = 'Downloading ${placeName ?? 'map'}…';
      subtitle = dlState.regionLabel != null
          ? 'Saving offline data'
          : 'Downloading tiles…';
    } else if (isCompleted) {
      bgColor = const Color(0xFF1B2E1B);
      accentColor = const Color(0xFF66BB6A);
      icon = Icons.cloud_done_outlined;
      final placeName = dlState.detectedPlace?.name;
      title = placeName != null ? '$placeName saved!' : 'Area saved for offline use';
      subtitle = '${dlState.tilesDownloaded} tiles cached';
    } else if (isError) {
      bgColor = const Color(0xFF2E1A1A);
      accentColor = const Color(0xFFEF5350);
      icon = Icons.cloud_off_outlined;
      title = 'Download interrupted';
      subtitle = 'Map will be cached when connection restores';
    } else {
      bgColor = Colors.transparent;
      accentColor = Colors.transparent;
      icon = Icons.cloud_outlined;
      title = '';
      subtitle = '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: bgColor.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: accentColor.withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: 0,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress bar (only while downloading)
                if (isDownloading)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: dlState.progress / 100),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    builder: (context, value, _) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 3,
                        backgroundColor: accentColor.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation(accentColor),
                      );
                    },
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: Row(
                    children: [
                      // Animated icon with glow
                      _AnimatedIcon(
                        icon: icon,
                        color: accentColor,
                        isAnimating: isDownloading,
                      ),
                      const SizedBox(width: 14),
                      // Text content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (isDownloading) ...[
                                  Text(
                                    '${dlState.progress.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: accentColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '•',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.3),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Dismiss button (not during prompting or downloading)
                      if (!isDownloading && !isPrompting)
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          onPressed: () {
                            ref.read(autoDownloadProvider.notifier).dismiss();
                          },
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                    ],
                  ),
                ),

                if (isPrompting) ...[
                  const Divider(color: Colors.white10, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: () {
                            ref.read(autoDownloadProvider.notifier).rejectDownload();
                          },
                          child: Text(
                            'Not Now',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          onPressed: () {
                            ref.read(autoDownloadProvider.notifier).confirmDownload();
                          },
                          label: const Text(
                            'Download',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An animated icon widget that pulses when downloading.
class _AnimatedIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final bool isAnimating;

  const _AnimatedIcon({
    required this.icon,
    required this.color,
    required this.isAnimating,
  });

  @override
  State<_AnimatedIcon> createState() => _AnimatedIconState();
}

class _AnimatedIconState extends State<_AnimatedIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _glowAnimation = Tween<double>(begin: 0.2, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isAnimating && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isAnimating ? _scaleAnimation.value : 1.0,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              boxShadow: widget.isAnimating
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: _glowAnimation.value),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              color: widget.color,
              size: 22,
            ),
          ),
        );
      },
    );
  }
}
