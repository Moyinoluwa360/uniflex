import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/order.dart';
import '../shared/services/notifications/notification_service.dart';
import '../shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'home/student_home_screen.dart';
import 'ordering/order_repository.dart';
import 'orders/orders_screen.dart';
import 'profile/student_profile_screen.dart';
import 'wallet/wallet_screen.dart';

/// Root of the Student experience. Phase 2 adds Orders and Wallet tabs.
/// No screen in here should import from lib/rider/ or lib/admin/.
///
/// Post-testing fixes, Section 12: also watches [studentOrdersProvider]
/// (now a live Supabase Realtime stream) for status changes and surfaces
/// a local notification the moment one is seen — e.g. Kitchen marking an
/// order Ready — without waiting on an FCM push round-trip. This only
/// fires while the app is open; background push still depends on FCM
/// being fully configured (see Phase 6 notes).
class StudentShell extends ConsumerWidget {
  const StudentShell({super.key});

  String? _statusChangeMessage(Order order) {
    return switch (order.status) {
      OrderStatus.readyForPickup =>
        'Your order ${order.shortId} is ready for pickup.',
      OrderStatus.ready when order.isForDelivery =>
        'Your order ${order.shortId} is ready and will be handed to a rider soon.',
      OrderStatus.outForDelivery =>
        'Your order ${order.shortId} is out for delivery.',
      OrderStatus.completed => 'Your order ${order.shortId} is complete.',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<List<Order>>>(studentOrdersProvider,
        (previous, next) {
      final prevOrders = previous?.valueOrNull;
      final nextOrders = next.valueOrNull;
      if (prevOrders == null || nextOrders == null) return;
      final prevById = {for (final o in prevOrders) o.id: o};
      for (final order in nextOrders) {
        final prev = prevById[order.id];
        if (prev == null) continue;

        if (prev.status != order.status) {
          final message = _statusChangeMessage(order);
          if (message != null) {
            NotificationService.showLocal('Order update', message);
          }
        } else if (prev.deliveryStage != order.deliveryStage &&
            order.deliveryStage == 'picked_up') {
          NotificationService.showLocal(
            'Order update',
            'Your order ${order.shortId} has been picked up by your rider.',
          );
        }
      }
    });

    return const AppBottomNavShell(
      tabs: [
        AppNavTab(
          label: 'Home',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          screen: StudentHomeScreen(),
        ),
        AppNavTab(
          label: 'Orders',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          screen: OrdersScreen(),
        ),
        AppNavTab(
          label: 'Wallet',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet,
          screen: WalletScreen(),
        ),
        AppNavTab(
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          screen: StudentProfileScreen(),
        ),
      ],
    );
  }
}
