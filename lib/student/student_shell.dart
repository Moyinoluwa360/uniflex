import 'package:flutter/material.dart';

import '../shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'home/student_home_screen.dart';
import 'profile/student_profile_screen.dart';

/// Root of the Student experience. Owns its own navigation stack — no
/// screen in here should ever import from lib/rider/ or lib/admin/.
/// Add new Student-only screens as new files under lib/student/, and wire
/// new top-level tabs into the `tabs` list below.
class StudentShell extends StatelessWidget {
  const StudentShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppBottomNavShell(
      tabs: [
        AppNavTab(
          label: 'Home',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          screen: StudentHomeScreen(),
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
