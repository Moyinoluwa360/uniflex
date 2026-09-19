import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/cart_item.dart';
import '../../shared/models/vendor.dart';

/// The in-memory shopping cart. The cart is scoped to a single vendor —
/// adding items from a different vendor requires clearing first (the UI
/// prompts the user before doing so).
class CartState {
  const CartState({
    this.items = const [],
    this.vendor,
  });

  final List<CartItem> items;

  /// The vendor this cart belongs to. Null when the cart is empty.
  final Vendor? vendor;

  bool get isEmpty => items.isEmpty;

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      items.fold(0.0, (sum, item) => sum + item.lineTotal);

  CartState copyWith({List<CartItem>? items, Vendor? vendor}) {
    return CartState(
      items: items ?? this.items,
      vendor: vendor ?? this.vendor,
    );
  }

  CartState withVendor(Vendor vendor) =>
      CartState(items: items, vendor: vendor);
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  /// Adds [item] to the cart, scoped to [vendor].
  /// If an identical product+options combo already exists, increments
  /// its quantity instead of adding a duplicate line.
  void addItem(CartItem item, Vendor vendor) {
    final items = [...state.items];
    final idx = items.indexWhere(
      (ci) =>
          ci.product.id == item.product.id &&
          _optionsMatch(ci.selectedOptions, item.selectedOptions),
    );

    if (idx >= 0) {
      items[idx] = items[idx].copyWith(
        quantity: items[idx].quantity + item.quantity,
      );
    } else {
      items.add(item);
    }

    state = CartState(items: items, vendor: vendor);
  }

  void removeAt(int index) {
    final items = [...state.items]..removeAt(index);
    state = CartState(
      items: items,
      vendor: items.isEmpty ? null : state.vendor,
    );
  }

  void updateQuantity(int index, int quantity) {
    if (quantity <= 0) {
      removeAt(index);
      return;
    }
    final items = [...state.items];
    items[index] = items[index].copyWith(quantity: quantity);
    state = state.copyWith(items: items);
  }

  void clear() => state = const CartState();

  bool _optionsMatch(
    List<SelectedOption> a,
    List<SelectedOption> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].group != b[i].group || a[i].name != b[i].name) return false;
    }
    return true;
  }
}

final cartProvider =
    NotifierProvider<CartNotifier, CartState>(CartNotifier.new);
