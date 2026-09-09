import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder/role_placeholder_screen.dart';

class RiderHomeScreen extends StatelessWidget {
  const RiderHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RolePlaceholderScreen(
      title: 'Rider Home',
      message: 'Rider Shell — placeholder\nDelivery job queue starts in a later phase.',
      icon: Icons.two_wheeler_outlined,
    );
  }
}
