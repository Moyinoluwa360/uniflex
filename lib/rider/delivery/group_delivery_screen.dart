import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../jobs/food_job_screen.dart';

/// Legacy multi-stop group delivery screen. All new food deliveries go through
/// [FoodJobScreen]. This stub redirects immediately so old navigation call
/// sites still compile. Remove once all call sites are updated to FoodJobScreen.
class GroupDeliveryScreen extends ConsumerWidget {
  const GroupDeliveryScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FoodJobScreen.active(groupId: groupId),
        ),
      );
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
