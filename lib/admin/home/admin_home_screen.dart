import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder/role_placeholder_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RolePlaceholderScreen(
      title: 'Admin Home',
      message:
          'Admin Shell — placeholder\nOrder, kitchen, and rider management start in a later phase.',
      icon: Icons.dashboard_outlined,
    );
  }
}
