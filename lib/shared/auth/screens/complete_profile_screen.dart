import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/auth_providers.dart';
import '../../services/profile/profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/buttons/app_button.dart';
import '../../widgets/auth/app_auth_header.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/inputs/app_form_parts.dart';
import '../../widgets/inputs/app_picker_field.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../validators.dart';
import '../../widgets/notice/app_inline_notice.dart';
import '../../theme/app_icons.dart';

/// The only school selectable today; modelled as a plain string field
/// (not an enum) on `profiles.school` so more schools can be added later
/// with just a longer list here — no schema change.
const _availableSchools = ['Redeemer\'s University'];

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

/// LEGACY (pre-Pack-5 accounts only — new sign-ups use SignupFinalStep).
/// Shown on app start if a signed-in student's profile row exists but
/// `onboarding_complete` is still false (see AuthGate). On submit this
/// creates the profile, wallet, and (if a valid code was entered) the
/// referral relationship in one transaction (complete_student_onboarding()
/// RPC), then invalidates [currentProfileProvider] so AuthGate picks up
/// the change and swaps to StudentShell on its own — this screen never
/// navigates directly to a shell.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
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
  String? _pinError;

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
      setState(() => _pinError = 'PINs do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
      _pinError = null;
    });

    final referralCode = _referralController.text.trim();

    try {
      await ref.read(profileServiceProvider).completeStudentOnboarding(
            nickname: _nicknameController.text.trim(),
            fullName: _fullNameController.text.trim(),
            matricNumber: _matricController.text.trim().isEmpty
                ? null
                : _matricController.text.trim(),
            school: _school,
            dateOfBirth: _dateOfBirth!,
            referralCodeUsed: referralCode.isEmpty ? null : referralCode,
          );

      // Best-effort — if this fails, the checkout-time PIN gate will
      // prompt the student to set one the next time they try to confirm
      // an order (see CheckoutScreen/ErrandScreen), so onboarding itself
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
    final c = context.colors;

    return AppAuthScaffold(
      header: AppAuthHeader.compact(
        title: 'Complete your\nprofile',
        subtitle: 'So riders and vendors know who they are looking for.',
        onBack: () {
          // If we can pop (pushed from Step 1), do so. Otherwise
          // this is a root route (app reopened mid-onboarding) —
          // sign out so AuthGate returns to LoginScreen.
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            ref.read(authServiceProvider).signOut();
          }
        },
        step: 2,
        totalSteps: 2,
        stepLabel: '2 / 2',
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 22),
            if (_errorText != null) ...[
              AppInlineNotice(isError: true, text: _errorText!),
              const SizedBox(height: AppSpacing.md),
            ],
            AppFieldPair(
              left: AppTextField(
                large: true,
                controller: _nicknameController,
                label: 'Nickname',
                textInputAction: TextInputAction.next,
                validator: (v) => AuthValidators.required(
                  v,
                  fieldName: 'a nickname',
                ),
              ),
              right: AppPickerField(
                placeholder: 'Date of birth',
                valueText:
                    _dateOfBirth == null ? null : _formatDate(_dateOfBirth!),
                trailingIcon: AppIcons.calendar,
                onTap: _pickDateOfBirth,
              ),
            ),
            const SizedBox(height: 10),
            AppTextField(
              large: true,
              controller: _fullNameController,
              label: 'Full name',
              hint: 'As written on your ID card',
              prefixIcon: AppIcons.idCard,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  AuthValidators.required(v, fieldName: 'your full name'),
            ),
            const SizedBox(height: 10),
            AppTextField(
              large: true,
              controller: _matricController,
              label: 'Matric number (optional)',
              hint: 'RUN / CMP / 22 / 1234',
              prefixIcon: AppIcons.idCard,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            AppDropdownField<String>(
              label: 'Region / School',
              leadingIcon: AppIcons.building,
              value: _school,
              items: [
                for (final school in _availableSchools)
                  AppDropdownItem(school, school),
              ],
              onChanged: (value) => setState(() => _school = value),
            ),
            const SizedBox(height: 10),
            AppTextField(
              large: true,
              controller: _referralController,
              label: 'Referral code',
              hint: 'FLEX500 (optional)',
              prefixIcon: AppIcons.gift,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 22),
            const AppFormSection(title: 'Transaction PIN'),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 10),
              child: Text(
                'You\'ll enter this 4-digit PIN to confirm every order.',
                style: AppTypography.meta(c),
              ),
            ),
            AppFieldPair(
              left: _pinField(_pinController, 'PIN'),
              right: _pinField(_pinConfirmController, 'Confirm PIN'),
            ),
            if (_pinError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppFieldErrorRow(_pinError!),
            ],
          ],
        ),
      ),
      footer: AppPinnedFooter(
        primary: AppButton(
          label: 'Finish setup',
          icon: AppIcons.success,
          isLoading: _isLoading,
          onPressed: _submit,
        ),
      ),
    );
  }

  Widget _pinField(TextEditingController controller, String label) =>
      AppTextField(
        large: true,
        controller: controller,
        label: label,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        validator: (v) =>
            (v == null || v.length != 4) ? 'Enter 4 digits' : null,
      );
}
