import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/auth_providers.dart';
import '../../services/profile/profile_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../../widgets/progress/onboarding_progress_bar.dart';
import '../validators.dart';

/// The only school selectable today; modelled as a plain string field
/// (not an enum) on `profiles.school` so more schools can be added later
/// with just a longer list here — no schema change.
const _availableSchools = ['Redeemer\'s University'];

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

/// Step Two — shown immediately after Step One (phone OTP) succeeds, or
/// on app start if a signed-in student's profile row exists but
/// `onboarding_complete` is still false (see AuthGate). On submit this
/// creates the profile, wallet, referral code, and referral relationship
/// in one transaction (complete_student_onboarding() RPC), then
/// invalidates [currentProfileProvider] so AuthGate picks up the change
/// and swaps to StudentShell on its own — this screen never navigates
/// directly to a shell.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState
    extends ConsumerState<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _matricController = TextEditingController();
  final _referralController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();

  String _school = _availableSchools.first;
  DateTime? _dateOfBirth;
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _nicknameController.dispose();
    _fullNameController.dispose();
    _matricController.dispose();
    _referralController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 14, now.month, now.day),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_dateOfBirth == null) {
      setState(() => _errorText = 'Select your date of birth');
      return;
    }
    if (_pinController.text.trim() != _pinConfirmController.text.trim()) {
      setState(() => _errorText = 'PINs do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final referralCode = _referralController.text.trim();

    try {
      await ref
          .read(profileServiceProvider)
          .completeStudentOnboarding(
            nickname: _nicknameController.text.trim(),
            fullName: _fullNameController.text.trim(),
            matricNumber: _matricController.text.trim(),
            school: _school,
            dateOfBirth: _dateOfBirth!,
            referralCodeUsed: referralCode.isEmpty ? null : referralCode,
          );

      // Best-effort — if this fails, the checkout-time PIN gate will
      // prompt the student to set one the next time they try to confirm
      // an order (see CheckoutScreen/AroundScreen), so onboarding itself
      // never blocks on it.
      try {
        await ref
            .read(profileServiceProvider)
            .setTransactionPin(_pinController.text.trim());
      } catch (_) {}

      // AuthGate watches this provider and moves to StudentShell once it
      // sees onboarding_complete == true — no navigation call needed here.
      ref.invalidate(currentProfileProvider);
    } on ProfileException catch (e) {
      setState(() => _errorText = e.message);
    } catch (_) {
      setState(() => _errorText = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dobLabel = _dateOfBirth == null
        ? 'Date of birth'
        : _formatDate(_dateOfBirth!);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OnboardingProgressHeader(step: 2, totalSteps: 2),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Complete your\nprofile',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'So riders and vendors know who they are looking for.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (_errorText != null) ...[
                  Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _nicknameController,
                        label: 'Nickname',
                        prefixIcon: Icons.alternate_email,
                        textInputAction: TextInputAction.next,
                        validator: (v) => AuthValidators.required(
                          v,
                          fieldName: 'a nickname',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: InkWell(
                        onTap: _pickDateOfBirth,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date of birth',
                            suffixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          child: Text(dobLabel),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _fullNameController,
                  label: 'Full name',
                  hint: 'As written on your ID card',
                  prefixIcon: Icons.badge_outlined,
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      AuthValidators.required(v, fieldName: 'your full name'),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _matricController,
                  label: 'Matric number',
                  hint: 'RUN / CMP / 22 / 1234',
                  prefixIcon: Icons.badge_outlined,
                  textInputAction: TextInputAction.next,
                  validator: (v) => AuthValidators.required(
                    v,
                    fieldName: 'your matric number',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _school,
                  decoration: const InputDecoration(
                    labelText: 'Region / School',
                  ),
                  items: [
                    for (final school in _availableSchools)
                      DropdownMenuItem(value: school, child: Text(school)),
                  ],
                  onChanged: (value) =>
                      setState(() => _school = value ?? _school),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _referralController,
                  label: 'Referral code',
                  hint: 'FLEX500 (optional)',
                  prefixIcon: Icons.card_giftcard_outlined,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Transaction PIN', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'You\'ll enter this 4-digit PIN to confirm every order.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _pinController,
                        label: 'PIN',
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        validator: (v) => (v == null || v.length != 4)
                            ? 'Enter 4 digits'
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: AppTextField(
                        controller: _pinConfirmController,
                        label: 'Confirm PIN',
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        validator: (v) => (v == null || v.length != 4)
                            ? 'Enter 4 digits'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Finish setup',
                  isLoading: _isLoading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
