import 'product.dart';

/// A selected option that the user chose during meal customisation,
/// stored both on [CartItem] (in-memory) and serialised into
/// `order_items.selected_options` (jsonb) when the order is placed.
class SelectedOption {
  const SelectedOption({
    required this.group,
    required this.name,
    required this.priceDelta,
  });

  factory SelectedOption.fromJson(Map<String, dynamic> json) {
    return SelectedOption(
      group: json['group'] as String,
      name: json['name'] as String,
      priceDelta: (json['price_delta'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 'protein' | 'extra'
  final String group;
  final String name;
  final double priceDelta;

  Map<String, dynamic> toJson() => {
        'group': group,
        'name': name,
        'price_delta': priceDelta,
      };
}

/// One line in the in-memory cart — a [Product] plus the user's quantity
/// and any selected options (protein, extras). Immutable; quantities are
/// updated by replacing the item via [copyWith].
class CartItem {
  const CartItem({
    required this.product,
    required this.quantity,
    this.selectedOptions = const [],
  });

  final Product product;
  final int quantity;
  final List<SelectedOption> selectedOptions;

  /// Unit price = base price + the sum of all option deltas.
  double get unitTotal {
    return product.basePrice +
        selectedOptions.fold(0.0, (sum, o) => sum + o.priceDelta);
  }

  double get lineTotal => unitTotal * quantity;

  /// Human-readable summary of selected options, e.g. "Chicken, Coleslaw".
  String get optionsSummary {
    if (selectedOptions.isEmpty) return '';
    return selectedOptions.map((o) => o.name).join(', ');
  }

  CartItem copyWith({int? quantity}) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
      selectedOptions: selectedOptions,
    );
  }
}
