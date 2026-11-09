import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth/auth_providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/buttons/app_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../../widgets/progress/onboarding_progress_bar.dart';
import '../signup/signup_draft.dart';
import '../signup/signup_flow_controller.dart';
import '../signup/signup_widgets.dart';
import '../validators.dart';
import '../signup/signup_final_step.dart';
import 'verify_phone_screen.dart';
import '../../theme/app_icons.dart';

/// Student self-signup (Pack 5) — THREE steps, and the account is created
/// only at the very end:
///
///   1. Your details   email, password, phone  → server checks they're free,
///                     THEN sends the SMS; moves on only if that worked
///   2. Verify phone   6-digit code (60 s resend, "Change number")
///   3. Final details  nickname, name, matric, school, DOB, referral, PIN
///                     → ONE server call creates everything, then we sign in
///
/// This widget is only the host: it loads the saved draft (so leaving and
/// coming back resumes the same step) and shows the widget for the current
/// step. All logic lives in [SignupFlowController]. Rider/Admin accounts are
/// invite-only and never come through here.
class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key, this.controller});

  /// Tests inject a controller; the app builds its own.
  final SignupFlowController? controller;

  @override
  ConsumerState<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  SignupFlowController? _c;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.controller != null) {
      _c = widget.controller;
      if (!_c!.loaded) await _c!.load();
      if (mounted) setState(() {});
      return;
    }
    final api = ref.read(signupApiProvider);
    final auth = ref.read(authServiceProvider);
    final secrets = ref.read(signupSecretStoreProvider);
    final prefs = await SharedPreferences.getInstance();
    final c = SignupFlowController(
      store: SignupDraftStore(prefs, secrets),
      api: api,
      signIn: (email, password) =>
          auth.signInWithEmail(email: email, password: password),
    );
    await c.load();
    if (!mounted) {
      c.dispose();
      return;
    }
    setState(() => _c = c);
  }

  @override
  void dispose() {
    if (widget.controller == null) _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !c.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return PopScope(
          // System back on step 2 = "Change number", not "leave".
          canPop: c.step != 2,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) c.changeNumber();
          },
          child: switch (c.step) {
            1 => SignupDetailsStep(
                key: const ValueKey('signup-step-1'), controller: c),
            2 => VerifyPhoneScreen(
                key: const ValueKey('signup-step-2'), controller: c),
            _ => SignupFinalStep(
                key: const ValueKey('signup-step-3'), controller: c),
          },
        );
      },
    );
  }
}

/// Step 1 — email, password, confirm, phone.
class SignupDetailsStep extends StatefulWidget {
  const SignupDetailsStep({super.key, required this.controller});

  final SignupFlowController controller;

  @override
  State<SignupDetailsStep> createState() => _SignupDetailsStepState();
}

class _SignupDetailsStepState extends State<SignupDetailsStep> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController =
      TextEditingController(text: widget.controller.draft.email);
  late final _passwordController =
      TextEditingController(text: widget.controller.password ?? '');
  late final _confirmPasswordController =
      TextEditingController(text: widget.controller.password ?? '');
  late final _phoneController =
      TextEditingController(text: widget.controller.draft.phoneInput);

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  SignupFlowController get _c => widget.controller;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // On success the controller moves to step 2 and the host swaps this
    // widget out — there is no navigation call here on purpose.
    await _c.submitDetails(
      email: _emailController.text,
      phoneInput: _phoneController.text,
      password: _passwordController.text,
    );
  }

  Future<void> _startOver() async {
    await _c.startOver();
    _emailController.clear();
    _passwordController.clear();
    _confirmPasswordController.clear();
    _phoneController.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondaryInk = context.colors.textSecondary;
    final busy = _c.busy;

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
                  step: 1,
                  totalSteps: 3,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Create your\naccount', style: textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Food, deliveries and errands across campus. '
                  'Takes about a minute.',
                  style: textTheme.bodyMedium?.copyWith(color: secondaryInk),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (_c.error != null) SignupErrorBanner(_c.error!),
                AppTextField(
                  controller: _emailController,
                  label: 'Email address',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  prefixIcon: AppIcons.mail,
                  validator: AuthValidators.email,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: '8+ characters, at least one number',
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  prefixIcon: AppIcons.lock,
                  suffixIcon: IconButton(
                    icon:
                        Icon(_obscurePassword ? AppIcons.eye : AppIcons.eyeOff),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: AuthValidators.password,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _confirmPasswordController,
                  label: 'Confirm password',
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.next,
                  prefixIcon: AppIcons.lock,
                  suffixIcon: IconButton(
                    icon:
                        Icon(_obscureConfirm ? AppIcons.eye : AppIcons.eyeOff),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Confirm your password';
                    if (v != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _phoneController,
                  label: 'Phone number',
                  hint: '08012345678',
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  prefixIcon: AppIcons.phone,
                  validator: AuthValidators.phone,
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Continue',
                  icon: AppIcons.forward,
                  isLoading: busy,
                  onPressed: busy ? null : _submit,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style:
                          textTheme.bodyMedium?.copyWith(color: secondaryInk),
                    ),
                    AppButton(
                      label: 'Log in',
                      variant: AppButtonVariant.text,
                      size: AppButtonSize.small,
                      expand: false,
                      onPressed:
                          busy ? null : () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
                if (_c.hasProgress) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: AppButton(
                      key: const ValueKey('start-over'),
                      label: 'Start over',
                      variant: AppButtonVariant.text,
                      size: AppButtonSize.small,
                      expand: false,
                      onPressed: busy ? null : _startOver,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
