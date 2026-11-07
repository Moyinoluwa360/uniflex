import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_providers.dart';

/// Re-runs [refresh] shortly after the underlying orders change.
///
/// Admin already streams delivery groups, errand orders and the pickup
/// (kitchen) queue over Realtime; any change in those means a number on the
/// dashboard / analytics may have moved. We wait a moment (events arrive in
/// bursts) and then refetch the figures from the database function — the
/// figures themselves are never computed on the phone.
///
/// Call [listenForOrderChanges] from `build`.
mixin StatsLiveRefresh<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Timer? _liveTimer;

  /// Debounce before refetching after a change (overridable for tests).
  Duration get liveDebounce => const Duration(milliseconds: 800);

  void listenForOrderChanges(void Function() refresh) {
    void onEvent(AsyncValue<Object?>? previous, AsyncValue<Object?> next) {
      // The first snapshot is just "what is there now" — we already have it.
      if (previous?.hasValue != true) return;
      _liveTimer?.cancel();
      _liveTimer = Timer(liveDebounce, () {
        if (mounted) refresh();
      });
    }

    ref.listen<AsyncValue<Object?>>(adminDeliveryGroupsProvider, onEvent);
    ref.listen<AsyncValue<Object?>>(adminErrandOrdersProvider, onEvent);
    ref.listen<AsyncValue<Object?>>(kitchenOrdersProvider, onEvent);
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }
}
