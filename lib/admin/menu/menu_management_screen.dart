import 'package:flutter/material.dart';

import 'vendor_menu_manager.dart';

/// Uniflex's own menu — the internal Uniflex vendor
/// (`00000000-0000-0000-0000-000000000001`).
///
/// Since Pack 4C this is just [VendorMenuManager], the same screen partner
/// vendors use, so the two can never drift apart again.
class MenuManagementScreen extends StatelessWidget {
  const MenuManagementScreen({super.key});

  /// Fixed UUID seeded in Phase 2 — the Uniflex vendor ID.
  static const uniflexVendorId = '00000000-0000-0000-0000-000000000001';

  @override
  Widget build(BuildContext context) => const VendorMenuManager(
        vendorId: uniflexVendorId,
        title: 'Menu Management',
      );
}
