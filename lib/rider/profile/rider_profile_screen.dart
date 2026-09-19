import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/auth/auth_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/buttons/primary_button.dart';

class RiderProfileScreen extends ConsumerWidget {
  const RiderProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (profile) {
          final initials = _initials(profile?.fullName);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            children: [
              // ── Avatar ───────────────────────────────────────────────
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: AppColors.pureWhite,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Name ─────────────────────────────────────────────────
              Center(
                child: Text(
                  profile?.fullName ?? '—',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'Rider',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── Info rows ────────────────────────────────────────────
              _InfoRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value: profile?.email ?? '—',
              ),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: profile?.phone ?? '—',
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── Logout ───────────────────────────────────────────────
              PrimaryButton(
                label: 'Log Out',
                onPressed: () => ref.read(authServiceProvider).signOut(),
              ),

              const SizedBox(height: AppSpacing.lg),
            ],
          );
        },
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: AppSpacing.md),
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
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
