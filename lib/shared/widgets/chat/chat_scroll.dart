import 'package:flutter/material.dart';

/// Shared scroll + keyboard behaviour for every chat screen (student support
/// chat, admin support chat).
///
/// Chose the **scroll-controller** approach (not a reversed list): the data
/// source and its order stay exactly as they were, and there is nothing to
/// break if "load older messages" is ever added.
///
/// What it guarantees:
///  1. The list opens at the newest message ([onChatMessages] with
///     `initial: true`).
///  2. When the keyboard opens/closes, or the input grows, the list keeps the
///     newest message visible **if the user was already near the bottom**
///     (within [nearBottomExtent]). If they scrolled up to read, nothing moves.
///  3. Sending a message always scrolls to it ([scrollToNewest]).
///  4. A message that arrives scrolls into view only when the user is near the
///     bottom ([onChatMessages] with `initial: false`).
///
/// Usage: `class _S extends ConsumerState<X> with ChatScrollMixin<X>`, give the
/// message `ListView` `controller: chatScroll`, wrap the screen body in
/// [chatBody], and wrap the input bar in [ChatBottomInset].
mixin ChatScrollMixin<T extends StatefulWidget> on State<T> {
  /// How close to the bottom still counts as "at the bottom".
  static const double nearBottomExtent = 120;

  final ScrollController chatScroll = ScrollController();

  /// Last known "user is at the bottom" state, refreshed on every scroll
  /// event. Layout changes that do not move the offset (keyboard, input
  /// growing) leave it alone, which is what lets us tell "was at the bottom
  /// before the viewport shrank" from "scrolled up on purpose".
  bool _stick = true;

  _ChatMetricsObserver? _observer;
  double _lastKeyboard = 0;

  @override
  void initState() {
    super.initState();
    chatScroll.addListener(_trackStick);
    _observer = _ChatMetricsObserver(_onMetrics);
    WidgetsBinding.instance.addObserver(_observer!);
  }

  @override
  void dispose() {
    final o = _observer;
    if (o != null) WidgetsBinding.instance.removeObserver(o);
    chatScroll.removeListener(_trackStick);
    chatScroll.dispose();
    super.dispose();
  }

  void _trackStick() => _stick = isNearBottom;

  /// True when the list is at (or within [nearBottomExtent] of) its end, or
  /// has no content to scroll yet.
  bool get isNearBottom {
    if (!chatScroll.hasClients) return true;
    final p = chatScroll.position;
    return p.maxScrollExtent - p.pixels <= nearBottomExtent;
  }

  /// Scrolls to the newest message after layout settles (twice: a long
  /// list's extent is only final once the last items have been laid out).
  void scrollToNewest() {
    _stick = true;
    void jump() {
      if (chatScroll.hasClients) {
        chatScroll.jumpTo(chatScroll.position.maxScrollExtent);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      jump();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) jump();
      });
    });
  }

  /// Call when the message list loads (`initial: true`) or grows.
  void onChatMessages({required bool initial}) {
    if (initial || isNearBottom) scrollToNewest();
  }

  void _stickIfNeeded() {
    if (_stick) scrollToNewest();
  }

  void _onMetrics() {
    if (!mounted) return;
    final view = View.of(context);
    final keyboard = view.viewInsets.bottom / view.devicePixelRatio;
    if (keyboard == _lastKeyboard) return;
    _lastKeyboard = keyboard;
    // The keyboard animates, so this fires several times; each one keeps the
    // newest message pinned (only if the user was at the bottom).
    _stickIfNeeded();
  }

  /// Wrap the screen body in this so a growing input bar (up to five lines)
  /// keeps the newest message visible.
  Widget chatBody({required Widget child}) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _stickIfNeeded();
        return false;
      },
      child: child,
    );
  }
}

class _ChatMetricsObserver with WidgetsBindingObserver {
  _ChatMetricsObserver(this._onChange);
  final VoidCallback _onChange;

  @override
  void didChangeMetrics() => _onChange();
}

/// Bottom padding for a chat input bar: the home-indicator inset **only while
/// the keyboard is closed**, so there is no empty gap between the input bar
/// and the keyboard. Also reports size changes (the input growing) to
/// [ChatScrollMixin.chatBody].
class ChatBottomInset extends StatelessWidget {
  const ChatBottomInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Depend on MediaQuery so this rebuilds when the keyboard opens/closes
    // (`View.of` alone does not subscribe), but read the keyboard from the
    // raw view: a Scaffold may already have removed it from the body's
    // MediaQuery.
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final keyboardOpen = View.of(context).viewInsets.bottom > 0;
    return SizeChangedLayoutNotifier(
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardOpen ? 0 : safeBottom),
        child: child,
      ),
    );
  }
}
