import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth/auth_providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/auth/app_auth_header.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/buttons/app_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../validators.dart';
import 'reset_password_screen.dart';
import '../../widgets/notice/app_inline_notice.dart';
import '../../theme/app_icons.dart';

/// Forgot Password — Step 1: enter the account email, request a 6-digit
/// recovery code. Reachable from the Login screen.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final email = _emailController.text.trim();

    try {
      await ref.read(authServiceProvider).sendPasswordResetOtp(email);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(email: email),
        ),
      );
    } on AuthException catch (e) {
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
        title: 'Forgot Password',
        subtitle: 'Reset your password',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 28),
            Text(
              'Enter the email on your account and we\'ll send you a '
              '6-digit code to reset your password.',
              style: AppTypography.meta(c),
            ),
            const SizedBox(height: 20),
            if (_errorText != null) ...[
              AppInlineNotice(isError: true, text: _errorText!),
              const SizedBox(height: AppSpacing.md),
            ],
            AppTextField(
              large: true,
              controller: _emailController,
              label: 'Email address',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              prefixIcon: AppIcons.mail,
              validator: AuthValidators.email,
            ),
          ],
        ),
      ),
      footer: AppPinnedFooter(
        primary: AppButton(
          label: 'Send Code',
          icon: AppIcons.mail,
          isLoading: _isLoading,
          onPressed: _submit,
        ),
      ),
    );
  }
}
