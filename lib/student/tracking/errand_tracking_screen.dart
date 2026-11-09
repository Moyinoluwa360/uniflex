import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/status/app_status_label.dart';
import '../../shared/widgets/status/status_presentation.dart';
import '../../shared/widgets/text/app_section_label.dart';
import '../../shared/widgets/tracking/pin_digit_boxes.dart';
import '../../shared/widgets/tracking/tracking_stepper.dart';
import '../ordering/order_repository.dart';

/// Simplified tracking screen for errand orders.
///
/// Shows a basic status timeline (placed → rider assigned → on the way → done),
/// rider name with Call and WhatsApp buttons once a rider is assigned,
/// and the delivery PIN. No sourcing, adjust-order, or final-payment steps.
class ErrandTrackingScreen extends ConsumerWidget {
  const ErrandTrackingScreen({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final liveAsync = ref.watch(orderByIdProvider(order.id));

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Track Errand ${order.shortId}',
        actions: [
          IconButton(
            icon: const Icon(AppIcons.refresh),
            onPressed: () => ref.invalidate(orderByIdProvider(order.id)),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: liveAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load this errand.',
          onRetry: () => ref.invalidate(orderByIdProvider(order.id)),
        ),
        data: (liveOrder) {
          final o = liveOrder ?? order;
          final status = StatusPresenter.order(o.status, isErrand: true);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header card ─────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.shortId, style: AppTypography.title(c)),
                        const SizedBox(height: 2),
                        Text('Errand request', style: AppTypography.meta(c)),
                        const SizedBox(height: AppSpacing.sm),
                        AppStatusLabel(
                            tone: status.tone, text: _errandLabel(o.status)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── Timeline ────────────────────────────────────────────
                const AppSectionLabel('Progress'),
                const SizedBox(height: AppSpacing.md),
                _ErrandTimeline(status: o.status),

                const SizedBox(height: AppSpacing.xl),

                // ── Rider contact (once assigned) ────────────────────────
                if (o.riderId != null) ...[
                  const AppSectionLabel('Your rider'),
                  const SizedBox(height: AppSpacing.sm),
                  Consumer(
                    builder: (ctx, cref, _) {
                      final riderInfoAsync =
                          cref.watch(orderRiderInfoProvider(o.id));
                      final info = riderInfoAsync.valueOrNull;
                      if (info == null) return const SizedBox.shrink();

                      final name = info['full_name'] as String?;
                      final phone = info['phone'] as String?;

                      return SizedBox(
                        width: double.infinity,
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(AppIcons.rider,
                                      size: 20, color: c.textSecondary),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    name ?? 'Assigned',
                                    style: AppTypography.body(c)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              if (phone != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Row(
                                  children: [
                                    Expanded(
                                      child: AppButton(
                                        icon: AppIcons.phone,
                                        label: 'Call',
                                        variant: AppButtonVariant.secondary,
                                        size: AppButtonSize.small,
                                        onPressed: () async {
                                          final uri = Uri.parse('tel:$phone');
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(uri);
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: AppButton(
                                        icon: AppIcons.chat,
                                        label: 'WhatsApp',
                                        variant: AppButtonVariant.secondary,
                                        size: AppButtonSize.small,
                                        onPressed: () async {
                                          final normalized = phone.replaceAll(
                                              RegExp(r'[^\d]'), '');
                                          final uri = Uri.parse(
                                              'https://wa.me/$normalized');
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(
                                              uri,
                                              mode: LaunchMode
                                                  .externalApplication,
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // ── Delivery PIN ─────────────────────────────────────────
                if (o.deliveryPin != null && !o.status.isTerminal) ...[
                  const AppSectionLabel('Delivery PIN'),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: AppCard(
                      child: Column(
                        children: [
                          PinDigitBoxes(pin: o.deliveryPin!),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Show this to your rider to confirm delivery.',
                            style: AppTypography.meta(c),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // ── Fee ─────────────────────────────────────────────────
                const AppSectionLabel('Fee'),
                const SizedBox(height: 4),
                Text(
                  Money.format(o.totalAmount),
                  style: AppTypography.tabular(AppTypography.title(c)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Errand-specific status labels.
  String _errandLabel(OrderStatus s) => switch (s) {
        OrderStatus.placed => 'Errand placed',
        OrderStatus.beingSourced => 'Rider assigned',
        OrderStatus.outForDelivery => 'On the way',
        OrderStatus.completed => 'Done',
        OrderStatus.cancelled => 'Cancelled',
        _ => s.label,
      };
}

/// Four-step errand timeline:
/// Placed → Rider Assigned → On the Way → Done.
class _ErrandTimeline extends StatelessWidget {
  const _ErrandTimeline({required this.status});

  final OrderStatus status;

  static const _steps = [
    (status: OrderStatus.placed, label: 'Errand placed'),
    (status: OrderStatus.beingSourced, label: 'Rider assigned'),
    (status: OrderStatus.outForDelivery, label: 'On the way'),
    (status: OrderStatus.completed, label: 'Done'),
  ];

  int _currentIndex() => switch (status) {
        OrderStatus.placed => 0,
        OrderStatus.beingSourced => 1,
        OrderStatus.outForDelivery => 2,
        OrderStatus.completed => 3,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final currentIdx = _currentIndex();
    return TrackingStepper(
      labels: [for (final s in _steps) s.label],
      states: [
        for (var i = 0; i < _steps.length; i++)
          i > currentIdx
              ? TrackingStepState.upcoming
              : (i == currentIdx && status != OrderStatus.completed)
                  ? TrackingStepState.current
                  : TrackingStepState.done,
      ],
    );
  }
}
