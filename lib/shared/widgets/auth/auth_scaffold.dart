import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Shared layout of Login and the sign-up screens (UI Polish 3).
///
///  * [header] (an `AppAuthHeader`) and [body] scroll together in one scroll
///    view, so the keyboard never squashes the header.
///  * [footer] (the screen's one primary button) is pinned at the bottom,
///    above the keyboard when it is open. Content scrolls under it through a
///    22 px fade. Same keyboard-aware pattern as the chat fix: the Scaffold
///    resizes for the keyboard, the content scrolls, a focused field scrolls
///    into view.
///  * [caption] (Login's "Redeemer's University") is hidden while the
///    keyboard is open or the screen is too short/zoomed for it.
class AppAuthScaffold extends StatelessWidget {
  const AppAuthScaffold({
    super.key,
    required this.header,
    required this.body,
    this.footer,
    this.caption,
    this.appBar,
  });

  final Widget header;
  final Widget body;
  final AppPinnedFooter? footer;
  final Widget? caption;
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboardOpen = View.of(context).viewInsets.bottom > 0;
    final roomForCaption = !keyboardOpen &&
        footer == null &&
        mq.size.height >= 700 &&
        mq.textScaler.scale(16) <= 16 * 1.15;

    return Scaffold(
      appBar: appBar,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.screenGutter,
                        0, AppSpacing.screenGutter, 24),
                    child: body,
                  ),
                ],
              ),
            ),
          ),
          if (footer != null) footer!,
          if (caption != null && roomForCaption)
            Padding(
              padding: EdgeInsets.only(bottom: 34 + mq.padding.bottom),
              child: Center(child: caption),
            ),
        ],
      ),
    );
  }
}

/// The pinned bottom action: [primary] (the one `AppButton`) with 20 px sides
/// and 30 px below it (plus the home-indicator inset). [secondary] (e.g. "Already
/// have an account? Log in") sits under it and is hidden while the keyboard is
/// open, so the field being typed in always has room.
class AppPinnedFooter extends StatelessWidget {
  const AppPinnedFooter({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final keyboardOpen = View.of(context).viewInsets.bottom > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 22 px fade so scrolling content slides under the button softly.
        Positioned(
          left: 0,
          right: 0,
          top: -22,
          height: 22,
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('footer-fade'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.background.withValues(alpha: 0), c.background],
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: c.background,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            4,
            AppSpacing.screenGutter,
            keyboardOpen ? 14 : 30 + safeBottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              if (secondary != null && !keyboardOpen) ...[
                const SizedBox(height: AppSpacing.sm),
                secondary!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
