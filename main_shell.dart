import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'notifications_screen.dart' as notif;
import 'dashboard_screen.dart' as dash;
import 'camera_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

// MainShell is the main navigation container of the app.
// It keeps the major pages of the app inside one shared structure and switches between them using the bottom navigation bar.
// This screen is important because it acts like the "main frame" after the user logs in successfully.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // Stores the index of the currently selected bottom navigation tab.
  // Default is 0, which means the app opens on the Home page first.
  int _selectedIndex = 0;

  // Helper method used to switch directly to the Camera tab.
  // This is useful because another page, such as HomeScreen, can call this callback without needing to control the whole shell itself.
  void _goToCameraTab() {
    setState(() {
      _selectedIndex = 3;
    });
  }

  // List of pages managed by the shell.
  // The order here must match: the titles list, the bottom navigation items
  // IndexedStack later uses this list so the currently selected page is shown while preserving the state of the others.
  late final List<Widget> _pages = [
    HomeScreen(onOpenCameraTab: _goToCameraTab),
    const notif.NotificationsScreen(),
     dash.DashboardScreen(),
    const CameraScreen(),
    const ProfileScreen(),
  ];

  // Titles shown in the app bar.
  // The currently displayed title depends on the selected tab index.
  final List<String> _titles = [
    "Home",
    "Notifications",
    "Dashboard",
    "Camera",
    "Profile",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  backgroundColor: const Color(0xFF0D1B2A),

  // Removes the app bar shadow for a flatter cleaner top bar.
  elevation: 0,

  // App bar title changes dynamically depending on the selected tab.
  title: Text(
    _titles[_selectedIndex],
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
    ),
  ),

  // Action buttons shown on the right side of the app bar.
  actions: [
    Padding(
      padding: const EdgeInsets.only(right: 10),
      child: IconButton(
        icon: const Icon(
          Icons.settings_rounded,
          color: Colors.white,
          size: 28,
        ),

        // Opens the Settings screen when the gear icon is tapped.
        // This pushes a new route on top of MainShell, instead of replacing the shell itself.
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SettingsScreen(),
            ),
          );
        },
      ),
    ),
  ],
),

      // IndexedStack is used instead of directly swapping body widgets.
      // This is important because IndexedStack keeps the inactive pages alive, which means their state is preserved when moving between tabs.
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),

      // Bottom navigation bar that controls the main app sections.
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,

        // When a tab is tapped, update the selected index so the corresponding page and title are shown.
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },

        // Fixed type allows all items to remain visible since there are more than three tabs.
        type: BottomNavigationBarType.fixed,

        // Active tab color.
        selectedItemColor: const Color(0xFF4A90E2),

        // Inactive tab color.
        unselectedItemColor: Colors.grey,

        // List of bottom navigation items.
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.videocam_outlined),
            activeIcon: Icon(Icons.videocam),
            label: 'Camera',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}