import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder/role_placeholder_screen.dart';

class StudentProfileScreen extends StatelessWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RolePlaceholderScreen(
      title: 'Student Profile',
      message: 'Student Shell — placeholder',
      icon: Icons.person_outline,
    );
  }
}
