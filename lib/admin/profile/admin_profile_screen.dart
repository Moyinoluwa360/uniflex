import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder/role_placeholder_screen.dart';

class AdminProfileScreen extends StatelessWidget {
  const AdminProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RolePlaceholderScreen(
      title: 'Admin Profile',
      message: 'Admin Shell — placeholder',
      icon: Icons.person_outline,
    );
  }
}
