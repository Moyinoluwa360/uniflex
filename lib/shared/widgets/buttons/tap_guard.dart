/// Fire-once guard used by every shared button (AppButton, AppIconButton).
///
/// There was no shared guard before UI Polish 1 (only per-screen
/// `_inFlight` / `_isSending` flags, which stay where they are). This one is
/// deliberately tiny and has no timers:
///  * a callback that returns a `Future` blocks further presses until the
///    future completes (success or error);
///  * a plain synchronous callback blocks presses for [syncWindow] after it
///    fired, which swallows a double tap. (After an async callback finishes
///    the button is usable again straight away.)
class TapGuard {
  TapGuard({this.syncWindow = const Duration(milliseconds: 400)});

  final Duration syncWindow;
  bool _busy = false;
  DateTime? _lastFired;

  /// True while an async callback is still running.
  bool get isBusy => _busy;

  /// Runs [action] unless a previous press is still being handled. Returns
  /// true if [action] was actually invoked.
  Future<bool> run(Function action) async {
    if (_busy) return false;
    final now = DateTime.now();
    final last = _lastFired;
    if (last != null && now.difference(last) < syncWindow) return false;
    _lastFired = now;
    _busy = true;
    var wasAsync = false;
    try {
      // `action` is typed `Function` on purpose: button callbacks are
      // declared `VoidCallback`, but many are `async` closures. Calling
      // through `Function` gives back the real return value so a Future can
      // be awaited.
      final Object? result = action();
      if (result is Future) {
        wasAsync = true;
        await result;
      }
    } finally {
      _busy = false;
      // An async action already blocked repeats while it ran; once it is done
      // the button is immediately usable again. Only a sync callback keeps
      // its short window.
      if (wasAsync) _lastFired = null;
    }
    return true;
  }
}
