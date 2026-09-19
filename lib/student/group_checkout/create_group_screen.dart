import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../services/student_providers.dart';
import 'group_checkout_screen.dart';

/// Creates a group order session and shows the shareable group ID to
/// send to friends. Friends join by entering the ID in their own app.
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key, required this.vendor});

  final Vendor vendor;

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  bool _isCreating = false;
  String? _groupId;

  Future<void> _create() async {
    setState(() => _isCreating = true);
    try {
      final id = await ref
          .read(studentServiceProvider)
          .createGroupOrder(vendorId: widget.vendor.id);
      setState(() => _groupId = id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Group Order')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: _groupId == null
            ? _buildCreateView(theme)
            : _buildShareView(theme),
      ),
    );
  }

  Widget _buildCreateView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.emerald.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border:
                Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const Icon(Icons.group_add, color: AppColors.emerald, size: 40),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Start a group order',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Everyone orders from ${widget.vendor.name} and pays their own share.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('How it works', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        ..._steps.map(
          (step) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${_steps.indexOf(step) + 1}',
                      style: const TextStyle(
                        color: AppColors.pureWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(step, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isCreating ? null : _create,
            child: _isCreating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.pureWhite),
                  )
                : const Text('Create Group'),
          ),
        ),
      ],
    );
  }

  Widget _buildShareView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: AppColors.emerald, size: 56),
              const SizedBox(height: AppSpacing.md),
              Text('Group created!', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Share this code so friends can join.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _groupId!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _groupId!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Group ID copied to clipboard')),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.shopping_cart_outlined),
            label: const Text('Start Adding Items'),
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => GroupCheckoutScreen(
                  vendor: widget.vendor,
                  groupId: _groupId!,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const _steps = [
    'You create the group and share the code.',
    'Friends join with the same code.',
    'Each person picks their own items.',
    'Everyone pays their own share from their wallet.',
    'Orders are placed under a single group — one delivery.',
  ];
}
