import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../../core/utils/l10n.dart';

/// Search across chats, contacts, groups, channels and message bodies.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final TextEditingController _query = TextEditingController();
  String _queryText = '';
  SearchKind? _filter;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String q = _queryText.trim();
    final AsyncValue<List<SearchHit>> results =
        q.isEmpty ? const AsyncData<List<SearchHit>>(<SearchHit>[]) : ref.watch(globalSearchProvider(q));
    final List<String> recent = ref.watch(recentSearchesProvider).orEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          cursorColor: context.c.accent,
          style: context.t.bodyLarge,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: context.l10n.searchEverything,
            hintStyle: context.t.bodyLarge?.copyWith(
              color: context.c.textSecondary,
            ),
          ),
          onChanged: (String v) => setState(() => _queryText = v),
          onSubmitted: (String v) {
            if (v.trim().isNotEmpty) {
              ref.read(recentSearchesProvider.notifier).add(v.trim());
            }
          },
        ),
        actions: <Widget>[
          if (_queryText.isNotEmpty)
            IconButton(
              tooltip: context.l10n.clear,
              onPressed: () => setState(() {
                _query.clear();
                _queryText = '';
              }),
              icon: const Icon(Icons.close_rounded),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: q.isEmpty ? _buildIdle(recent) : _buildResults(results, q),
    );
  }

  Widget _buildIdle(List<String> recent) {
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: <Widget>[
        if (recent.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: context.l10n.recent,
            trailing: TextButton(
              onPressed: () => ref.read(recentSearchesProvider.notifier).clear(),
              child: Text(context.l10n.clear),
            ),
          ),
          for (final String term in recent)
            SettingsTile(
              title: term,
              leadingIcon: Icons.history_rounded,
              onTap: () {
                _query.text = term;
                setState(() => _queryText = term);
              },
              trailing: IconButton(
                tooltip: context.l10n.remove,
                onPressed: () {
                  ref.read(recentSearchesProvider.notifier).remove(term);
                },
                icon: const Icon(Icons.north_west_rounded,
                    size: AppIconSizes.sm),
              ),
            ),
        ],
        SectionHeader(title: context.l10n.searchIn),
        for (final ({SearchKind? kind, IconData icon, String label}) entry
            in <({SearchKind? kind, IconData icon, String label})>[
          (kind: null, icon: Icons.search_rounded, label: context.l10n.everything),
          (kind: SearchKind.chat, icon: Icons.chat_bubble_outline_rounded, label: context.l10n.tabChats),
          (kind: SearchKind.message, icon: Icons.article_outlined, label: context.l10n.messages),
          (kind: SearchKind.contact, icon: Icons.person_outline_rounded, label: context.l10n.tabContacts),
          (kind: SearchKind.group, icon: Icons.groups_rounded, label: context.l10n.filterGroups),
          (kind: SearchKind.channel, icon: Icons.podcasts_rounded, label: context.l10n.channels),
        ])
          SettingsTile(
            title: entry.label,
            leadingIcon: entry.icon,
            leadingIconColor:
                _filter == entry.kind ? context.c.accent : null,
            titleColor: _filter == entry.kind ? context.c.accent : null,
            onTap: () => setState(() => _filter = entry.kind),
            trailing: _filter == entry.kind
                ? Icon(Icons.check_rounded, color: context.c.accent)
                : null,
          ),
      ],
    );
  }

  Widget _buildResults(AsyncValue<List<SearchHit>> async, String q) {
    return async.when(
      loading: () => const Center(child: ILoader(size: 26)),
      error: (Object e, StackTrace s) => errorStateFor(context, e),
      data: (List<SearchHit> hits) {
        final List<SearchHit> visible = _filter == null
            ? hits
            : hits.where((SearchHit h) => h.kind == _filter).toList();

        if (visible.isEmpty) {
          return EmptyState(
            icon: Icons.search_off_rounded,
            title: context.l10n.noResults,
            message: context.l10n.nothingMatchesQuery(q),
          );
        }

        final Map<SearchKind, List<SearchHit>> grouped =
            <SearchKind, List<SearchHit>>{};
        for (final SearchHit h in visible) {
          grouped.putIfAbsent(h.kind, () => <SearchHit>[]).add(h);
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
          children: <Widget>[
            for (final MapEntry<SearchKind, List<SearchHit>> entry
                in grouped.entries) ...<Widget>[
              SectionHeader(title: _labelFor(context, entry.key)),
              for (final SearchHit hit in entry.value)
                _SearchResultRow(
                  hit: hit,
                  onTapAvatar: () => _openProfile(hit),
                  onTapRow: () => _open(hit),
                ),
            ],
          ],
        );
      },
    );
  }

  /// Opens the details page for a hit — the avatar's destination.
  ///
  /// Tapping the name starts a conversation, tapping the picture shows who the
  /// person is. Contacts reachable only through the device address book have no
  /// locally-stored record yet, so they fall back to the new-contact form
  /// pre-filled with the number rather than dead-ending on an empty profile.
  void _openProfile(SearchHit hit) {
    switch (hit.kind) {
      case SearchKind.chat:
      case SearchKind.group:
        context.push('${AppRoutes.groupInfo}/${hit.id}');
      case SearchKind.contact:
        context.push('${AppRoutes.contactInfo}/${hit.id}');
      case SearchKind.message:
        // A message hit resolves to its conversation, which is the only place
        // a profile page could sensibly come from.
        if (hit.chatId != null) context.push('${AppRoutes.chat}/${hit.chatId}');
      default:
        break;
    }
  }

  void _open(SearchHit hit) {
    ref.read(recentSearchesProvider.notifier).add(_queryText.trim());
    switch (hit.kind) {
      case SearchKind.chat:
        context.push('${AppRoutes.chat}/${hit.id}');
      case SearchKind.message:
        if (hit.chatId != null) context.push('${AppRoutes.chat}/${hit.chatId}');
      case SearchKind.contact:
        context.push('${AppRoutes.contactInfo}/${hit.id}');
      case SearchKind.group:
        context.push('${AppRoutes.groupInfo}/${hit.id}');
      default:
        break;
    }
  }

  /// Section heading for a result group.
  ///
  /// Takes a [BuildContext] explicitly: it is `static`, so it has no `context`
  /// of its own, and the labels are localised.
  static String _labelFor(BuildContext context, SearchKind kind) {
    switch (kind) {
      case SearchKind.chat:
        return context.l10n.tabChats;
      case SearchKind.message:
        return context.l10n.messages;
      case SearchKind.contact:
        return context.l10n.tabContacts;
      case SearchKind.group:
        return context.l10n.filterGroups;
      case SearchKind.community:
        return context.l10n.tabCommunities;
      case SearchKind.channel:
        return context.l10n.channels;
    }
  }

}

/// One search result, with two distinct tap targets.
///
/// Tapping the name (or anywhere on the row) opens the conversation or the
/// content itself; tapping the avatar opens the profile behind it. The avatar
/// owns its own gesture so the parent row does not swallow that tap — a single
/// `onTap` for the whole tile was the original behaviour and it made the
/// picture indistinguishable from the text.
class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.hit,
    required this.onTapAvatar,
    required this.onTapRow,
  });

  final SearchHit hit;
  final VoidCallback onTapAvatar;
  final VoidCallback onTapRow;

  /// True when the avatar leads somewhere genuinely different from the row.
  ///
  /// For a chat hit both gestures land on the same conversation, so the avatar
  /// is not given its own target — that would only add a confusing dead zone.
  bool get _avatarIsDistinct =>
      hit.kind == SearchKind.contact ||
      hit.kind == SearchKind.group ||
      hit.kind == SearchKind.community ||
      hit.kind == SearchKind.channel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.searchResult(hit.title),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTapRow,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              children: <Widget>[
                IAvatar(
                  name: hit.title,
                  imagePath: hit.avatarPath,
                  size: AppSizes.avatarMd,
                  isGroup: hit.kind == SearchKind.group,
                  icon: _GlobalSearchIcons.forKind(hit.kind),
                  onTap: _avatarIsDistinct ? onTapAvatar : null,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        hit.title,
                        style: context.t.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hit.subtitle.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          hit.subtitle,
                          style: context.t.bodySmall?.copyWith(
                            color: context.c.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (hit.timestamp != null)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Text(
                      DateFormatter.chatTimestamp(hit.timestamp!),
                      style: context.t.labelSmall?.copyWith(
                        color: context.c.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon lookup shared by the row widgets in this file.
class _GlobalSearchIcons {
  const _GlobalSearchIcons._();

  static IconData forKind(SearchKind kind) {
    switch (kind) {
      case SearchKind.chat:
        return Icons.chat_bubble_outline_rounded;
      case SearchKind.message:
        return Icons.article_outlined;
      case SearchKind.contact:
        return Icons.person_outline_rounded;
      case SearchKind.group:
        return Icons.groups_rounded;
      case SearchKind.community:
        return Icons.groups_2_rounded;
      case SearchKind.channel:
        return Icons.podcasts_rounded;
    }
  }
}
