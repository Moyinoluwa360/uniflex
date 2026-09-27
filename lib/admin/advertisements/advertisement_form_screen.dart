import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/models/advertisement.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../shared/widgets/media/app_image.dart';
import '../services/admin_providers.dart';

/// Create or edit a home-page advertisement.
class AdvertisementFormScreen extends ConsumerStatefulWidget {
  const AdvertisementFormScreen({super.key, this.existing});

  final Advertisement? existing;

  @override
  ConsumerState<AdvertisementFormScreen> createState() =>
      _AdvertisementFormScreenState();
}

class _AdvertisementFormScreenState
    extends ConsumerState<AdvertisementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _orderCtrl;

  late bool _isDark;
  late bool _isActive;
  late AdLinkType _linkType;
  String? _vendorId;
  String? _imageUrl;
  Uint8List? _pickedBytes;
  String? _pickedFileName;
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _isSaving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ad = widget.existing;
    _titleCtrl = TextEditingController(text: ad?.title ?? '');
    _subtitleCtrl = TextEditingController(text: ad?.subtitle ?? '');
    _orderCtrl = TextEditingController(text: '${ad?.sortOrder ?? 0}');
    _isDark = ad?.isDark ?? false;
    _isActive = ad?.isActive ?? true;
    _linkType = ad?.linkType ?? AdLinkType.none;
    _imageUrl = ad?.imageUrl;
    _startsAt = ad?.startsAt;
    _endsAt = ad?.endsAt;
    _vendorId = ad?.linkType == AdLinkType.vendor ? ad?.linkValue : null;
    _urlCtrl = TextEditingController(
      text: ad?.linkType == AdLinkType.url ? (ad?.linkValue ?? '') : '',
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _urlCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pickedBytes = bytes;
      _pickedFileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startsAt : _endsAt) ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startsAt = date;
      } else {
        // Run to the end of the chosen day rather than midnight, so "ends
        // 5 Oct" includes the 5th.
        _endsAt = DateTime(date.year, date.month, date.day, 23, 59);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_linkType == AdLinkType.vendor && _vendorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick the vendor this ad opens.')),
      );
      return;
    }
    if (_startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The end date must be after the start.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = ref.read(adminServiceProvider);

      var imageUrl = _imageUrl;
      if (_pickedBytes != null && _pickedFileName != null) {
        imageUrl = await service.uploadAdImage(_pickedBytes!, _pickedFileName!);
      }

      await service.upsertAdvertisement(
        id: widget.existing?.id,
        title: _titleCtrl.text.trim(),
        subtitle: _subtitleCtrl.text.trim(),
        isDark: _isDark,
        isActive: _isActive,
        sortOrder: int.tryParse(_orderCtrl.text.trim()) ?? 0,
        imageUrl: imageUrl,
        linkType: _linkType,
        linkValue: switch (_linkType) {
          AdLinkType.vendor => _vendorId,
          AdLinkType.url => _urlCtrl.text.trim(),
          _ => null,
        },
        startsAt: _startsAt,
        endsAt: _endsAt,
      );

      ref.invalidate(adminAdvertisementsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vendorsAsync = ref.watch(allVendorsProvider);

    return Scaffold(
      appBar: UniflexAppBar(title: _isEdit ? 'Edit Ad' : 'New Ad'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Live preview ──────────────────────────────────────────
              Text('Preview', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 128,
                child: _AdPreview(
                  title: _titleCtrl.text.trim().isEmpty
                      ? 'Your headline'
                      : _titleCtrl.text.trim(),
                  subtitle: _subtitleCtrl.text.trim(),
                  dark: _isDark,
                  bytes: _pickedBytes,
                  imageUrl: _imageUrl,
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _titleCtrl,
                label: 'Title',
                hint: 'e.g. Free delivery over ₦5,000',
                onChanged: (_) => setState(() {}),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _subtitleCtrl,
                label: 'Subtitle',
                hint: 'e.g. Uniflex Kitchen · ends Sunday',
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: AppSpacing.lg),
              Text('Image (optional)', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      _pickedBytes != null || _imageUrl != null
                          ? 'Change image'
                          : 'Choose image',
                    ),
                  ),
                  if (_pickedBytes != null || _imageUrl != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: () => setState(() {
                        _pickedBytes = null;
                        _pickedFileName = null;
                        _imageUrl = null;
                      }),
                      child: const Text('Remove'),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: AppSpacing.lg),
              Text('Style', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Orange')),
                  ButtonSegment(value: true, label: Text('Dark')),
                ],
                selected: {_isDark},
                onSelectionChanged: (s) => setState(() => _isDark = s.first),
              ),
              const SizedBox(height: 4),
              Text(
                'Used when there is no image, and as the scrim colour when '
                'there is one.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              Text('Tapping the ad', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<AdLinkType>(
                initialValue: _linkType,
                items: const [
                  DropdownMenuItem(
                      value: AdLinkType.none, child: Text('Does nothing')),
                  DropdownMenuItem(
                      value: AdLinkType.vendor, child: Text('Opens a vendor')),
                  DropdownMenuItem(
                      value: AdLinkType.wallet,
                      child: Text('Opens the wallet')),
                  DropdownMenuItem(
                      value: AdLinkType.url,
                      child: Text('Opens a web link')),
                ],
                onChanged: (v) =>
                    setState(() => _linkType = v ?? AdLinkType.none),
              ),

              if (_linkType == AdLinkType.vendor) ...[
                const SizedBox(height: AppSpacing.md),
                vendorsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Could not load vendors.'),
                  data: (vendors) => DropdownButtonFormField<String>(
                    initialValue: _vendorId,
                    hint: const Text('Choose a vendor'),
                    items: vendors
                        .map((v) => DropdownMenuItem(
                              value: v.id,
                              child: Text(v.name),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _vendorId = v),
                  ),
                ),
              ],

              if (_linkType == AdLinkType.url) ...[
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _urlCtrl,
                  label: 'Link',
                  hint: 'https://…',
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return 'Enter a link';
                    final uri = Uri.tryParse(value);
                    if (uri == null || !uri.hasScheme) {
                      return 'Include https://';
                    }
                    return null;
                  },
                ),
              ],

              const SizedBox(height: AppSpacing.lg),
              Text('Schedule (optional)', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Starts',
                      value: _startsAt,
                      onPick: () => _pickDate(isStart: true),
                      onClear: () => setState(() => _startsAt = null),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _DateField(
                      label: 'Ends',
                      value: _endsAt,
                      onPick: () => _pickDate(isStart: false),
                      onClear: () => setState(() => _endsAt = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Leave blank to run immediately and indefinitely.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _orderCtrl,
                      label: 'Display order',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Active', style: theme.textTheme.labelMedium),
                      Switch(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeThumbColor: AppColors.emerald,
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: _isEdit ? 'Save changes' : 'Create ad',
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

/// Mirrors the student-facing promo card closely enough that admin can see
/// what they are shipping before they ship it.
class _AdPreview extends StatelessWidget {
  const _AdPreview({
    required this.title,
    required this.subtitle,
    required this.dark,
    this.bytes,
    this.imageUrl,
  });

  final String title;
  final String subtitle;
  final bool dark;
  final Uint8List? bytes;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = dark ? AppColors.matteBlack : AppColors.orange;
    final hasImage = bytes != null || (imageUrl != null && imageUrl!.isNotEmpty);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: ColoredBox(
        color: base,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes!, fit: BoxFit.cover)
            else if (imageUrl != null && imageUrl!.isNotEmpty)
              AppImage(url: imageUrl, fit: BoxFit.cover),
            if (hasImage)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColors.matteBlack.withValues(alpha: 0.72),
                      AppColors.matteBlack.withValues(alpha: 0.15),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: AppColors.pureWhite),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.pureWhite.withValues(alpha: 0.85),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelSmall),
                  Text(
                    value == null
                        ? 'Any time'
                        : '${value!.day}/${value!.month}/${value!.year}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (value != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: onClear,
              )
            else
              const Icon(Icons.calendar_today_outlined, size: 16),
          ],
        ),
      ),
    );
  }
}
