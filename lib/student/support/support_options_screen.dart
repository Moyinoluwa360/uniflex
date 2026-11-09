import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/profile.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/settings/support_whatsapp_provider.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/phone_format.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/lists/app_list_group.dart';
import 'support_chat_screen.dart';

/// "Help & Support" — the choice between live chat and WhatsApp.
///
/// Admin sets ONE WhatsApp number (Manage → Support settings). When none is
/// set (or it cannot be loaded) there is nothing to choose, so this screen
/// simply IS the live chat — no empty choice screen, no dead button.
///
/// [orderShortId] / the order or group ids carry "I'm asking about this
/// order" through to either channel: the live chat attaches the order, the
/// WhatsApp message names it.
class SupportOptionsScreen extends ConsumerWidget {
  const SupportOptionsScreen({
    super.key,
    this.orderId,
    this.orderLabel,
    this.groupId,
    this.groupLabel,
    this.orderShortId,
    this.launcher,
    this.liveChatBuilder,
  });

  final String? orderId;
  final String? orderLabel;
  final String? groupId;
  final String? groupLabel;

  /// Short order id shown in the WhatsApp message (e.g. `AB12CD`).
  final String? orderShortId;

  /// Opens a URL outside the app. Defaults to the system browser/WhatsApp;
  /// replaced in tests.
  final Future<bool> Function(Uri uri)? launcher;

  /// Builds the live chat. Defaults to [SupportChatScreen]; replaced in tests.
  final WidgetBuilder? liveChatBuilder;

  Widget _liveChat(BuildContext context) =>
      liveChatBuilder?.call(context) ??
      SupportChatScreen(
        initialOrderId: orderId,
        initialOrderLabel: orderLabel,
        initialGroupId: groupId,
        initialGroupLabel: groupLabel,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final whatsapp = ref.watch(supportWhatsappProvider);

    return whatsapp.when(
      loading: () => const Scaffold(
        appBar: UniflexAppBar(title: 'Help & Support'),
        body: Center(child: CircularProgressIndicator()),
      ),
      // No number (or we could not read it): live chat only, straight away.
      error: (_, __) => _liveChat(context),
      data: (digits) {
        if (digits == null) return _liveChat(context);
        return _Choice(
          digits: digits,
          orderShortId: orderShortId,
          launcher: launcher,
          openLiveChat: () => Navigator.of(context).push(
            MaterialPageRoute(builder: _liveChat),
          ),
        );
      },
    );
  }
}

class _Choice extends ConsumerWidget {
  const _Choice({
    required this.digits,
    required this.orderShortId,
    required this.launcher,
    required this.openLiveChat,
  });

  final String digits;
  final String? orderShortId;
  final Future<bool> Function(Uri uri)? launcher;
  final VoidCallback openLiveChat;

  Future<void> _openWhatsapp(BuildContext context, WidgetRef ref) async {
    // Normally already loaded (the app shell watches it); wait briefly if not,
    // and fall back to a generic greeting rather than failing.
    Profile? profile;
    try {
      profile = await ref.read(currentProfileProvider.future);
    } catch (_) {
      profile = null;
    }
    final name = (profile?.nickname?.trim().isNotEmpty ?? false)
        ? profile!.nickname
        : profile?.fullName;
    final uri = buildSupportWhatsappUri(
      digits: digits,
      name: name,
      orderShortId: orderShortId,
    );
    var opened = false;
    try {
      opened = await (launcher ??
          (u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("Couldn't open WhatsApp. You can use live chat instead."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const UniflexAppBar(title: 'Help & Support'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        children: [
          Text(
            'How would you like to reach us?',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          AppListGroup(
            children: [
              AppListRow(
                key: const ValueKey('option-live-chat'),
                leadingIcon: AppIcons.chat,
                title: 'Live chat',
                subtitle: 'Chat with us here in the app. Replies show up here.',
                showChevron: true,
                onTap: openLiveChat,
              ),
              AppListRow(
                key: const ValueKey('option-whatsapp'),
                leadingIcon: AppIcons.phone,
                title: 'WhatsApp',
                subtitle: 'Message us on WhatsApp.',
                showChevron: true,
                onTap: () => _openWhatsapp(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
