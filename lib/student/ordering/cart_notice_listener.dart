import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cart_provider.dart';

/// Shows the one-time cart notice — "Your cart will be cleared 1 hour after
/// your last change." — the first time an item is added to an EMPTY cart.
///
/// Once per cart: later adds don't trigger it, and neither does reopening
/// the app with a saved cart. An expired cart is cleared silently; there is
/// no "your cart was cleared" message anywhere.
class CartNoticeListener extends ConsumerWidget {
  const CartNoticeListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(cartFirstAddNoticeProvider, (previous, next) {
      if (next > (previous ?? 0)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text(kCartExpiryNotice),
            behavior: SnackBarBehavior.floating,
          ));
      }
    });
    return child;
  }
}
