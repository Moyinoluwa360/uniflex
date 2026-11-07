import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/cart_item.dart';
import '../../shared/models/vendor.dart';

/// SharedPreferences key used to persist the cart between app restarts.
const _cartKey = 'uniflex_cart_v2';
const _legacyCartKey = 'uniflex_cart';

/// Pack contents for one vendor's food order: a list of maps where each
/// map represents one pack (productId → quantity).
typedef PackContentsData = List<Map<String, int>>;

/// Per-vendor data in the multi-vendor cart.
class VendorCartGroup {
  const VendorCartGroup({
    required this.vendor,
    this.items = const [],
    this.packCount = 0,
    this.packFee = 0,
    this.packContents = const [],
  });

  final Vendor vendor;
  final List<CartItem> items;

  /// Number of food packs (0 if no food items or if this vendor
  /// only has drinks/others).
  final int packCount;

  /// Total pack fee (packCount × vendor.packPrice).
  final double packFee;

  /// Per-pack food contents: packContents[i] = {productId: quantity}.
  final PackContentsData packContents;

  bool get isEmpty => items.isEmpty;
  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);
  double get subtotal => items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get totalWithPacks => subtotal + packFee;

  VendorCartGroup copyWith({
    List<CartItem>? items,
    int? packCount,
    double? packFee,
    PackContentsData? packContents,
  }) {
    return VendorCartGroup(
      vendor: vendor,
      items: items ?? this.items,
      packCount: packCount ?? this.packCount,
      packFee: packFee ?? this.packFee,
      packContents: packContents ?? this.packContents,
    );
  }

  Map<String, dynamic> toJson() => {
        'vendor': vendor.toMap(),
        'items': items.map((i) => i.toJson()).toList(),
        'pack_count': packCount,
        'pack_fee': packFee,
        'pack_contents':
            packContents.map((m) => m.map((k, v) => MapEntry(k, v))).toList(),
      };

  factory VendorCartGroup.fromJson(Map<String, dynamic> json) {
    return VendorCartGroup(
      vendor: Vendor.fromMap(json['vendor'] as Map<String, dynamic>),
      items: (json['items'] as List<dynamic>?)
              ?.map((i) => CartItem.fromJson(i as Map<String, dynamic>))
              .toList() ??
          const [],
      packCount: json['pack_count'] as int? ?? 0,
      packFee: (json['pack_fee'] as num?)?.toDouble() ?? 0,
      packContents: (json['pack_contents'] as List<dynamic>?)
              ?.map((m) => (m as Map<String, dynamic>)
                  .map((k, v) => MapEntry(k, (v as num).toInt())))
              .toList() ??
          const [],
    );
  }
}

/// Multi-vendor cart state. Groups items by vendor.
class CartState {
  const CartState({this.groups = const {}, this.lastModifiedAt});

  /// VendorId → VendorCartGroup
  final Map<String, VendorCartGroup> groups;

  /// When items were last added/removed/changed. Used for 1-hour expiry.
  final DateTime? lastModifiedAt;

  bool get isEmpty => groups.values.every((g) => g.isEmpty);
  int get vendorCount => groups.values.where((g) => !g.isEmpty).length;

  int get itemCount => groups.values.fold(0, (sum, g) => sum + g.itemCount);

  double get subtotal => groups.values.fold(0.0, (sum, g) => sum + g.subtotal);

  double get totalPackFee =>
      groups.values.fold(0.0, (sum, g) => sum + g.packFee);

  /// Backwards compat: single vendor if only one group.
  Vendor? get vendor {
    final nonEmpty = groups.values.where((g) => !g.isEmpty).toList();
    if (nonEmpty.length == 1) return nonEmpty.first.vendor;
    return nonEmpty.isEmpty ? null : nonEmpty.first.vendor;
  }

  /// Flat list of all items across all vendors (for display/counting).
  List<CartItem> get items => groups.values.expand((g) => g.items).toList();

  /// Whether the cart contains any partner vendor.
  bool get hasPartnerVendor =>
      groups.values.any((g) => !g.isEmpty && !g.vendor.isUniflex);

  /// Whether the cart is Uniflex-only.
  bool get isUniflexOnly =>
      groups.values.every((g) => g.isEmpty || g.vendor.isUniflex);

  CartState copyWith({
    Map<String, VendorCartGroup>? groups,
    DateTime? lastModifiedAt,
  }) {
    return CartState(
      groups: groups ?? this.groups,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'groups':
            groups.map((vendorId, group) => MapEntry(vendorId, group.toJson())),
        if (lastModifiedAt != null)
          'last_modified_at': lastModifiedAt!.toIso8601String(),
      };

  factory CartState.fromJson(Map<String, dynamic> json) {
    final rawLastMod = json['last_modified_at'] as String?;
    final lastMod = rawLastMod != null ? DateTime.tryParse(rawLastMod) : null;

    if (json['version'] == 2) {
      final rawGroups = json['groups'] as Map<String, dynamic>? ?? {};
      final groups = rawGroups.map((vendorId, g) => MapEntry(
          vendorId, VendorCartGroup.fromJson(g as Map<String, dynamic>)));
      return CartState(groups: groups, lastModifiedAt: lastMod);
    }
    // Legacy v1 format: single vendor cart.
    return _migrateLegacy(json);
  }

  /// Migrate old single-vendor cart format to multi-vendor.
  static CartState _migrateLegacy(Map<String, dynamic> json) {
    try {
      final items = (json['items'] as List<dynamic>?)
              ?.map((i) => CartItem.fromJson(i as Map<String, dynamic>))
              .toList() ??
          const [];
      if (items.isEmpty) return const CartState();

      final vendor = json['vendor'] != null
          ? Vendor.fromMap(json['vendor'] as Map<String, dynamic>)
          : null;
      if (vendor == null) return const CartState();

      return CartState(groups: {
        vendor.id: VendorCartGroup(vendor: vendor, items: items),
      });
    } catch (_) {
      return const CartState();
    }
  }
}

const _cartExpiry = Duration(hours: 1);

/// Bumped each time an item is added to an EMPTY cart (the start of a new
/// cart). The student shell listens and shows the one-time notice
/// "Your cart will be cleared 1 hour after your last change." — once per
/// cart, never on later adds, never when the app reopens with a saved cart.
final cartFirstAddNoticeProvider = StateProvider<int>((ref) => 0);

/// The notice text (kept here so the listener and tests agree on it).
const kCartExpiryNotice =
    'Your cart will be cleared 1 hour after your last change.';

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() {
    _restore();
    return const CartState();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    // Try v2 first, then legacy.
    var raw = prefs.getString(_cartKey);
    if (raw == null) {
      raw = prefs.getString(_legacyCartKey);
      if (raw != null) {
        // Migrate and clean up.
        await prefs.remove(_legacyCartKey);
      }
    }
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final loaded = CartState.fromJson(json);

      // Check 1-hour expiry. Old carts with no timestamp are treated as
      // fresh (backward-compatible).
      if (!loaded.isEmpty &&
          loaded.lastModifiedAt != null &&
          DateTime.now().difference(loaded.lastModifiedAt!) > _cartExpiry) {
        // Expired carts are cleared silently — no message, ever.
        await prefs.remove(_cartKey);
        await prefs.remove(_legacyCartKey);
        // state stays empty (default)
        return;
      }

      state = loaded;
    } catch (_) {
      await prefs.remove(_cartKey);
      await prefs.remove(_legacyCartKey);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (state.isEmpty) {
      await prefs.remove(_cartKey);
    } else {
      await prefs.setString(_cartKey, jsonEncode(state.toJson()));
    }
  }

  /// Updates [lastModifiedAt] on every cart mutation so the expiry timer
  /// resets with each change.
  void _touch() {
    state = state.copyWith(lastModifiedAt: DateTime.now());
    _persist();
  }

  /// Call this when the cart screen is opened or the app resumes.
  /// Returns true if the cart was expired and silently cleared.
  bool checkAndClearIfExpired() {
    if (state.isEmpty) return false;
    final lastMod = state.lastModifiedAt;
    if (lastMod == null) {
      return false; // no timestamp yet — never expires mid-session
    }
    if (DateTime.now().difference(lastMod) > _cartExpiry) {
      clear();
      return true;
    }
    return false;
  }

  /// Adds a non-food item (drinks, others) to the cart for [vendor].
  void addItem(CartItem item, Vendor vendor) {
    final startsNewCart = state.isEmpty;
    final groups = Map<String, VendorCartGroup>.from(state.groups);
    final group = groups[vendor.id] ?? VendorCartGroup(vendor: vendor);

    final items = [...group.items];
    final idx = items.indexWhere(
      (ci) =>
          ci.product.id == item.product.id &&
          _optionsMatch(ci.selectedOptions, item.selectedOptions),
    );

    if (idx >= 0) {
      items[idx] =
          items[idx].copyWith(quantity: items[idx].quantity + item.quantity);
    } else {
      items.add(item);
    }

    groups[vendor.id] = group.copyWith(items: items);
    state = CartState(groups: groups);
    _touch();
    if (startsNewCart) {
      ref.read(cartFirstAddNoticeProvider.notifier).state++;
    }
  }

  /// Adds a food item from the pack builder (tagged with pack index).
  void addPackItem(CartItem item, Vendor vendor, {required int packIndex}) {
    // Pack items are added as regular cart items — the pack metadata
    // is stored separately via setPackInfo.
    addItem(item, vendor);
  }

  /// Records pack metadata for a vendor after the pack builder completes.
  void setPackInfo({
    required Vendor vendor,
    required int packCount,
    required double packFee,
    required List<Map<String, int>> packContents,
  }) {
    final groups = Map<String, VendorCartGroup>.from(state.groups);
    final group = groups[vendor.id] ?? VendorCartGroup(vendor: vendor);

    groups[vendor.id] = group.copyWith(
      packCount: packCount,
      packFee: packFee,
      packContents: packContents,
    );

    state = CartState(groups: groups);
    _touch();
  }

  /// Remove an item at [index] within a specific vendor's group.
  void removeItemFromVendor(String vendorId, int index) {
    final groups = Map<String, VendorCartGroup>.from(state.groups);
    final group = groups[vendorId];
    if (group == null) return;

    final items = [...group.items]..removeAt(index);
    if (items.isEmpty) {
      groups.remove(vendorId);
    } else {
      groups[vendorId] = group.copyWith(items: items);
    }

    state = CartState(groups: groups);
    _touch();
  }

  /// Remove a whole vendor's group from the cart.
  void removeVendor(String vendorId) {
    final groups = Map<String, VendorCartGroup>.from(state.groups);
    groups.remove(vendorId);
    state = CartState(groups: groups);
    _touch();
  }

  /// Clear all food packs for a vendor (when re-entering pack builder).
  void clearFoodPacks(String vendorId) {
    final groups = Map<String, VendorCartGroup>.from(state.groups);
    final group = groups[vendorId];
    if (group == null) return;

    // Remove food items, keep drinks/others.
    final nonFoodItems =
        group.items.where((i) => i.product.section != 'food').toList();

    if (nonFoodItems.isEmpty) {
      groups.remove(vendorId);
    } else {
      groups[vendorId] = group.copyWith(
        items: nonFoodItems,
        packCount: 0,
        packFee: 0,
        packContents: [],
      );
    }

    state = CartState(groups: groups);
    _touch();
  }

  // ── Legacy compat (single-vendor API) ──────────────────────────────

  /// Remove item at flat index across all items. Used by old CartScreen.
  void removeAt(int flatIndex) {
    int offset = 0;
    for (final entry in state.groups.entries) {
      final groupLen = entry.value.items.length;
      if (flatIndex < offset + groupLen) {
        removeItemFromVendor(entry.key, flatIndex - offset);
        return;
      }
      offset += groupLen;
    }
  }

  void updateQuantity(int flatIndex, int quantity) {
    if (quantity <= 0) {
      removeAt(flatIndex);
      return;
    }
    int offset = 0;
    final groups = Map<String, VendorCartGroup>.from(state.groups);
    for (final entry in groups.entries) {
      final groupLen = entry.value.items.length;
      if (flatIndex < offset + groupLen) {
        final localIdx = flatIndex - offset;
        final items = [...entry.value.items];
        items[localIdx] = items[localIdx].copyWith(quantity: quantity);
        groups[entry.key] = entry.value.copyWith(items: items);
        state = CartState(groups: groups);
        _touch();
        return;
      }
      offset += groupLen;
    }
  }

  void clear() {
    state = const CartState();
    _persist();
  }

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
