import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/support_conversation.dart';
import '../../shared/services/support/support_chat_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/profile_basics.dart';
import 'admin_support_chat_screen.dart';
import '../../shared/widgets/inputs/app_text_field.dart';

/// Admin support inbox — lists all student conversations, newest first.
/// Filter chips: Open / Resolved / All.  Each row shows the student's
/// nickname as the main name with the full name underneath; search matches
/// nickname, full name or phone.
class AdminSupportInboxScreen extends ConsumerStatefulWidget {
  const AdminSupportInboxScreen({super.key});

  @override
  ConsumerState<AdminSupportInboxScreen> createState() =>
      _AdminSupportInboxScreenState();
}

class _AdminSupportInboxScreenState
    extends ConsumerState<AdminSupportInboxScreen> {
  _Filter _filter = _Filter.open;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final convAsync = ref.watch(allConversationsProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Support Inbox'),
      body: Column(
        children: [
          // ── Search ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              0,
            ),
            child: AppTextField(
              decoration: InputDecoration(
                hintText: 'Search by name or phone…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),

          // ── Filter chips ────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: FilterChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),

          // ── List ────────────────────────────────────────────────────
          Expanded(
            child: convAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => RetrySection(
                message: 'Could not load conversations.',
                onRetry: () => ref.invalidate(allConversationsProvider),
              ),
              data: (all) {
                // Names come from the admin-only profile function (Admin
                // cannot read other users' profile rows directly).
                final names = ref
                        .watch(adminProfileBasicsProvider(
                            profileIdsKey(all.map((c) => c.studentId))))
                        .valueOrNull ??
                    const <String, ProfileBasics>{};

                final filtered = _applyFilter(all, names);

                if (filtered.isEmpty) {
                  return _EmptyState(filter: _filter);
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: AppSpacing.screenGutter),
                  itemBuilder: (context, i) => _ConversationTile(
                    conversation: filtered[i],
                    profile: names[filtered[i].studentId],
                    onTap: () => _openChat(filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<SupportConversation> _applyFilter(
    List<SupportConversation> all,
    Map<String, ProfileBasics> names,
  ) {
    return all.where((c) {
      // Status filter.
      if (_filter == _Filter.open && !c.isOpen) return false;
      if (_filter == _Filter.resolved && !c.isResolved) return false;
      // Name / preview search.
      if (_query.isNotEmpty) {
        final byName = names[c.studentId]?.matches(_query) ?? false;
        final preview = c.lastMessagePreview?.toLowerCase() ?? '';
        if (!byName && !preview.contains(_query)) return false;
      }
      return true;
    }).toList();
  }

  void _openChat(SupportConversation conv) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminSupportChatScreen(conversation: conv),
      ),
    );
  }
}

// ── Filter enum ──────────────────────────────────────────────────────────────

enum _Filter { open, resolved, all }

extension on _Filter {
  String get label => switch (this) {
        _Filter.open => 'Open',
        _Filter.resolved => 'Resolved',
        _Filter.all => 'All',
      };
}

// ── Conversation tile ─────────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.profile,
    required this.onTap,
  });

  final SupportConversation conversation;
  final ProfileBasics? profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conv = conversation;
    final hasUnread = conv.adminUnreadCount > 0;
    final mainName = profile?.displayName('Student') ?? 'Student';
    final fullName = profile?.secondaryName;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.xs,
      ),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        child: Text(
          _initials(mainName),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              mainName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conv.lastMessageAt != null)
            Text(
              _timeLabel(conv.lastMessageAt!),
              style: theme.textTheme.labelSmall?.copyWith(
                color: hasUnread
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fullName != null)
            Text(
              fullName,
              key: const ValueKey('inbox-full-name'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  conv.lastMessagePreview ?? 'No messages yet',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hasUnread
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasUnread)
                Container(
                  margin: const EdgeInsets.only(left: AppSpacing.xs),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '${conv.adminUnreadCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: context.colors.onBrand,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              if (conv.isResolved)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      'Resolved',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  String _timeLabel(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}';
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});
  final _Filter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              filter == _Filter.open
                  ? 'No open conversations'
                  : filter == _Filter.resolved
                      ? 'No resolved conversations'
                      : 'No conversations yet',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
