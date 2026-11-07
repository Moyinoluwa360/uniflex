import 'package:flutter/material.dart';

import 'app_bottom_nav_shell.dart';

/// Calls [onVisible] each time the enclosing [AppBottomNavShell] switches TO
/// tab [tabIndex]. Tabs sit in an IndexedStack, so their screens are built
/// once and kept — without this, a data tab would only load when the app
/// starts and then go stale.
///
/// Outside a shell (no scope) it does nothing.
class RefreshOnTabVisible extends StatefulWidget {
  const RefreshOnTabVisible({
    super.key,
    required this.tabIndex,
    required this.onVisible,
    required this.child,
  });

  final int tabIndex;
  final VoidCallback onVisible;
  final Widget child;

  @override
  State<RefreshOnTabVisible> createState() => _RefreshOnTabVisibleState();
}

class _RefreshOnTabVisibleState extends State<RefreshOnTabVisible> {
  int? _last;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final now = AppNavShellScope.of(context)?.currentIndex;
    if (now != null &&
        _last != null &&
        _last != now &&
        now == widget.tabIndex) {
      // After this frame so we never touch providers mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onVisible();
      });
    }
    _last = now;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
