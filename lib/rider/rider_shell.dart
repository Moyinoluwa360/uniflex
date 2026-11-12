import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/services/notifications/notification_service.dart';
import '../shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'dashboard/rider_dashboard_screen.dart';
import 'history/delivery_history_screen.dart';
import 'jobs/errand_job_screen.dart';
import 'jobs/food_job_screen.dart';
import 'pool/job_pool_screen.dart';
import 'profile/rider_profile_screen.dart';

/// Root of the Rider experience. Owns its own navigation stack — no
/// screen here ever imports from lib/student/ or lib/admin/.
///
/// Also opens the right place when a push is tapped:
///   `new_job`                → Jobs tab (the pool)
///   `customer_paid`          → that job's screen
///   `cancelled_by_*`         → Home (the job is gone)
class RiderShell extends ConsumerStatefulWidget {
  const RiderShell({super.key});

  @override
  ConsumerState<RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends ConsumerState<RiderShell> {
  static const _homeTab = 0;
  static const _jobsTab = 1;

  @override
  void initState() {
    super.initState();
    NotificationService.pendingNavigation.addListener(_onPendingNavigation);
    // A tap that launched the app (cold start) was stored before this
    // shell existed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingNavigation());
  }

  @override
  void dispose() {
    NotificationService.pendingNavigation.removeListener(_onPendingNavigation);
    super.dispose();
  }

  void _onPendingNavigation() {
    if (!mounted) return;
    final nav = NotificationService.consumePendingNavigation();
    if (nav == null) return;

    String? s(String key) {
      final v = nav[key]?.toString();
      return (v == null || v.isEmpty) ? null : v;
    }

    final type = s('type');
    final groupId = s('group_id');
    final orderId = s('order_id');

    switch (type) {
      case 'new_job':
        _goTab(_jobsTab);
      case 'customer_paid':
        if (groupId != null) {
          _push(FoodJobScreen.active(groupId: groupId));
        } else if (orderId != null) {
          _push(ErrandJobScreen.active(orderId: orderId));
        } else {
          _goTab(_homeTab);
        }
      case 'cancelled_by_customer':
      case 'cancelled_by_admin':
        _goTab(_homeTab);
      default:
        break;
    }
  }

  void _goTab(int index) {
    // Close anything pushed on top so the tab is actually visible.
    Navigator.of(context).popUntil((route) => route.isFirst);
    ref.read(shellTabRequestProvider.notifier).state = index;
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return const AppBottomNavShell(
      tabs: [
        AppNavTab(
          label: 'Home',
          icon: Icons.two_wheeler_outlined,
          selectedIcon: Icons.two_wheeler,
          screen: RiderDashboardScreen(),
        ),
        AppNavTab(
          label: 'Jobs',
          icon: Icons.inbox_outlined,
          selectedIcon: Icons.inbox,
          screen: JobPoolScreen(),
        ),
        AppNavTab(
          label: 'History',
          icon: Icons.history_outlined,
          selectedIcon: Icons.history,
          screen: DeliveryHistoryScreen(),
        ),
        AppNavTab(
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          screen: RiderProfileScreen(),
        ),
      ],
    );
  }
}
