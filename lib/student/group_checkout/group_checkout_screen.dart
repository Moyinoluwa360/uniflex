import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/models/vendor.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../ordering/cart_provider.dart';
import '../ordering/order_confirmation_screen.dart';
import '../services/student_providers.dart';

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
          content: Text(
              'Joined! Browse the vendor\'s menu to add your items.'),
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
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Paste group ID here',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _join(),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isJoining ? null : _join,
                child: _isJoining
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.pureWhite),
                      )
                    : const Text('Join Group'),
              ),
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

class _GroupCheckoutScreenState
    extends ConsumerState<GroupCheckoutScreen> {
  bool _isCheckingOut = false;

  Future<void> _checkout() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some items first.')),
      );
      return;
    }

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
          builder: (_) =>
              OrderConfirmationScreen(order: Order.fromMap(raw)),
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
    final cart = ref.watch(cartProvider);
    final membersAsync =
        ref.watch(groupMembersProvider(widget.groupId));

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
                  return Chip(
                    label: Text(
                      paid ? 'Member ${i + 1} ✓' : 'Member ${i + 1}',
                      style: theme.textTheme.labelSmall,
                    ),
                    backgroundColor: paid
                        ? AppColors.emerald.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
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
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: 0.5),
                ),
              )
            else ...[
              ...cart.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Text(
                        '${item.quantity}×',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                          child: Text(item.product.name,
                              style: theme.textTheme.bodyMedium)),
                      Text('₦${item.lineTotal.toStringAsFixed(0)}',
                          style: theme.textTheme.labelMedium),
                    ],
                  ),
                ),
              ),
              const Divider(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Your total', style: theme.textTheme.titleSmall),
                  Text(
                    '₦${cart.subtotal.toStringAsFixed(0)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isCheckingOut ? null : _checkout,
                  child: _isCheckingOut
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.pureWhite),
                        )
                      : Text(
                          'Pay My Share  ₦${cart.subtotal.toStringAsFixed(0)}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
