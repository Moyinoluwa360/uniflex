import 'package:flutter/material.dart';

/// App-wide scrolling behaviour: dragging ANY scroll view (forms, sheets,
/// dialogs, lists) takes focus off the text field, which hides the keyboard
/// and with it the selection highlight, handles and toolbar. A scroll view
/// can still opt out with its own `keyboardDismissBehavior`.
///
/// Set once on `MaterialApp.scrollBehavior`.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
          BuildContext context) =>
      ScrollViewKeyboardDismissBehavior.onDrag;
}

/// Tapping any empty part of the screen takes focus off the current text
/// field. Wrapped once around the whole app (`MaterialApp.builder`).
///
/// A plain translucent tap detector: taps that land on a button, a text
/// field or anything else that handles taps win the gesture and do NOT
/// reach it, so nothing else changes behaviour.
class TapOutsideUnfocus extends StatelessWidget {
  const TapOutsideUnfocus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}
