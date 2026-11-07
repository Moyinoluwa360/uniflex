import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../../widgets/progress/onboarding_progress_bar.dart';
import '../validators.dart';
import 'signup_draft.dart';
import 'signup_flow_controller.dart';
import 'signup_widgets.dart';

const _availableSchools = ["Redeemer's University"];

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

String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

enum _Check { idle, checking, ok, bad }

/// Debounced "is this free / valid?" lookup for one text field.
class _LiveCheck {
  _LiveCheck(this._check, this._onChange);

  final Future<bool?> Function(String) _check;
  final VoidCallback _onChange;
  Timer? _timer;
  int _seq = 0;
  _Check state = _Check.idle;

  void input(String raw) {
    _timer?.cancel();
    final v = raw.trim();
    final seq = ++_seq;
    if (v.isEmpty) {
      state = _Check.idle;
      _onChange();
      return;
    }
    state = _Check.checking;
    _onChange();
    _timer = Timer(const Duration(milliseconds: 500), () async {
      final result = await _check(v);
      if (seq != _seq) return; // a newer keystroke superseded this one
      // null = couldn't tell (offline) → don't block; the server re-checks.
      state = result == null ? _Check.idle : (result ? _Check.ok : _Check.bad);
      _onChange();
    });
  }

  void dispose() => _timer?.cancel();
}

/// Step 3 of sign-up — everything else about the student, then ONE server
/// call creates the account (profile, wallet, referral, hashed PIN) and we
/// sign in. After that [AuthGate] shows the Student shell by itself; the
/// only navigation here is closing the sign-up screens so AuthGate shows.
class SignupFinalStep extends StatefulWidget {
  const SignupFinalStep({super.key, required this.controller});

  final SignupFlowController controller;

  @override
  State<SignupFinalStep> createState() => _SignupFinalStepState();
}

class _SignupFinalStepState extends State<SignupFinalStep> {
  final _formKey = GlobalKey<FormState>();
  late final _nickname = TextEditingController(text: _c.draft.nickname);
  late final _fullName = TextEditingController(text: _c.draft.fullName);
  late final _matric = TextEditingController(text: _c.draft.matric);
  late final _referral = TextEditingController(text: _c.draft.referral);
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();

  late String _school = _availableSchools.contains(_c.draft.school)
      ? _c.draft.school
      : _availableSchools.first;
  late DateTime? _dob = _c.draft.dateOfBirth;

  late final _nickCheck = _LiveCheck(_c.api.isNicknameAvailable, _refresh);
  late final _matricCheck = _LiveCheck(_c.api.isMatricAvailable, _refresh);
  late final _referralCheck = _LiveCheck(_c.api.isReferralValid, _refresh);

  Timer? _saveTimer;
  Timer? _proofTimer;
  String? _localError;
  bool _dobError = false;

  SignupFlowController get _c => widget.controller;

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // If the phone proof runs out while this screen is open → back to step 2.
    final at = _c.draft.proofAt;
    if (at != null) {
      final left = kProofLifetime - DateTime.now().difference(at);
      _proofTimer = Timer(
        left.isNegative ? Duration.zero : left,
        () => _c.expireProof(),
      );
    }
    if (_nickname.text.isNotEmpty) _nickCheck.input(_nickname.text);
  }

  @override
  void dispose() {
    _saveNow();
    _saveTimer?.cancel();
    _proofTimer?.cancel();
    _nickCheck.dispose();
    _matricCheck.dispose();
    _referralCheck.dispose();
    _nickname.dispose();
    _fullName.dispose();
    _matric.dispose();
    _referral.dispose();
    _pin.dispose();
    _pinConfirm.dispose();
    super.dispose();
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  // Never includes the PIN.
  void _saveNow() {
    unawaited(_c.saveFinalFields(
      nickname: _nickname.text.trim(),
      fullName: _fullName.text.trim(),
      matric: _matric.text.trim(),
      school: _school,
      referral: _referral.text.trim(),
      dateOfBirth: _dob,
    ));
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 14, now.month, now.day),
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobError = false;
      });
      _saveSoon();
    }
  }

  String? _liveError(_Check s, String taken) => s == _Check.bad ? taken : null;

  Future<void> _submit() async {
    setState(() => _localError = null);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (_dob == null) setState(() => _dobError = true);
    if (!formOk || _dob == null) return;
    if (_pin.text != _pinConfirm.text) {
      setState(() => _localError = 'PINs do not match');
      return;
    }
    if (_nickCheck.state == _Check.bad ||
        _matricCheck.state == _Check.bad ||
        (_referral.text.trim().isNotEmpty &&
            _referralCheck.state == _Check.bad)) {
      return; // the field already shows what's wrong
    }

    _saveNow();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await _c.submitFinal(
      nickname: _nickname.text,
      fullName: _fullName.text,
      matric: _matric.text,
      school: _school,
      dateOfBirth: _dob!,
      referral: _referral.text,
      pin: _pin.text,
    );
    switch (outcome) {
      case SignupOutcome.created:
        // Signed in. Close the sign-up screens; AuthGate (underneath) has
        // already switched to the Student shell.
        nav.popUntil((r) => r.isFirst);
      case SignupOutcome.createdButSignInFailed:
        nav.popUntil((r) => r.isFirst);
        messenger.showSnackBar(const SnackBar(
          content: Text(
              'Your account is ready. Log in with your email and password.'),
        ));
      case SignupOutcome.failed:
        break; // the controller's error banner explains why
    }
  }

  Widget? _statusIcon(_Check s) => switch (s) {
        _Check.checking => const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        _Check.ok => const Icon(Icons.check_circle, color: AppColors.emerald),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondaryInk = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkInkSecondary
        : AppColors.mediumGrey;
    final busy = _c.busy;
    final banner = _localError ?? _c.error;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OnboardingProgressHeader(
                  step: 3,
                  totalSteps: 3,
                  // Leaving keeps the draft; "Create account" resumes here.
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Complete your\nprofile', style: textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  const Icon(Icons.verified,
                      size: 16, color: AppColors.emerald),
                  const SizedBox(width: AppSpacing.xs),
                  Text('Phone verified',
                      style:
                          textTheme.bodySmall?.copyWith(color: secondaryInk)),
                ]),
                const SizedBox(height: AppSpacing.xl),
                if (banner != null) SignupErrorBanner(banner),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _nickname,
                        label: 'Nickname',
                        prefixIcon: Icons.alternate_email,
                        textInputAction: TextInputAction.next,
                        suffixIcon: _statusIcon(_nickCheck.state),
                        errorText:
                            _liveError(_nickCheck.state, 'Nickname is taken'),
                        onChanged: (v) {
                          _nickCheck.input(v);
                          _saveSoon();
                        },
                        validator: (v) =>
                            AuthValidators.required(v, fieldName: 'a nickname'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: InkWell(
                        onTap: _pickDob,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Date of birth',
                            suffixIcon:
                                const Icon(Icons.calendar_today_outlined),
                            errorText:
                                _dobError ? 'Select your date of birth' : null,
                          ),
                          child: Text(_dob == null
                              ? 'Date of birth'
                              : _formatDate(_dob!)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _fullName,
                  label: 'Full name',
                  hint: 'As written on your ID card',
                  prefixIcon: Icons.badge_outlined,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _saveSoon(),
                  validator: (v) =>
                      AuthValidators.required(v, fieldName: 'your full name'),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _matric,
                  label: 'Matric number (optional)',
                  hint: 'RUN / CMP / 22 / 1234',
                  prefixIcon: Icons.badge_outlined,
                  textInputAction: TextInputAction.next,
                  suffixIcon: _statusIcon(_matricCheck.state),
                  errorText: _liveError(_matricCheck.state,
                      'This matric number is already registered'),
                  onChanged: (v) {
                    _matricCheck.input(v);
                    _saveSoon();
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _school,
                  decoration:
                      const InputDecoration(labelText: 'Region / School'),
                  items: [
                    for (final s in _availableSchools)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) {
                    setState(() => _school = v ?? _school);
                    _saveSoon();
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _referral,
                  label: 'Referral code',
                  hint: 'FLEX500 (optional)',
                  prefixIcon: Icons.card_giftcard_outlined,
                  textInputAction: TextInputAction.done,
                  suffixIcon: _statusIcon(_referralCheck.state),
                  errorText:
                      _liveError(_referralCheck.state, "That code isn't valid"),
                  onChanged: (v) {
                    _referralCheck.input(v);
                    _saveSoon();
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Transaction PIN', style: textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "You'll enter this 4-digit PIN to confirm every order.",
                  style: textTheme.bodySmall?.copyWith(color: secondaryInk),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: _pinField(_pin, 'PIN')),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: _pinField(_pinConfirm, 'Confirm PIN')),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Finish setup',
                  icon: Icons.check_circle_outline,
                  isLoading: busy,
                  onPressed: busy ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pinField(TextEditingController c, String label) => AppTextField(
        controller: c,
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
