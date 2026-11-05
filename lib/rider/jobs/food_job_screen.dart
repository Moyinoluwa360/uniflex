import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/app_error_mapper.dart';
import '../../shared/widgets/accordions/app_accordion_card.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../pool/pool_group.dart';
import '../services/rider_providers.dart';
import '../services/rider_service.dart';

class FoodJobScreen extends ConsumerStatefulWidget {
  /// Open in preview mode (from pool — group not yet accepted).
  FoodJobScreen.fromPool({super.key, required this.poolGroup})
      : groupId = poolGroup.group.id,
        isPreview = true;

  /// Open as active job (group already accepted by this rider).
  const FoodJobScreen.active({super.key, required this.groupId})
      : poolGroup = null,
        isPreview = false;

  final String groupId;
  final PoolGroup? poolGroup;
  final bool isPreview;

  @override
  ConsumerState<FoodJobScreen> createState() => _FoodJobScreenState();
}

class _FoodJobScreenState extends ConsumerState<FoodJobScreen> {
  bool _isAccepting = false;

  // Track which accordion is expanded (vendor index).
  int? _expandedVendorIndex;

  @override
  void initState() {
    super.initState();
    if (!widget.isPreview) {
      // Listen for terminal state and auto-pop.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkTerminalState();
      });
    }
  }

  void _checkTerminalState() {
    final group = ref.read(groupDetailProvider(widget.groupId)).valueOrNull;
    if (group != null && group.isTerminal) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _accept() async {
    setState(() => _isAccepting = true);
    try {
      await ref
          .read(riderServiceProvider)
          .acceptDeliveryGroup(widget.groupId);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => FoodJobScreen.active(groupId: widget.groupId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMapper.map(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  Future<void> _showEnterPriceSheet({bool isCorrection = false}) async {
    final customerAsync =
        ref.read(groupCustomerInfoProvider(widget.groupId));
    final customerName =
        customerAsync.valueOrNull?.displayName ?? 'the customer';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => _EnterPriceSheet(
        groupId: widget.groupId,
        customerName: customerName,
        isCorrection: isCorrection,
      ),
    );
  }

  Future<void> _showDeliveryPinSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => _DeliveryPinSheet(groupId: widget.groupId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(groupItemsProvider(widget.groupId));

    if (!widget.isPreview) {
      final groupAsync = ref.watch(groupDetailProvider(widget.groupId));

      // Auto-pop on terminal state.
      groupAsync.whenData((group) {
        if (group != null && group.isTerminal) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }
      });

      final customerAsync =
          ref.watch(groupCustomerInfoProvider(widget.groupId));

      return Scaffold(
        appBar: UniflexAppBar(
          title: 'Active Job',
          actions: [_FoodBadgeChip()],
        ),
        body: groupAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => RetrySection(
            message: 'Could not load job details.',
            onRetry: () {
              ref.invalidate(groupDetailProvider(widget.groupId));
            },
          ),
          data: (g) {
            if (g == null) {
              return const Center(child: CircularProgressIndicator());
            }

            // Cancelled by student.
            if (g.status == DeliveryGroupStatus.cancelled &&
                g.cancelledByStudent) {
              return _CancelledByStudentView(
                onBack: () => Navigator.of(context).pop(),
              );
            }

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      AppSpacing.md,
                      AppSpacing.screenGutter,
                      AppSpacing.xl,
                    ),
                    children: [
                      // Status stepper.
                      _StatusStepper(status: g.status),
                      const SizedBox(height: AppSpacing.lg),

                      // Customer card.
                      customerAsync.when(
                        loading: () => const _CustomerCardShimmer(),
                        error: (e, _) => RetrySection(
                          message: 'Could not load customer info.',
                          compact: true,
                          onRetry: () => ref.invalidate(
                              groupCustomerInfoProvider(widget.groupId)),
                        ),
                        data: (info) => _CustomerCard(info: info),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Vendor breakdown.
                      _buildVendorSection(theme, itemsAsync),
                      const SizedBox(height: AppSpacing.md),

                      // Drop-off location.
                      _InfoCard(
                        icon: Icons.location_on_outlined,
                        label: 'Drop-off',
                        value: g.deliveryLocation ?? '—',
                      ),

                      // Student note.
                      if (g.studentNote != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _InfoCard(
                          icon: Icons.sticky_note_2_outlined,
                          label: 'Note from customer',
                          value: g.studentNote!,
                        ),
                      ],
                    ],
                  ),
                ),
                _BottomActionBar(
                  status: g.status,
                  onEnterPrice: () => _showEnterPriceSheet(),
                  onCorrectPrice: () =>
                      _showEnterPriceSheet(isCorrection: true),
                  onEnterPin: _showDeliveryPinSheet,
                ),
              ],
            );
          },
        ),
      );
    }

    // ── Preview mode (from pool) ──────────────────────────────────────
    final poolGroup = widget.poolGroup!;
    final group = poolGroup.group;

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Job Details',
        actions: [_FoodBadgeChip()],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.md,
                AppSpacing.screenGutter,
                AppSpacing.xl,
              ),
              children: [
                // Vendor breakdown.
                _buildVendorSection(theme, itemsAsync),
                const SizedBox(height: AppSpacing.md),

                // Drop-off location.
                _InfoCard(
                  icon: Icons.location_on_outlined,
                  label: 'Drop-off',
                  value: group.deliveryLocation ?? '—',
                ),

                // Student note.
                if (group.studentNote != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Note',
                    value: group.studentNote!,
                  ),
                ],

                const SizedBox(height: AppSpacing.lg),

                // Total section.
                _TotalSection(poolGroup: poolGroup),
              ],
            ),
          ),

          // Accept button.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.lg,
            ),
            child: SizedBox(
              width: double.infinity,
              height: AppSpacing.controlHeight,
              child: FilledButton(
                onPressed: _isAccepting ? null : _accept,
                child: _isAccepting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.pureWhite,
                        ),
                      )
                    : const Text('Accept Job'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorSection(
      ThemeData theme, AsyncValue<List<GroupVendorItems>> itemsAsync) {
    return itemsAsync.when(
      loading: () => const _VendorShimmer(),
      error: (e, _) => RetrySection(
        message: 'Could not load item details.',
        onRetry: () => ref.invalidate(groupItemsProvider(widget.groupId)),
      ),
      data: (vendors) {
        if (vendors.isEmpty) {
          return const SizedBox.shrink();
        }

        // Single vendor: flat list.
        if (vendors.length == 1) {
          return _VendorItemsBlock(
            vendor: vendors.first,
            isFlat: true,
          );
        }

        // Multiple vendors: accordions (all closed initially).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vendors (${vendors.length})',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...List.generate(vendors.length, (i) {
              final vendor = vendors[i];
              final isExpanded = _expandedVendorIndex == i;
              final totalItems = vendor.items.length +
                  vendor.packs.fold<int>(
                      0, (sum, p) => sum + p.items.length);
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppAccordionCard(
                  leading: buildAccordionLeadingIcon(
                    context: context,
                    icon: Icons.storefront_outlined,
                    color: AppColors.emerald,
                  ),
                  title: vendor.vendorName,
                  subtitle: vendor.vendorLocation ??
                      '$totalItems item${totalItems == 1 ? '' : 's'}',
                  isExpanded: isExpanded,
                  onTap: () => setState(() {
                    _expandedVendorIndex = isExpanded ? null : i;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm),
                    child: _VendorItemsContent(vendor: vendor),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ── FOOD badge chip ───────────────────────────────────────────────────────────

class _FoodBadgeChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.emerald.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          'FOOD',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.emerald,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Status stepper ────────────────────────────────────────────────────────────

class _StatusStepper extends StatelessWidget {
  const _StatusStepper({required this.status});

  final DeliveryGroupStatus status;

  static const _steps = [
    'Accepted',
    'Price Sent',
    'Awaiting Payment',
    'Out for Delivery',
  ];

  int get _currentStep => switch (status) {
        DeliveryGroupStatus.riderAccepted => 0,
        DeliveryGroupStatus.awaitingFinalPayment => 1,
        DeliveryGroupStatus.outForDelivery => 3,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _currentStep;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
            color: AppColors.emerald.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line.
            final stepIndex = i ~/ 2;
            final isActive = stepIndex < current;
            return Expanded(
              child: Container(
                height: 2,
                color: isActive
                    ? AppColors.emerald
                    : theme.colorScheme.outline.withValues(alpha: 0.2),
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final isDone = stepIndex < current;
          final isCurrent = stepIndex == current;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone || isCurrent
                      ? AppColors.emerald
                      : theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check,
                          size: 14, color: AppColors.pureWhite)
                      : isCurrent
                          ? const SizedBox(
                              width: 8,
                              height: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.pureWhite,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 60,
                child: Text(
                  _steps[stepIndex],
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isDone || isCurrent
                        ? AppColors.emerald
                        : theme.colorScheme.onSurface
                            .withValues(alpha: 0.4),
                    fontWeight:
                        isCurrent ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ── Customer card ─────────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.info});

  final GroupCustomerInfo info;

  void _callPhone(BuildContext context, String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open phone app.')),
        );
      }
    }
  }

  void _openWhatsApp(BuildContext context, String phone) async {
    final formatted = phone.replaceFirst(RegExp(r'^0'), '234');
    final uri = Uri.parse('https://wa.me/$formatted');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open WhatsApp.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 16, color: AppColors.emerald),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Customer',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.emerald,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            info.fullName,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (info.nickname != null) ...[
            const SizedBox(height: 2),
            Text(
              '@${info.nickname}',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
          if (info.email != null) ...[
            const SizedBox(height: 2),
            Text(
              info.email!,
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
          if (info.locationDetails != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 14,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    info.locationDetails!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _callPhone(context, info.phone),
                  icon: const Icon(Icons.phone_outlined, size: 16),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openWhatsApp(context, info.phone),
                  icon: const Icon(Icons.chat_outlined, size: 16),
                  label: const Text('WhatsApp'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(
                        color: Color(0xFF25D366), width: 1),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerCardShimmer extends StatelessWidget {
  const _CustomerCardShimmer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
      ),
    );
  }
}

// ── Vendor items block ────────────────────────────────────────────────────────

class _VendorItemsBlock extends StatelessWidget {
  const _VendorItemsBlock({
    required this.vendor,
    this.isFlat = false,
  });

  final GroupVendorItems vendor;
  final bool isFlat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isFlat) ...[
            Row(
              children: [
                const Icon(Icons.storefront_outlined,
                    size: 16, color: AppColors.emerald),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    vendor.vendorName,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (vendor.vendorLocation != null) ...[
              const SizedBox(height: 2),
              Padding(
                padding:
                    const EdgeInsets.only(left: AppSpacing.md + 8),
                child: Text(
                  vendor.vendorLocation!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          _VendorItemsContent(vendor: vendor),
        ],
      ),
    );
  }
}

class _VendorItemsContent extends StatelessWidget {
  const _VendorItemsContent({required this.vendor});

  final GroupVendorItems vendor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = <Widget>[];

    // Packs.
    for (final pack in vendor.packs) {
      sections.add(_SectionHeader(label: pack.label));
      for (final item in pack.items) {
        sections.add(_ItemRow(
          name: item.productName,
          qty: item.quantity,
          price: null,
        ));
      }
    }

    // Food items (not in a pack).
    final foodItems = vendor.foodItems;
    if (foodItems.isNotEmpty) {
      if (vendor.packs.isEmpty) {
        sections.add(_SectionHeader(label: 'Items'));
      }
      for (final item in foodItems) {
        sections.add(_ItemRow(
          name: item.productName,
          qty: item.quantity,
          price: item.unitPrice,
        ));
      }
    }

    // Drinks.
    final drinkItems = vendor.drinkItems;
    if (drinkItems.isNotEmpty) {
      sections.add(_SectionHeader(label: 'Drinks'));
      for (final item in drinkItems) {
        sections.add(_ItemRow(
          name: item.productName,
          qty: item.quantity,
          price: item.unitPrice,
        ));
      }
    }

    // Others.
    final otherItems = vendor.otherItems;
    if (otherItems.isNotEmpty) {
      sections.add(_SectionHeader(label: 'Others'));
      for (final item in otherItems) {
        sections.add(_ItemRow(
          name: item.productName,
          qty: item.quantity,
          price: item.unitPrice,
        ));
      }
    }

    if (sections.isEmpty) {
      return Text(
        'No items',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
          top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color:
              theme.colorScheme.onSurface.withValues(alpha: 0.6),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.name,
    required this.qty,
    this.price,
  });

  final String name;
  final int qty;
  final double? price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                '$qty',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.emerald,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (price != null)
            Text(
              '₦${price!.toStringAsFixed(0)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );
  }
}

class _VendorShimmer extends StatelessWidget {
  const _VendorShimmer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Info card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 18,
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Total section (preview only) ──────────────────────────────────────────────

class _TotalSection extends ConsumerWidget {
  const _TotalSection({required this.poolGroup});

  final PoolGroup poolGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final group = poolGroup.group;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border:
            Border.all(color: AppColors.emerald.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Totals',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Pack fee',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.6),
                  )),
              Text(
                '₦${group.commitmentFeeTotal.toStringAsFixed(0)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          if (group.finalAmount != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Items total',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    )),
                Text(
                  '₦${group.finalAmount!.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                group.finalAmount != null
                    ? '₦${(group.commitmentFeeTotal + group.finalAmount!).toStringAsFixed(0)}'
                    : 'TBD after sourcing',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.emerald,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Bottom action bar (active job) ────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.status,
    required this.onEnterPrice,
    required this.onCorrectPrice,
    required this.onEnterPin,
  });

  final DeliveryGroupStatus status;
  final VoidCallback onEnterPrice;
  final VoidCallback onCorrectPrice;
  final VoidCallback onEnterPin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: switch (status) {
        DeliveryGroupStatus.riderAccepted => SizedBox(
            width: double.infinity,
            height: AppSpacing.controlHeight,
            child: FilledButton(
              onPressed: onEnterPrice,
              child: const Text('Enter Final Price'),
            ),
          ),
        DeliveryGroupStatus.awaitingFinalPayment => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_empty,
                        color: AppColors.warning, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Waiting for customer payment...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: onCorrectPrice,
                child: const Text('Correct Price'),
              ),
            ],
          ),
        DeliveryGroupStatus.outForDelivery => SizedBox(
            width: double.infinity,
            height: AppSpacing.controlHeight,
            child: FilledButton(
              onPressed: onEnterPin,
              child: const Text('Enter Delivery PIN'),
            ),
          ),
        DeliveryGroupStatus.completed => Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline,
                    color: AppColors.emerald),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Delivery completed',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        DeliveryGroupStatus.cancelled => Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cancel_outlined,
                    color: AppColors.error),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Order cancelled',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

// ── Cancelled by student view ─────────────────────────────────────────────────

class _CancelledByStudentView extends StatelessWidget {
  const _CancelledByStudentView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cancel_outlined,
                  color: AppColors.error, size: 36),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Cancelled by customer',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This order was declined after you sent the final price.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: onBack,
              child: const Text('Back to jobs'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Enter Price bottom sheet ──────────────────────────────────────────────────

class _EnterPriceSheet extends ConsumerStatefulWidget {
  const _EnterPriceSheet({
    required this.groupId,
    required this.customerName,
    this.isCorrection = false,
  });

  final String groupId;
  final String customerName;
  final bool isCorrection;

  @override
  ConsumerState<_EnterPriceSheet> createState() => _EnterPriceSheetState();
}

class _EnterPriceSheetState extends ConsumerState<_EnterPriceSheet> {
  final _controller = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final amountText = _controller.text.trim();
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount.')),
      );
      return;
    }

    if (amount > 500000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Amount cannot exceed ₦500,000.')),
      );
      return;
    }

    // Confirmation dialog.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm price'),
        content: Text(
          'Send ₦${amount.toStringAsFixed(0)} to ${widget.customerName}?\n\nThey will be asked to pay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSending = true);
    try {
      await ref
          .read(riderServiceProvider)
          .setGroupFinalPrice(widget.groupId, amount);
      ref.invalidate(groupDetailProvider(widget.groupId));
      ref.invalidate(groupCustomerInfoProvider(widget.groupId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMapper.map(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenGutter,
        right: AppSpacing.screenGutter,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isCorrection ? 'Correct price' : 'Enter final price',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Enter the total amount you paid across all vendors.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(
              prefixText: '₦ ',
              hintText: '0',
              counterText: '',
            ),
            style: theme.textTheme.headlineMedium,
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.controlHeight,
            child: FilledButton(
              onPressed: _isSending ? null : _send,
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.pureWhite),
                    )
                  : const Text('Send to customer'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Delivery PIN bottom sheet ─────────────────────────────────────────────────

class _DeliveryPinSheet extends ConsumerStatefulWidget {
  const _DeliveryPinSheet({required this.groupId});

  final String groupId;

  @override
  ConsumerState<_DeliveryPinSheet> createState() =>
      _DeliveryPinSheetState();
}

class _DeliveryPinSheetState extends ConsumerState<_DeliveryPinSheet> {
  final _controller = TextEditingController();
  bool _isConfirming = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final pin = _controller.text.trim().toUpperCase();
    if (pin.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a 4-character PIN.')),
      );
      return;
    }

    setState(() => _isConfirming = true);
    try {
      await ref
          .read(riderServiceProvider)
          .verifyGroupDelivery(widget.groupId, pin);
      ref.invalidate(riderStatsProvider);
      if (mounted) {
        Navigator.of(context).pop(); // close sheet
        Navigator.of(context).pop(); // pop job screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMapper.map(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenGutter,
        right: AppSpacing.screenGutter,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Delivery PIN',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Ask the customer for their 4-digit PIN.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            maxLength: 4,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: '- - - -',
              counterText: '',
            ),
            style: theme.textTheme.displaySmall?.copyWith(
              letterSpacing: 12,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
            autofocus: true,
            onChanged: (v) {
              final upper = v.toUpperCase();
              if (upper != v) {
                _controller.value = _controller.value.copyWith(
                  text: upper,
                  selection:
                      TextSelection.collapsed(offset: upper.length),
                );
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.controlHeight,
            child: FilledButton(
              onPressed: _isConfirming ? null : _confirm,
              child: _isConfirming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.pureWhite),
                    )
                  : const Text('Confirm delivery'),
            ),
          ),
        ],
      ),
    );
  }
}
