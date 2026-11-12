import 'package:flutter/material.dart';

import '../../shared/models/vendor.dart';
import '../menu/vendor_menu_manager.dart';

/// A partner vendor's menu. Since Pack 4C this is the same
/// [VendorMenuManager] Uniflex's own menu uses (sections, per-section Add,
/// availability, pack price) — only the vendor differs.
class VendorProductsScreen extends StatelessWidget {
  const VendorProductsScreen({super.key, required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) => VendorMenuManager(
        vendorId: vendor.id,
        title: '${vendor.name} — Menu',
        fixedMenu: vendor.isFixedMenu,
      );
}
