import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder/role_placeholder_screen.dart';

class StudentHomeScreen extends StatelessWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RolePlaceholderScreen(
      title: 'Student Home',
      message: 'Student Shell — placeholder\nOrdering flow starts in a later phase.',
      icon: Icons.restaurant_menu_outlined,
    );
  }
}
