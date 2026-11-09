import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/media/app_image.dart';
import '../ordering/catalog_screen.dart';
import '../ordering/product_repository.dart';
import '../../shared/widgets/inputs/app_text_field.dart';

/// Full-screen search. Debounces input (300 ms), then calls the
/// `search_products` RPC which returns product name, price, and
/// vendor info for all active matches.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<_SearchResult> _results = [];
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
        _error = null;
      });
      return;
    }
    setState(() => _isLoading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search(query.trim());
    });
  }

  Future<void> _search(String query) async {
    try {
      final client = ref.read(supabaseClientProvider);
      final data = await client.rpc(
        'search_products',
        params: {'p_query': query},
      );

      if (!mounted) return;

      final List<dynamic> rows = data is List ? data : [];
      setState(() {
        _results = rows
            .map((r) => _SearchResult.fromJson(r as Map<String, dynamic>))
            .toList();
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Search failed. Try again.';
      });
    }
  }

  Future<void> _navigateToVendor(String vendorId) async {
    final vendors = await ref.read(vendorsProvider.future);
    final vendor = vendors.where((v) => v.id == vendorId).firstOrNull;
    if (vendor == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CatalogScreen(vendor: vendor)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Search'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: AppTextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search meals, vendors...',
                prefixIcon: const Icon(AppIcons.search),
                suffixIcon: hasQuery
                    ? IconButton(
                        icon: const Icon(AppIcons.close),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      )
                    : null,
              ),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(_error!,
                  style: AppTypography.meta(context.colors)
                      .copyWith(color: context.colors.dangerText)),
            )
          else if (hasQuery && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'No results found.',
                style: AppTypography.meta(context.colors),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final r = _results[i];
                  return ListTile(
                    leading: SizedBox(
                      width: 48,
                      height: 48,
                      child: AppImage(
                        url: r.imageUrl,
                        keywords: 'food,${r.section}',
                        seed: r.productId.hashCode,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    title: Text(r.productName),
                    subtitle: Text(
                      '${Money.format(r.basePrice)}  ·  ${r.vendorName}',
                    ),
                    onTap: () => _navigateToVendor(r.vendorId),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchResult {
  const _SearchResult({
    required this.productId,
    required this.productName,
    required this.basePrice,
    required this.section,
    required this.vendorId,
    required this.vendorName,
    this.imageUrl,
  });

  factory _SearchResult.fromJson(Map<String, dynamic> json) {
    return _SearchResult(
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      basePrice: (json['base_price'] as num).toDouble(),
      section: json['section'] as String? ?? 'food',
      vendorId: json['vendor_id'] as String,
      vendorName: json['vendor_name'] as String,
      imageUrl: json['image_url'] as String?,
    );
  }

  final String productId;
  final String productName;
  final double basePrice;
  final String section;
  final String vendorId;
  final String vendorName;
  final String? imageUrl;
}
