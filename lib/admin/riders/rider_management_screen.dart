import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../services/admin_providers.dart';
import '../services/admin_service.dart';

/// Admin: add / remove / activate Rider accounts (post-testing fixes,
/// Section 7). Invite-only — there is still no public Rider signup path;
/// this just moves "seed by hand in Supabase" into an in-app action.
class RiderManagementScreen extends ConsumerWidget {
  const RiderManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ridersAsync = ref.watch(adminRidersProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Riders'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddRiderSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Rider'),
      ),
      body: ridersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load riders.',
          onRetry: () => ref.invalidate(adminRidersProvider),
        ),
        data: (riders) {
          if (riders.isEmpty) {
            return const Center(
              child: Text('No riders yet. Tap + to invite one.'),
            );
          }
          final active = riders.where((r) => r.isActive).toList();
          final inactive = riders.where((r) => !r.isActive).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              AppSpacing.xl + 72,
            ),
            children: [
              Text('Active (${active.length})',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              if (active.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text('No active riders.',
                      style: theme.textTheme.bodySmall),
                ),
              ...active.map((r) => _RiderCard(
                    rider: r,
                    onToggle: () => _toggleActive(context, ref, r),
                  )),
              if (inactive.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Removed / Inactive (${inactive.length})',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                ...inactive.map((r) => _RiderCard(
                      rider: r,
                      onToggle: () => _toggleActive(context, ref, r),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    RiderAccount rider,
  ) async {
    final makeActive = !rider.isActive;
    if (!makeActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove rider?'),
          content: Text(
            '"${rider.fullName}" will no longer be able to sign in or '
            'receive jobs. Their account and delivery history are kept — '
            'you can reactivate them any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await ref.read(adminServiceProvider).setRiderActive(rider.id, makeActive);
      ref.invalidate(adminRidersProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update rider: $e')),
        );
      }
    }
  }

  Future<void> _openAddRiderSheet(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool isSaving = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            setState(() {
              isSaving = true;
              error = null;
            });
            try {
              await ref.read(adminServiceProvider).createRider(
                    email: emailCtrl.text.trim(),
                    password: passwordCtrl.text,
                    fullName: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isEmpty
                        ? null
                        : phoneCtrl.text.trim(),
                  );
              ref.invalidate(adminRidersProvider);
              if (ctx.mounted) Navigator.of(ctx).pop();
            } catch (e) {
              setState(() {
                isSaving = false;
                error = e is AdminException ? e.message : 'Could not create rider.';
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.screenGutter,
              right: AppSpacing.screenGutter,
              top: AppSpacing.lg,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invite a Rider',
                        style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Set them a temporary password and share it with '
                      'them directly — there is no public sign-up for '
                      'riders.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (error != null) ...[
                      Text(error!,
                          style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    AppTextField(
                      controller: nameCtrl,
                      label: 'Full name',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: emailCtrl,
                      label: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: phoneCtrl,
                      label: 'Phone (optional)',
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: passwordCtrl,
                      label: 'Temporary password',
                      obscureText: true,
                      validator: (v) => (v == null || v.length < 8)
                          ? 'At least 8 characters'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'Create Rider Account',
                        icon: Icons.person_add_outlined,
                      isLoading: isSaving,
                      onPressed: submit,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.rider, required this.onToggle});

  final RiderAccount rider;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: rider.isActive
                  ? AppColors.emerald.withValues(alpha: 0.15)
                  : theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.two_wheeler_outlined,
                color: rider.isActive
                    ? AppColors.emerald
                    : theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rider.fullName, style: theme.textTheme.labelLarge),
                  Text(
                    rider.phone ?? rider.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (rider.isActive)
                    Text(
                      rider.isOnline ? 'Online now' : 'Offline',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: rider.isOnline
                            ? AppColors.emerald
                            : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: onToggle,
              style: OutlinedButton.styleFrom(
                foregroundColor: rider.isActive ? AppColors.error : AppColors.emerald,
                side: BorderSide(
                  color: rider.isActive ? AppColors.error : AppColors.emerald,
                ),
              ),
              child: Text(rider.isActive ? 'Remove' : 'Reactivate'),
            ),
          ],
        ),
      ),
    );
  }
}
