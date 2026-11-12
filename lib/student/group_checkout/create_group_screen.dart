import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../services/student_providers.dart';
import 'group_checkout_screen.dart';
import '../../shared/utils/app_error_mapper.dart';

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
          SnackBar(content: Text('Could not create group. ${AppErrorMapper.map(e)}')),
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
      appBar: const UniflexAppBar(title: 'Group Order'),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child:
            _groupId == null ? _buildCreateView(theme) : _buildShareView(theme),
      ),
    );
  }

  Widget _buildCreateView(ThemeData theme) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Icon(AppIcons.group, color: c.brandText, size: 40),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Start a group order',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Everyone orders from ${widget.vendor.name} and pays their own share.',
                  style: AppTypography.meta(c),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
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
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.borderStrong),
                  ),
                  child: Center(
                    child: Text(
                      '${_steps.indexOf(step) + 1}',
                      style: AppTypography.tabular(
                        AppTypography.caption(c).copyWith(
                          color: c.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
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
        AppButton(
          label: 'Create Group',
          isLoading: _isCreating,
          onPressed: _isCreating ? null : _create,
        ),
      ],
    );
  }

  Widget _buildShareView(ThemeData theme) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              Icon(AppIcons.success, color: c.brandText, size: 56),
              const SizedBox(height: AppSpacing.md),
              Text('Group created!', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Share this code so friends can join.',
                style: AppTypography.meta(c),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
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
                  icon: Icon(AppIcons.copy, color: c.textSecondary),
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
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Start Adding Items',
          icon: AppIcons.cart,
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => GroupCheckoutScreen(
                vendor: widget.vendor,
                groupId: _groupId!,
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
