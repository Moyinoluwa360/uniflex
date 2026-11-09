import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/models/vendor.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/cart/summary_row.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/pin/pin_entry_sheet.dart';
import '../ordering/cart_provider.dart';
import '../ordering/order_confirmation_screen.dart';
import '../services/student_providers.dart';
import '../../shared/widgets/inputs/app_text_field.dart';

/// Join an existing group order by ID.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final _controller = TextEditingController();
  bool _isJoining = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final id = _controller.text.trim();
    if (id.isEmpty) return;
    setState(() => _isJoining = true);
    try {
      await ref.read(studentServiceProvider).joinGroupOrder(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Joined! Browse the vendor\'s menu to add your items.'),
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        final raw = e.toString();
        final msg = raw.contains('GROUP_NOT_FOUND')
            ? 'Group not found. Check the code.'
            : raw.contains('GROUP_CLOSED')
                ? 'This group is no longer accepting members.'
                : 'Could not join: $e';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Join Group Order'),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the group code shared by your friend:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _controller,
              hint: 'Paste group ID here',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _join(),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Join Group',
              isLoading: _isJoining,
              onPressed: _isJoining ? null : _join,
            ),
          ],
        ),
      ),
    );
  }
}

/// Group checkout — the current student adds cart items and checks out
/// as one member of the given group order session.
class GroupCheckoutScreen extends ConsumerStatefulWidget {
  const GroupCheckoutScreen({
    super.key,
    required this.vendor,
    required this.groupId,
  });

  final Vendor vendor;
  final String groupId;

  @override
  ConsumerState<GroupCheckoutScreen> createState() =>
      _GroupCheckoutScreenState();
}

class _GroupCheckoutScreenState extends ConsumerState<GroupCheckoutScreen> {
  bool _isCheckingOut = false;

  /// Prompts for the transaction PIN, offering to set one first if this
  /// account has none. Returns null if the student backs out.
  Future<String?> _collectPin() async {
    final hasPin = await ref.read(profileServiceProvider).hasTransactionPin();
    if (!mounted) return null;
    if (!hasPin) {
      final didSet = await showSetPinSheet(context, ref);
      if (!mounted || !didSet) return null;
    }
    return showEnterPinSheet(context);
  }

  Future<void> _checkout() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some items first.')),
      );
      return;
    }

    // Group checkout spends the wallet, so it goes through the same
    // transaction-PIN gate as an ordinary order.
    final pin = await _collectPin();
    if (pin == null || !mounted) return;

    setState(() => _isCheckingOut = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final service = ref.read(studentServiceProvider);

      final lineItems = cart.items
          .map((item) => {
                'product_id': item.product.id,
                'product_name': item.product.name,
                'quantity': item.quantity,
                'unit_price': item.unitTotal,
                'selected_options':
                    item.selectedOptions.map((o) => o.toJson()).toList(),
              })
          .toList();

      final orderId = await service.checkoutGroupOrder(
        groupId: widget.groupId,
        lineItems: lineItems,
        myTotal: cart.subtotal,
        pin: pin,
      );

      ref.read(cartProvider.notifier).clear();

      if (!mounted) return;

      final raw = await client
          .from('orders')
          .select('*, vendors(name)')
          .eq('id', orderId)
          .single();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderConfirmationScreen(order: Order.fromMap(raw)),
        ),
      );
    } catch (e) {
      if (mounted) {
        final raw = e.toString();
        final msg = raw.contains('INSUFFICIENT_BALANCE')
            ? 'Insufficient wallet balance.'
            : raw.contains('ALREADY_CHECKED_OUT')
                ? 'You already checked out of this group.'
                : 'Checkout failed: $e';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final cart = ref.watch(cartProvider);
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));

    return Scaffold(
      appBar: UniflexAppBar(title: 'Group: ${widget.vendor.name}'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Members status ─────────────────────────────────────────
            Text('Members', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            membersAsync.when(
              loading: () => const SizedBox(
                  height: 40,
                  child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const SizedBox.shrink(),
              data: (members) => Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: List.generate(members.length, (i) {
                  final paid = members[i]['paid'] as bool? ?? false;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: paid ? c.brand : c.border),
                    ),
                    child: Text(
                      paid ? 'Member ${i + 1} ✓' : 'Member ${i + 1}',
                      style: AppTypography.caption(c).copyWith(
                        color: paid ? c.brandText : c.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Cart ───────────────────────────────────────────────────
            Text('Your items', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),

            if (cart.isEmpty)
              Text(
                'No items yet — go back to the menu to add items.',
                style: AppTypography.meta(c),
              )
            else ...[
              AppCard(
                child: Column(
                  children: [
                    ...cart.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          children: [
                            Text('${item.quantity}×',
                                style: AppTypography.tabular(
                                    AppTypography.meta(c))),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                                child: Text(item.product.name,
                                    style: theme.textTheme.bodyMedium)),
                            Text(Money.format(item.lineTotal),
                                style: AppTypography.tabular(
                                    theme.textTheme.labelMedium!)),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: AppSpacing.lg, color: c.border),
                    SummaryRow(
                      label: 'Your total',
                      value: Money.format(cart.subtotal),
                      bold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Pay My Share  ${Money.format(cart.subtotal)}',
                isLoading: _isCheckingOut,
                onPressed: _isCheckingOut ? null : _checkout,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
