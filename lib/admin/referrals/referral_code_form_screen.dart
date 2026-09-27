import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../services/admin_providers.dart';
import '../services/admin_service.dart';

/// Mint a new referral code, or re-allocate an existing one.
///
/// A code can be held either by a student (who then earns the ₦500 referral
/// bonus) or by someone with no account — a promoter, an orientation stand —
/// in which case signups are still counted but nobody is paid.
class ReferralCodeFormScreen extends ConsumerStatefulWidget {
  const ReferralCodeFormScreen({super.key, this.existing});

  final ReferralCodeRow? existing;

  @override
  ConsumerState<ReferralCodeFormScreen> createState() =>
      _ReferralCodeFormScreenState();
}

enum _OwnerKind { student, external, none }

class _ReferralCodeFormScreenState
    extends ConsumerState<ReferralCodeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _labelController;
  late final TextEditingController _noteController;
  final _searchController = TextEditingController();

  late _OwnerKind _ownerKind;
  StudentPick? _selectedStudent;
  String? _existingOwnerName;
  bool _isSaving = false;
  bool _isSearching = false;
  List<StudentPick> _results = const [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _codeController = TextEditingController(text: existing?.code ?? '');
    _labelController = TextEditingController(text: existing?.ownerLabel ?? '');
    _noteController = TextEditingController(text: existing?.note ?? '');
    _existingOwnerName = existing?.ownerName;
    _ownerKind = existing == null
        ? _OwnerKind.student
        : existing.ownerId != null
            ? _OwnerKind.student
            : (existing.ownerLabel != null && existing.ownerLabel!.isNotEmpty)
                ? _OwnerKind.external
                : _OwnerKind.none;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _labelController.dispose();
    _noteController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _isSearching = true);
    try {
      final results =
          await ref.read(adminServiceProvider).searchStudents(query);
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // A student-held code needs an actual student. On edit the still-attached
    // owner counts — but if it was cleared in the UI, demand a new pick
    // rather than silently keeping the one they just removed.
    if (_ownerKind == _OwnerKind.student &&
        _selectedStudent == null &&
        _existingOwnerName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick the student this code belongs to.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final service = ref.read(adminServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    final ownerId = switch (_ownerKind) {
      // Only fall back to the existing owner while it is still shown as
      // attached — see the guard above.
      _OwnerKind.student => _selectedStudent?.id ??
          (_existingOwnerName != null ? widget.existing?.ownerId : null),
      _ => null,
    };
    final ownerLabel = switch (_ownerKind) {
      _OwnerKind.external => _labelController.text.trim(),
      _ => null,
    };

    try {
      if (_isEdit) {
        await service.updateReferralCode(
          codeId: widget.existing!.id,
          ownerId: ownerId,
          ownerLabel: ownerLabel,
          note: _noteController.text.trim(),
          isActive: widget.existing!.isActive,
        );
      } else {
        await service.createReferralCode(
          code: _codeController.text.trim().toUpperCase(),
          ownerId: ownerId,
          ownerLabel: ownerLabel,
          note: _noteController.text.trim(),
        );
      }
      ref.invalidate(adminReferralCodesProvider);
      if (mounted) Navigator.of(context).pop();
    } on AdminException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: UniflexAppBar(
        title: _isEdit ? 'Edit Code' : 'New Referral Code',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Code', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _codeController,
                hint: 'e.g. RUNFEST',
                enabled: !_isEdit,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                  LengthLimitingTextInputFormatter(16),
                  // Codes are stored uppercase, so normalise as it is typed
                  // rather than surprising admin on save.
                  TextInputFormatter.withFunction(
                    (_, next) => next.copyWith(text: next.text.toUpperCase()),
                  ),
                ],
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (_isEdit) return null;
                  if (value.length < 4) return 'At least 4 characters';
                  return null;
                },
              ),
              if (_isEdit) ...[
                const SizedBox(height: 4),
                Text(
                  'The code itself cannot be changed once people may already '
                  'be sharing it — make a new one instead.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),
              Text('Allocate to', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<_OwnerKind>(
                segments: const [
                  ButtonSegment(
                    value: _OwnerKind.student,
                    label: Text('Student'),
                    icon: Icon(Icons.person_outline),
                  ),
                  ButtonSegment(
                    value: _OwnerKind.external,
                    label: Text('Other'),
                    icon: Icon(Icons.campaign_outlined),
                  ),
                  ButtonSegment(
                    value: _OwnerKind.none,
                    label: Text('Nobody'),
                    icon: Icon(Icons.block_outlined),
                  ),
                ],
                selected: {_ownerKind},
                onSelectionChanged: (s) =>
                    setState(() => _ownerKind = s.first),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                switch (_ownerKind) {
                  _OwnerKind.student =>
                    'This student earns ₦500 each time someone signs up with '
                        'the code and completes a first order.',
                  _OwnerKind.external =>
                    'For a promoter or campaign with no Uniflex account. '
                        'Signups are counted, but no bonus is paid.',
                  _OwnerKind.none =>
                    'Pure attribution — track where signups came from, with '
                        'nobody attached and no bonus.',
                },
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),

              if (_ownerKind == _OwnerKind.student) ...[
                const SizedBox(height: AppSpacing.md),
                if (_selectedStudent != null)
                  _SelectedOwnerTile(
                    name: _selectedStudent!.displayName,
                    detail: _selectedStudent!.matricNumber ??
                        _selectedStudent!.email,
                    onClear: () => setState(() => _selectedStudent = null),
                  )
                else if (_existingOwnerName != null)
                  _SelectedOwnerTile(
                    name: _existingOwnerName!,
                    detail: 'Currently allocated',
                    onClear: () => setState(() => _existingOwnerName = null),
                  )
                else ...[
                  AppTextField(
                    controller: _searchController,
                    hint: 'Search by name, nickname, or matric number',
                    prefixIcon: Icons.search,
                    onChanged: (v) {
                      if (v.trim().length >= 2) _search(v);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_isSearching)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    ..._results.map(
                      (s) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(s.displayName),
                        subtitle: Text(s.matricNumber ?? s.email ?? '—'),
                        onTap: () => setState(() {
                          _selectedStudent = s;
                          _results = const [];
                          _searchController.clear();
                        }),
                      ),
                    ),
                ],
              ],

              if (_ownerKind == _OwnerKind.external) ...[
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _labelController,
                  label: 'Who holds it',
                  hint: 'e.g. Bola — Instagram',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Say who this code was given to'
                      : null,
                ),
              ],

              const SizedBox(height: AppSpacing.lg),
              Text('Note (optional)', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _noteController,
                hint: 'Anything worth remembering about this code',
                maxLines: 2,
              ),

              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: _isEdit ? 'Save changes' : 'Create code',
                icon: Icons.check,
                isLoading: _isSaving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedOwnerTile extends StatelessWidget {
  const _SelectedOwnerTile({
    required this.name,
    required this.detail,
    required this.onClear,
  });

  final String name;
  final String? detail;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: AppColors.emerald, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.labelLarge),
                if (detail != null)
                  Text(
                    detail!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Change',
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}
