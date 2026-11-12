import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/config/legal_links.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/profile/profile_service.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/notice/app_inline_notice.dart';
import '../../shared/widgets/pin/pin_entry_sheet.dart';

/// Pack 2 — in-app account deletion (Apple 5.1.1(v), Google Play).
///
/// Rules (owner, 2026-11-12, same as uniflex.live/delete-account): refused
/// while an order / errand / gift is in progress; a positive balance is lost
/// (shown here first); personal data and the login are removed; order and
/// wallet records are kept without anything that identifies the student.
/// Everything is enforced by `delete_my_account` on the server.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _delete(double balance) async {
    if (_busy) return;
    final confirmed = await AppDialog.show(
      context,
      title: 'Delete your account?',
      body: balance > 0
          ? 'Your ${Money.format(balance)} wallet balance will be lost. '
              'This cannot be undone.'
          : 'This cannot be undone.',
      secondaryLabel: 'Keep my account',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final pin = await showEnterPinSheet(
      context,
      title: 'Confirm with your PIN',
      subtitle: 'Enter your 4-digit transaction PIN to delete your account.',
    );
    if (pin == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileServiceProvider).deleteMyAccount(pin);
    } on ProfileException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return;
    }

    // Deleted on the server. Leave every screen and sign out on this phone
    // (the server already ended every session, so a server error here is
    // expected and ignored).
    if (!mounted) return;
    final client = ref.read(supabaseClientProvider);
    final auth = ref.read(authServiceProvider);
    Navigator.of(context).popUntil((route) => route.isFirst);
    try {
      await auth.signOut();
    } catch (_) {
      await client.auth.signOut(scope: SignOutScope.local);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    final balance = ref.watch(walletBalanceProvider).valueOrNull ?? 0;

    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: AppTypography.body(c)),
              Expanded(child: Text(text, style: AppTypography.body(c))),
            ],
          ),
        );

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Delete account'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('What happens', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bullet('Your name, email, phone number, matric number, '
                      'date of birth, PIN, support chats and notifications '
                      'are deleted, and you can no longer sign in.'),
                  bullet('Records of past orders and payments are kept for '
                      'accounting, with nothing that identifies you.'),
                  bullet('You can sign up again later with the same email '
                      'and phone number as a new account.'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppInlineNotice(
              key: const ValueKey('delete-balance-notice'),
              text: balance > 0
                  ? 'Your wallet balance of ${Money.format(balance)} will be '
                      'lost. Use it before deleting your account.'
                  : 'Orders, errands and gifts still in progress must be '
                      'delivered or cancelled first.',
              icon: AppIcons.info,
              isError: balance > 0,
            ),
            if (balance > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Orders, errands and gifts still in progress must be '
                'delivered or cancelled first.',
                style: AppTypography.meta(c),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppInlineNotice(
                key: const ValueKey('delete-error'),
                text: _error!,
                icon: AppIcons.error,
                isError: true,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              key: const ValueKey('delete-account-button'),
              label: _busy ? 'Deleting…' : 'Delete my account',
              icon: AppIcons.delete,
              variant: AppButtonVariant.quietDanger,
              onPressed: _busy ? null : () => _delete(balance),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'How we handle your data',
              variant: AppButtonVariant.text,
              size: AppButtonSize.small,
              onPressed: () => LegalLinks.open(LegalLinks.privacyPolicy),
            ),
          ],
        ),
      ),
    );
  }
}
