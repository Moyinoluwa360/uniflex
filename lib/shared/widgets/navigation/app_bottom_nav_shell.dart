import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A pending "switch to this tab" request from a screen that is *pushed on
/// top of* the shell rather than living inside it.
///
/// [AppNavShellScope] only reaches descendants of the shell's body, so a
/// route pushed onto the root navigator (Checkout, for example) cannot see
/// it — `AppNavShellScope.of(context)` returns null there. Such a screen
/// sets this instead, then pops back to the shell, which picks the request
/// up and switches tabs. The shell clears it once consumed, so it never
/// leaks across sign-outs or role changes.
final shellTabRequestProvider = StateProvider<int?>((ref) => null);

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

/// Lets a descendant screen switch the enclosing shell's active tab —
/// e.g. the Home header's "Top up" button jumping to the Wallet tab —
/// without threading callbacks through every widget. Obtain it with
/// `AppNavShellScope.of(context)?.go(index)`.
class AppNavShellScope extends InheritedWidget {
  const AppNavShellScope({
    super.key,
    required this.go,
    required super.child,
  });

  /// Switch the shell to the tab at [index].
  final void Function(int index) go;

  static AppNavShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppNavShellScope>();

  @override
  bool updateShouldNotify(AppNavShellScope oldWidget) => go != oldWidget.go;
}

/// Reusable bottom-nav scaffold: [IndexedStack] body + [BottomNavigationBar],
/// so each role builds it own tab shell (StudentShell, RiderShell,
/// AdminShell) from the same widget rather than each hand-rolling
/// navigation chrome. This widget holds no cross-role state — each shell
/// instance owns its own selected-tab state independently.
class AppBottomNavShell extends ConsumerStatefulWidget {
  const AppBottomNavShell({super.key, required this.tabs});

  final List<AppNavTab> tabs;

  @override
  ConsumerState<AppBottomNavShell> createState() => _AppBottomNavShellState();
}

class _AppBottomNavShellState extends ConsumerState<AppBottomNavShell> {
  int _index = 0;

  void _go(int index) {
    if (index >= 0 && index < widget.tabs.length) {
      setState(() => _index = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int?>(shellTabRequestProvider, (_, next) {
      if (next == null) return;
      _go(next);
      // Clear outside the listener so we are not mutating provider state
      // during a build triggered by that same state.
      Future.microtask(
        () => ref.read(shellTabRequestProvider.notifier).state = null,
      );
    });

    return Scaffold(
      body: SafeArea(
        child: AppNavShellScope(
          go: _go,
          child: IndexedStack(
            index: _index,
            children: widget.tabs.map((tab) => tab.screen).toList(),
          ),
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
