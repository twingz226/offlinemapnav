import 'package:flutter/material.dart';
import 'map_page.dart';
import 'favorites_page.dart';
import 'settings_page.dart';

class MainNavigationPage
    extends StatefulWidget {

  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() =>
      _MainNavigationPageState();
}

class _MainNavigationPageState
    extends State<MainNavigationPage> {

  int currentIndex = 0;

  final pages = [
    const MapPage(),
    const FavoritesPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      body: pages[currentIndex],

      bottomNavigationBar: NavigationBar(

        selectedIndex: currentIndex,

        onDestinationSelected: (index) {
          setState(() {
            currentIndex = index;
          });
        },

        destinations: const [

          NavigationDestination(
            icon: Icon(Icons.map),
            label: 'Map',
          ),

          NavigationDestination(
            icon: Icon(Icons.favorite),
            label: 'Saved',
          ),

          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
