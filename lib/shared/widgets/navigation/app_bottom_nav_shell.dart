import 'package:flutter/material.dart';

/// One tab of an [AppBottomNavShell]: the icon/label pair for the nav bar
/// plus the screen it shows.
class AppNavTab {
  const AppNavTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

/// Reusable bottom-nav scaffold: [IndexedStack] body + [BottomNavigationBar],
/// so each role builds it own tab shell (StudentShell, RiderShell,
/// AdminShell) from the same widget rather than each hand-rolling
/// navigation chrome. This widget holds no cross-role state — each shell
/// instance owns its own selected-tab state independently.
class AppBottomNavShell extends StatefulWidget {
  const AppBottomNavShell({super.key, required this.tabs});

  final List<AppNavTab> tabs;

  @override
  State<AppBottomNavShell> createState() => _AppBottomNavShellState();
}

class _AppBottomNavShellState extends State<AppBottomNavShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: widget.tabs.map((tab) => tab.screen).toList(),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          for (final tab in widget.tabs)
            BottomNavigationBarItem(
              icon: Icon(tab.icon),
              activeIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
