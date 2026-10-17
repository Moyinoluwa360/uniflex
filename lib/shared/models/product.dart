/// A menu item from the `products` table. Post-testing fixes, Section
/// 11: every product is its own independently orderable catalog item —
/// there is no more protein/extras option bundling (the old
/// `product_options` table and combo-builder wizard are retired from the
/// ordering flow; former protein choices are now standalone products,
/// e.g. "Chicken" under a "Proteins" category).
class Product {
  const Product({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.description,
    required this.category,
    required this.basePrice,
    this.imageUrl,
    this.isAvailable = true,
    this.requiresPack = false,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      category: map['category'] as String,
      basePrice: (map['base_price'] as num).toDouble(),
      imageUrl: map['image_url'] as String?,
      isAvailable: map['is_available'] as bool? ?? true,
      requiresPack: map['requires_pack'] as bool? ?? false,
    );
  }

  final String id;
  final String vendorId;
  final String name;
  final String description;
  final String category;
  final double basePrice;
  final String? imageUrl;
  final bool isAvailable;

  /// Post-testing fixes, Section 11: true when this item needs to be
  /// packaged into a container to be handed over (most food); false for
  /// items that never do (drinks, etc.). Admin-editable per product.
  final bool requiresPack;

  Map<String, dynamic> toMap() => {
        'id': id,
        'vendor_id': vendorId,
        'name': name,
        'description': description,
        'category': category,
        'base_price': basePrice,
        'image_url': imageUrl,
        'is_available': isAvailable,
        'requires_pack': requiresPack,
      };
}
