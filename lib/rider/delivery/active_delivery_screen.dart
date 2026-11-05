import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../jobs/food_job_screen.dart';

/// Legacy single-order delivery screen. All new food deliveries go through
/// [FoodJobScreen]. This stub redirects immediately so old navigation call
/// sites still compile. Remove once all call sites are updated to FoodJobScreen.
class ActiveDeliveryScreen extends ConsumerWidget {
  const ActiveDeliveryScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Immediately redirect to the new unified food job screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FoodJobScreen.active(groupId: orderId),
        ),
      );
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
