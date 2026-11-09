import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_glass_nav_bar.dart';

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
    this.currentIndex = 0,
    required super.child,
  });

  /// Switch the shell to the tab at [index].
  final void Function(int index) go;

  /// The tab currently showing (tabs live in an IndexedStack, so a tab's
  /// screen stays built while hidden — it can watch this to refresh when it
  /// becomes the visible one).
  final int currentIndex;

  static AppNavShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppNavShellScope>();

  @override
  bool updateShouldNotify(AppNavShellScope oldWidget) =>
      go != oldWidget.go || currentIndex != oldWidget.currentIndex;
}

/// Reusable bottom-nav scaffold: [IndexedStack] body + [BottomNavigationBar],
/// so each role builds it own tab shell (StudentShell, RiderShell,
/// AdminShell) from the same widget rather than each hand-rolling
/// navigation chrome. This widget holds no cross-role state — each shell
/// instance owns its own selected-tab state independently.
///
/// Pass [badgeCounts] to show numeric badges on nav items. The list length
/// must match [tabs]; a value of 0 hides the badge for that item.
class AppBottomNavShell extends ConsumerStatefulWidget {
  const AppBottomNavShell({
    super.key,
    required this.tabs,
    this.badgeCounts,
    this.glass = false,
  });

  final List<AppNavTab> tabs;

  /// Use the floating [AppGlassNavBar] (content scrolls under it) instead of
  /// the classic bottom bar. Same tabs, same index/callback logic. Screens in
  /// a glass shell pad their bottom with `AppSpacing.navClearanceOf(context)`.
  final bool glass;

  /// Optional unread/badge counts, one per tab. Zero = no badge.
  final List<int>? badgeCounts;

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

  Widget _badgedIcon(IconData icon, int tabIndex, {required bool selected}) {
    final count =
        widget.badgeCounts != null && tabIndex < widget.badgeCounts!.length
            ? widget.badgeCounts![tabIndex]
            : 0;
    final child = Icon(icon);
    if (count <= 0) return child;
    return Badge(
      label: Text('$count'),
      child: child,
    );
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

    if (widget.glass) {
      // The Scaffold grows the body's bottom padding by the bar's height;
      // put the real device inset back so `AppSpacing.navClearanceOf` is
      // (bar + gap + safe area) exactly once.
      final deviceBottom = MediaQuery.paddingOf(context).bottom;
      return Scaffold(
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Builder(
            builder: (context) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  padding: mq.padding.copyWith(bottom: deviceBottom),
                ),
                child: AppNavShellScope(
                  go: _go,
                  currentIndex: _index,
                  child: IndexedStack(
                    index: _index,
                    children: widget.tabs.map((tab) => tab.screen).toList(),
                  ),
                ),
              );
            },
          ),
        ),
        bottomNavigationBar: AppGlassNavBar(
          items: [
            for (var i = 0; i < widget.tabs.length; i++)
              AppGlassNavItem.fromTab(
                widget.tabs[i],
                badgeCount: widget.badgeCounts != null &&
                        i < widget.badgeCounts!.length
                    ? widget.badgeCounts![i]
                    : 0,
              ),
          ],
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: AppNavShellScope(
          go: _go,
          currentIndex: _index,
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
          for (var i = 0; i < widget.tabs.length; i++)
            BottomNavigationBarItem(
              icon: _badgedIcon(widget.tabs[i].icon, i, selected: false),
              activeIcon:
                  _badgedIcon(widget.tabs[i].selectedIcon, i, selected: true),
              label: widget.tabs[i].label,
            ),
        ],
      ),
    );
  }
}
