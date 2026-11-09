import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import 'signup_draft.dart';
import 'signup_flow_controller.dart';
import 'signup_widgets.dart';
import '../../theme/app_icons.dart';

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
        _Check.ok => Icon(AppIcons.success, color: context.colors.brandText),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = _c.busy;
    final banner = _localError ?? _c.error;

    return AppAuthScaffold(
      header: AppAuthHeader.compact(
        title: 'Complete your\nprofile',
        subtitleWidget: Row(children: [
          Icon(AppIcons.success, size: 16, color: c.authSub),
          const SizedBox(width: AppSpacing.xs),
          const Text('Phone verified'),
        ]),
        // Leaving keeps the draft; "Create account" resumes here.
        onBack: () => Navigator.of(context).maybePop(),
        step: 3,
        totalSteps: 3,
        stepLabel: '3 / 3',
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 22),
            if (banner != null) SignupErrorBanner(banner),
            AppFieldPair(
              left: AppTextField(
                large: true,
                controller: _nickname,
                label: 'Nickname',
                textInputAction: TextInputAction.next,
                suffixIcon: _statusIcon(_nickCheck.state),
                errorText: _liveError(_nickCheck.state, 'Nickname is taken'),
                onChanged: (v) {
                  _nickCheck.input(v);
                  _saveSoon();
                },
                validator: (v) =>
                    AuthValidators.required(v, fieldName: 'a nickname'),
              ),
              right: AppPickerField(
                placeholder: 'Date of birth',
                valueText: _dob == null ? null : _formatDate(_dob!),
                trailingIcon: AppIcons.calendar,
                errorText: _dobError ? 'Select your date of birth' : null,
                onTap: _pickDob,
              ),
            ),
            const SizedBox(height: 10),
            AppTextField(
              large: true,
              controller: _fullName,
              label: 'Full name',
              hint: 'As written on your ID card',
              prefixIcon: AppIcons.idCard,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _saveSoon(),
              validator: (v) =>
                  AuthValidators.required(v, fieldName: 'your full name'),
            ),
            const SizedBox(height: 10),
            AppTextField(
              large: true,
              controller: _matric,
              label: 'Matric number (optional)',
              hint: 'RUN / CMP / 22 / 1234',
              prefixIcon: AppIcons.idCard,
              textInputAction: TextInputAction.next,
              suffixIcon: _statusIcon(_matricCheck.state),
              errorText: _liveError(_matricCheck.state,
                  'This matric number is already registered'),
              onChanged: (v) {
                _matricCheck.input(v);
                _saveSoon();
              },
            ),
            const SizedBox(height: 10),
            AppDropdownField<String>(
              label: 'Region / School',
              leadingIcon: AppIcons.building,
              value: _school,
              items: [
                for (final s in _availableSchools) AppDropdownItem(s, s),
              ],
              onChanged: (v) {
                setState(() => _school = v);
                _saveSoon();
              },
            ),
            const SizedBox(height: 10),
            AppTextField(
              large: true,
              controller: _referral,
              label: 'Referral code',
              hint: 'FLEX500 (optional)',
              prefixIcon: AppIcons.gift,
              textInputAction: TextInputAction.done,
              suffixIcon: _statusIcon(_referralCheck.state),
              errorText:
                  _liveError(_referralCheck.state, "That code isn't valid"),
              onChanged: (v) {
                _referralCheck.input(v);
                _saveSoon();
              },
            ),
            const SizedBox(height: 22),
            const AppFormSection(title: 'Transaction PIN'),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 10),
              child: Text(
                "You'll enter this 4-digit PIN to confirm every order.",
                style: AppTypography.meta(c),
              ),
            ),
            AppFieldPair(
              left: _pinField(_pin, 'PIN'),
              right: _pinField(_pinConfirm, 'Confirm PIN'),
            ),
          ],
        ),
      ),
      footer: AppPinnedFooter(
        primary: AppButton(
          label: 'Finish setup',
          icon: AppIcons.success,
          isLoading: busy,
          onPressed: busy ? null : _submit,
        ),
      ),
    );
  }

  Widget _pinField(TextEditingController c, String label) => AppTextField(
        large: true,
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
