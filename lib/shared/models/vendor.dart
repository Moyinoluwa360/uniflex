/// A vendor row from the `vendors` table.
/// Uniflex is the primary vendor (isFeatured true, badgeLabel 'Major');
/// all other rows are partner vendors.
class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    required this.description,
    required this.isFeatured,
    required this.isActive,
    this.badgeLabel,
    this.imageUrl,
    this.location,
    this.contact,
    this.packPrice = 200,
    this.campusDeliveryFee = 200,
    this.hostelDeliveryFee = 300,
  });

  factory Vendor.fromMap(Map<String, dynamic> map) {
    return Vendor(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      isFeatured: map['is_featured'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
      badgeLabel: map['badge_label'] as String?,
      imageUrl: map['image_url'] as String?,
      location: map['location'] as String?,
      contact: map['contact'] as String?,
      packPrice: (map['pack_price'] as num?)?.toDouble() ?? 200,
      campusDeliveryFee:
          (map['campus_delivery_fee'] as num?)?.toDouble() ?? 200,
      hostelDeliveryFee:
          (map['hostel_delivery_fee'] as num?)?.toDouble() ?? 300,
    );
  }

  final String id;
  final String name;
  final String description;
  final bool isFeatured;
  final bool isActive;
  final String? badgeLabel;
  final String? imageUrl;

  /// Physical location of the vendor (e.g. "Block A, Ground Floor"). Added
  /// in Phase 4 for partner vendor management. May be null for legacy rows.
  final String? location;

  /// Contact details for the vendor (phone number, WhatsApp, etc.). Added
  /// in Phase 4. May be null.
  final String? contact;

  /// Post-testing fixes, Section 11: price of one pack (₦) for this
  /// vendor's pack-requiring items. Set per vendor — Uniflex and each
  /// partner vendor can each have their own.
  final double packPrice;

  /// Delivery fees (₦) for this vendor. These used to be hardcoded in the
  /// checkout screen, which meant admin could not change them and the
  /// server had no way to validate an order total against them.
  final double campusDeliveryFee;
  final double hostelDeliveryFee;

  /// Fee for a given `delivery_type`, mirroring `_delivery_fee()` in
  /// supabase/phase9_security_hardening.sql. The server recomputes this
  /// independently and rejects a mismatched total, so the two must agree.
  double deliveryFeeFor(String deliveryType) => switch (deliveryType) {
        'campus_delivery' => campusDeliveryFee,
        'hostel_delivery' => hostelDeliveryFee,
        'delivery' => campusDeliveryFee,
        _ => 0,
      };

  /// True for the primary Uniflex vendor — used to render its home card
  /// differently from partner vendor cards.
  bool get isUniflex => isFeatured && badgeLabel == 'Major';
}
