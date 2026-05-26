import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'dart:async';
import 'dart:math' as math;

import '../../../../core/constants/tile_config.dart';
import '../../data/models/favorite_place_model.dart';
import 'main_navigation_page.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _progressController;
  late final Animation<double> _progressAnimation;
  
  String _statusText = 'Loading Offline Map System...';

  @override
  void initState() {
    super.initState();

    // Pulse animation for the radar/glow rings behind the logo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Smooth progress bar controller
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOutCubic),
    )..addListener(() {
        setState(() {});
      });

    // Start initialization sequence
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Remove native splash screen as Flutter's first frame is painted
      FlutterNativeSplash.remove();
      _runInitialization();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _runInitialization() async {
    final stopwatch = Stopwatch()..start();

    try {
      // Phase 1: Initialize Hive
      setState(() {
        _statusText = 'Initializing Local Storage...';
      });
      _progressController.animateTo(0.3, duration: const Duration(milliseconds: 500));
      
      await Hive.initFlutter();
      Hive.registerAdapter(FavoritePlaceModelAdapter());
      await Hive.openBox<FavoritePlaceModel>('favoritesBox');
      await Hive.openBox('routesCache');
      await Hive.openBox('routesHistory');
      await Hive.openBox('osm_graphs');
      
      await Future.delayed(const Duration(milliseconds: 200));

      // Phase 2: Initialize Offline Map Tile Caching
      setState(() {
        _statusText = 'Loading Navigation Engine...';
      });
      _progressController.animateTo(0.6, duration: const Duration(milliseconds: 500));
      
      await FMTCObjectBoxBackend().initialise();
      
      await Future.delayed(const Duration(milliseconds: 200));

      // Phase 3: Setup Tile Store
      setState(() {
        _statusText = 'Setting Up Map Tiles...';
      });
      _progressController.animateTo(0.85, duration: const Duration(milliseconds: 400));
      
      final store = const FMTCStore(TileConfig.storeName);
      if (!await store.manage.ready) {
        await store.manage.create();
      }

      await Future.delayed(const Duration(milliseconds: 200));

      // Phase 4: Ready
      setState(() {
        _statusText = 'Ready';
      });
      _progressController.animateTo(1.0, duration: const Duration(milliseconds: 300));
      
    } catch (e) {
      debugPrint('Initialization error: $e');
      setState(() {
        _statusText = 'Error during setup. Proceeding...';
      });
    }

    // Ensure the splash screen stays for at least 2.2 seconds for a premium feel
    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed < 2200) {
      await Future.delayed(Duration(milliseconds: 2200 - elapsed));
    }

    if (mounted) {
      // Transition to MainNavigationPage with a premium fade transition
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const MainNavigationPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Premium dark/light themes for splash page
    final backgroundColor = isDark ? const Color(0xFF121212) : const Color(0xFFF9FAFB);
    final progressColor = isDark ? Colors.blueAccent : const Color(0xFF2563EB);
    final progressBgColor = isDark ? Colors.white12 : Colors.black12;
    final textColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Background Radar Pulses (Navigation theme)
          ...List.generate(3, (index) {
            final animationValue = (_pulseController.value + (index * 0.33)) % 1.0;
            return Center(
              child: Container(
                width: 120 + (animationValue * 260),
                height: 120 + (animationValue * 260),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: progressColor.withValues(alpha: (1.0 - animationValue) * 0.15),
                    width: 1.5,
                  ),
                ),
              ),
            );
          }),

          // Content Column
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with subtle floating scale animation
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = 1.0 + 0.03 * math.sin(_pulseController.value * 2 * math.pi);
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: Image.asset(
                    'assets/logo.png',
                    width: 140,
                    height: 140,
                    fit: BoxFit.contain,
                  ),
                ),
                
                const SizedBox(height: 60),

                // Modern Linear Progress Indicator (glowing thin bar)
                Container(
                  width: 220,
                  height: 4,
                  decoration: BoxDecoration(
                    color: progressBgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(
                    children: [
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progressAnimation.value,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: LinearGradient(
                              colors: [
                                progressColor.withValues(alpha: 0.7),
                                progressColor,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: progressColor.withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),

                // Animated status description
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _statusText,
                    key: ValueKey<String>(_statusText),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Premium bottom branding label
          Positioned(
            bottom: 40,
            child: Text(
              'OFFLINE NAVIGATOR',
              style: TextStyle(
                color: textColor.withValues(alpha: 0.4),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
