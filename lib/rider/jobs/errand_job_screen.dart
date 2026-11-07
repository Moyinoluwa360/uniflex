import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/app_error_mapper.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/rider_providers.dart';
import '../services/rider_service.dart';
import 'delivery_complete_screen.dart';
import 'rider_job.dart';
import '../../shared/widgets/inputs/app_text_field.dart';

class ErrandJobScreen extends ConsumerStatefulWidget {
  /// Open in preview mode (from the pool — errand not yet accepted).
  ErrandJobScreen.fromPool({super.key, required RiderJob job})
      : orderId = job.id,
        previewJob = job,
        isPreview = true;

  /// Open as an active errand (already accepted by this rider).
  const ErrandJobScreen.active({super.key, required this.orderId})
      : previewJob = null,
        isPreview = false;

  final String orderId;
  final RiderJob? previewJob;
  final bool isPreview;

  @override
  ConsumerState<ErrandJobScreen> createState() => _ErrandJobScreenState();
}

class _ErrandJobScreenState extends ConsumerState<ErrandJobScreen> {
  bool _isAccepting = false;

  Future<void> _accept() async {
    setState(() => _isAccepting = true);
    try {
      await ref.read(riderServiceProvider).acceptOrder(widget.orderId);
      ref.invalidate(riderStatsProvider);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ErrandJobScreen.active(orderId: widget.orderId),
          ),
        );
      }
    } catch (e) {
      debugPrint('[ErrandJob] accept failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMapper.map(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  Future<void> _showDeliveryPinSheet() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => _ErrandDeliveryPinSheet(orderId: widget.orderId),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DeliveryCompleteScreen(jobId: widget.orderId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPreview) return _buildPreview(context);
    return _buildActive(context);
  }

  Widget _buildPreview(BuildContext context) {
    final job = widget.previewJob!;
    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Job Details',
        actions: [_ErrandBadgeChip()],
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
                _ErrandDetailCard(job: job),
                const SizedBox(height: AppSpacing.md),
                _InfoCard(
                  icon: Icons.location_on_outlined,
                  label: 'Drop-off',
                  value: job.deliveryLocation ?? '—',
                ),
              ],
            ),
          ),
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
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentViolet,
                ),
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

  Widget _buildActive(BuildContext context) {
    final theme = Theme.of(context);
    final jobsAsync = ref.watch(riderActiveJobsProvider);
    final customerAsync = ref.watch(errandCustomerProvider(widget.orderId));

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Active Errand',
        actions: [_ErrandBadgeChip()],
      ),
      body: jobsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          debugPrint('[ErrandJob] load error: $e');
          return RetrySection(
            message: 'Could not load errand details.',
            onRetry: () => ref.invalidate(riderActiveJobsProvider),
          );
        },
        data: (jobs) {
          final matches = jobs.where((j) => j.id == widget.orderId);
          if (matches.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenGutter),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('This errand is no longer active.',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.lg),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Go back'),
                    ),
                  ],
                ),
              ),
            );
          }
          final job = matches.first;
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
                    _ErrandStatusStepper(
                        outForDelivery: job.status == 'out_for_delivery'),
                    const SizedBox(height: AppSpacing.lg),
                    _InfoCard(
                      icon: Icons.tag,
                      label: 'Order ID',
                      value: job.shortId,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    customerAsync.when(
                      loading: () => const _DetailShimmer(),
                      error: (e, _) => RetrySection(
                        message: 'Could not load customer info.',
                        compact: true,
                        onRetry: () => ref
                            .invalidate(errandCustomerProvider(widget.orderId)),
                      ),
                      data: (c) => _ActiveCustomerCard(customer: c),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ErrandDetailCard(job: job),
                    const SizedBox(height: AppSpacing.md),
                    _InfoCard(
                      icon: Icons.location_on_outlined,
                      label: 'Drop-off',
                      value: job.deliveryLocation ?? '—',
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.sm,
                  AppSpacing.screenGutter,
                  AppSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  border: Border(top: BorderSide(color: theme.dividerColor)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: AppSpacing.controlHeight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentViolet,
                    ),
                    onPressed: _showDeliveryPinSheet,
                    child: const Text('Enter Delivery PIN'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── ERRAND badge chip ─────────────────────────────────────────────────────────

class _ErrandBadgeChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.accentViolet.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          'ERRAND',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.accentViolet,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Status stepper (2 steps) ──────────────────────────────────────────────────

class _ErrandStatusStepper extends StatelessWidget {
  const _ErrandStatusStepper({required this.outForDelivery});

  final bool outForDelivery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = ['Accepted', 'Completed'];
    final current = outForDelivery ? 1 : 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentViolet.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border:
            Border.all(color: AppColors.accentViolet.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final stepIndex = i ~/ 2;
            final isActive = stepIndex < current;
            return Expanded(
              child: Container(
                height: 2,
                color: isActive
                    ? AppColors.accentViolet
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
                      ? AppColors.accentViolet
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
              Text(
                steps[stepIndex],
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isDone || isCurrent
                      ? AppColors.accentViolet
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
                  fontSize: 10,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ── Errand detail card (from the rider-safe job payload; no fees) ────────────

class _ErrandDetailCard extends StatelessWidget {
  const _ErrandDetailCard({required this.job});

  final RiderJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = job.category ?? 'Errand';
    final description = job.itemDescription ?? '—';
    final pickup = job.pickupLocation;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accentViolet.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              category,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.accentViolet,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(description, style: theme.textTheme.bodyMedium),
          if (pickup != null && pickup.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.store_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pickup',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      Text(pickup, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Active customer card ──────────────────────────────────────────────────────

class _ActiveCustomerCard extends StatelessWidget {
  const _ActiveCustomerCard({required this.customer});

  final ErrandCustomer customer;

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
    final phone = customer.phone ?? '';

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
                  size: 16, color: AppColors.accentViolet),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Customer',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.accentViolet,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (customer.name != null)
            Text(
              customer.name!,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: AppSpacing.sm),
          if (phone.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _callPhone(context, phone),
                    icon: const Icon(Icons.phone_outlined, size: 16),
                    label: const Text('Call'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openWhatsApp(context, phone),
                    icon: const Icon(Icons.chat_outlined, size: 16),
                    label: const Text('WhatsApp'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF25D366),
                      side:
                          const BorderSide(color: Color(0xFF25D366), width: 1),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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

// ── Shimmer placeholder ───────────────────────────────────────────────────────

class _DetailShimmer extends StatelessWidget {
  const _DetailShimmer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
    );
  }
}

// ── Delivery PIN bottom sheet (errand) ────────────────────────────────────────

class _ErrandDeliveryPinSheet extends ConsumerStatefulWidget {
  const _ErrandDeliveryPinSheet({required this.orderId});

  final String orderId;

  @override
  ConsumerState<_ErrandDeliveryPinSheet> createState() =>
      _ErrandDeliveryPinSheetState();
}

class _ErrandDeliveryPinSheetState
    extends ConsumerState<_ErrandDeliveryPinSheet> {
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
        const SnackBar(content: Text('Please enter a 4-character PIN.')),
      );
      return;
    }

    setState(() => _isConfirming = true);
    try {
      await ref.read(riderServiceProvider).verifyDelivery(widget.orderId, pin);
      ref.invalidate(riderStatsProvider);
      if (mounted) Navigator.of(context).pop(true); // job screen shows summary
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
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
                  selection: TextSelection.collapsed(offset: upper.length),
                );
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.controlHeight,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentViolet,
              ),
              onPressed: _isConfirming ? null : _confirm,
              child: _isConfirming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.pureWhite),
                    )
                  : const Text('Confirm delivery'),
            ),
          ),
        ],
      ),
    );
  }
}
