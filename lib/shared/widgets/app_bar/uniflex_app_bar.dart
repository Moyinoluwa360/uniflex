import 'package:flutter/material.dart';

/// Standard app bar. Thin wrapper around [AppBar] so every screen gets the
/// theme's flat, borderless style automatically instead of screens
/// reaching for raw [AppBar] with ad-hoc elevation/colour overrides.
class UniflexAppBar extends StatelessWidget implements PreferredSizeWidget {
  const UniflexAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = false,
  });

  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title != null ? Text(title!) : null,
      leading: leading,
      actions: actions,
      centerTitle: centerTitle,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
