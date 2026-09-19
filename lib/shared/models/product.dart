/// A configurable add-on for a [Product] (protein choice, extra side).
/// Stored in the `product_options` table.
class ProductOption {
  const ProductOption({
    required this.id,
    required this.productId,
    required this.group,
    required this.name,
    required this.priceDelta,
  });

  factory ProductOption.fromMap(Map<String, dynamic> map) {
    return ProductOption(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      group: map['option_group'] as String,
      name: map['name'] as String,
      priceDelta: (map['price_delta'] as num?)?.toDouble() ?? 0.0,
    );
  }

  final String id;
  final String productId;

  /// 'protein' (radio — pick one) or 'extra' (checkbox — pick many).
  final String group;
  final String name;

  /// Added to the product's base_price. May be negative (e.g. egg is
  /// cheaper than chicken).
  final double priceDelta;
}

/// A menu item from the `products` table. [options] is populated by the
/// product repository after a separate `product_options` fetch.
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
    this.options = const [],
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

  /// Protein and extra options, loaded separately by the product repository.
  final List<ProductOption> options;

  List<ProductOption> get proteinOptions =>
      options.where((o) => o.group == 'protein').toList();

  List<ProductOption> get extraOptions =>
      options.where((o) => o.group == 'extra').toList();

  bool get hasProteinOptions => proteinOptions.isNotEmpty;
  bool get hasExtraOptions => extraOptions.isNotEmpty;

  Product copyWith({List<ProductOption>? options}) {
    return Product(
      id: id,
      vendorId: vendorId,
      name: name,
      description: description,
      category: category,
      basePrice: basePrice,
      imageUrl: imageUrl,
      isAvailable: isAvailable,
      requiresPack: requiresPack,
      options: options ?? this.options,
    );
  }
}
