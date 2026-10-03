import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/remote_contact_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../chats/domain/chat_service.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../domain/directory_search_service.dart';
import '../../../core/utils/l10n.dart';

/// Debounced directory search state.
final Provider<DirectorySearchService> directorySearchServiceProvider =
    Provider<DirectorySearchService>((Ref ref) {
  final DirectorySearchService service = DirectorySearchService(
    directory: ref.watch(remoteContactServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Results of the live directory search, keyed by the query.
final StreamProviderFamily<List<RemoteProfile>, String>
    directorySearchProvider =
    StreamProvider.family<List<RemoteProfile>, String>((Ref ref, String query) {
  final DirectorySearchService service =
      ref.watch(directorySearchServiceProvider);
  // Kick the debounced query, then surface the shared result stream. The
  // provider rebuilds per query string, which is what makes the debounce window
  // restart on every keystroke.
  service.search(query);
  return service.stream;
});

/// Live lookup of one exact identifier (phone, email, @handle or uid).
///
/// Separate from [directorySearchProvider] because the "New contact" screen
/// needs a single unambiguous answer — "is this number on Imo LIVE?" — not a
/// list.
final FutureProviderFamily<LookupResult, String> directoryLookupProvider =
    FutureProvider.family<LookupResult, String>((Ref ref, String identifier) {
  return ref.watch(remoteContactServiceProvider).findByAnyIdentifier(identifier);
});

/// Smart search over the shared Imo LIVE directory.
///
/// Typing a phone number, an email address, an `@username` or a uid returns the
/// matching accounts in real time. Tapping the name opens a chat; tapping the
/// avatar opens the profile.
class DirectorySearchScreen extends ConsumerStatefulWidget {
  const DirectorySearchScreen({super.key});

  @override
  ConsumerState<DirectorySearchScreen> createState() =>
      _DirectorySearchScreenState();
}

class _DirectorySearchScreenState
    extends ConsumerState<DirectorySearchScreen> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  String _queryText = '';

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// Seeds the search field from a hint row and puts the caret back in it.
  ///
  /// Each hint row stands for one searchable identifier, so tapping it starts
  /// the query in the right shape (`+` for a number, `@` for a handle) instead
  /// of leaving the user to guess the format. The field is always re-focused so
  /// the keyboard stays up and the next keystroke continues the query.
  void _seedQuery(String seed) {
    _query.text = seed;
    _query.selection = TextSelection.collapsed(offset: seed.length);
    setState(() => _queryText = seed);
    _queryFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final String q = _queryText.trim();
    final DirectoryQueryKind kind = DirectorySearchService.kindOf(q);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: TextField(
          controller: _query,
          focusNode: _queryFocus,
          autofocus: true,
          cursorColor: context.c.accent,
          style: context.t.bodyLarge,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: context.l10n.phoneEmailUsernameOrUser,
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
      body: q.isEmpty
          ? _AddByHandleHint(onPick: _seedQuery)
          : _Results(query: q, kind: kind),
    );
  }
}

/// What to search — shown before the user types.
class _AddByHandleHint extends StatelessWidget {
  const _AddByHandleHint({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: <Widget>[
        SectionHeader(title: context.l10n.searchImoLIVEBy),
        for (final ({
          IconData icon,
          String title,
          String subtitle,
          String seed,
        }) entry in <({
          IconData icon,
          String title,
          String subtitle,
          String seed,
        })>[
          (
            icon: Icons.phone_rounded,
            title: context.l10n.phoneNumber,
            subtitle: context.l10n.eG8801712345678,
            seed: '+',
          ),
          (
            icon: Icons.alternate_email_rounded,
            title: '@username',
            subtitle: context.l10n.eGImouser042117,
            seed: '@',
          ),
          (
            icon: Icons.mail_outline_rounded,
            title: context.l10n.emailAddress,
            subtitle: context.l10n.eGNameExampleCom,
            // No email prefix exists, so this row only moves the caret back
            // into the field rather than guessing at a format.
            seed: '',
          ),
          (
            icon: Icons.badge_outlined,
            title: context.l10n.userID,
            subtitle: context.l10n.theUidShownOnA,
            seed: '',
          ),
        ])
          SettingsTile(
            title: entry.title,
            subtitle: entry.subtitle,
            leadingIcon: entry.icon,
            onTap: () => onPick(entry.seed),
          ),
        SizedBox(height: AppSpacing.lg),
        Padding(
          padding: AppSpacing.pageH,
          child: Row(
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: context.c.textSecondary,
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.l10n.resultsComeLiveFromImo2,
                  style: context.t.bodySmall?.copyWith(
                    color: context.c.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The live result list.
///
/// Two shapes of query, two answers:
///
/// * a `@handle` can match many people, so it streams a range query;
/// * a phone number, email address or uid is an exact key, so the answer is one
///   person or nobody — and "nobody" is the invite case, which is why the exact
///   path is the only one that can show the invite prompt.
class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.kind});

  final String query;
  final DirectoryQueryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            context.l10n.searchingBy(DirectorySearchService.labelFor(kind)),
            style: context.t.bodySmall?.copyWith(
              color: context.c.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: kind == DirectoryQueryKind.username
              ? _handleResults(ref)
              : _exactResult(ref),
        ),
      ],
    );
  }

  /// Handle prefixes stream, because several people can share one.
  Widget _handleResults(WidgetRef ref) {
    final AsyncValue<List<RemoteProfile>> async =
        ref.watch(directorySearchProvider(query));

    return async.when(
      loading: () => const Center(child: ILoader(size: 26)),
      error: (Object error, StackTrace stack) => const _SearchUnavailable(),
      data: (List<RemoteProfile> profiles) => profiles.isEmpty
          ? _InvitePrompt(query: query, kind: kind)
          : _ProfileList(profiles: profiles, highlight: query),
    );
  }

  /// Exact identifiers resolve to at most one profile.
  ///
  /// [directoryLookupProvider] is used instead of the list stream because it
  /// reports *why* there is no result: a genuine miss becomes an invite prompt,
  /// while an unreachable Firestore becomes a neutral "try again" — a network
  /// blip must never be presented as "this person has no account".
  Widget _exactResult(WidgetRef ref) {
    final AsyncValue<LookupResult> async =
        ref.watch(directoryLookupProvider(query));

    return async.when(
      loading: () => const Center(child: ILoader(size: 26)),
      error: (Object error, StackTrace stack) => const _SearchUnavailable(),
      data: (LookupResult result) {
        final RemoteProfile? profile = result.profile;
        if (result.isFound && profile != null) {
          return _ProfileList(
            profiles: <RemoteProfile>[profile],
            highlight: query,
          );
        }
        if (result.isUnavailable) return const _SearchUnavailable();
        return _InvitePrompt(query: query, kind: kind);
      },
    );
  }
}

/// The shared result list.
class _ProfileList extends StatelessWidget {
  const _ProfileList({required this.profiles, required this.highlight});

  final List<RemoteProfile> profiles;
  final String highlight;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      itemCount: profiles.length,
      itemBuilder: (BuildContext context, int index) => _ProfileRow(
        profile: profiles[index],
        highlight: highlight,
      ),
    );
  }
}

/// Shown when Firestore could not be reached at all.
class _SearchUnavailable extends StatelessWidget {
  const _SearchUnavailable();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: context.l10n.searchUnavailable,
      message: context.l10n.imoLIVECouldNotBe2,
    );
  }
}

/// The "nobody has that identifier" state, with an Invite action.
///
/// This is the required behaviour for a number that is not registered: say so
/// plainly and offer the way forward, rather than a dead-end "no results".
class _InvitePrompt extends ConsumerWidget {
  const _InvitePrompt({required this.query, required this.kind});

  final String query;
  final DirectoryQueryKind kind;

  /// The number case is worded exactly as the spec requires; the others name
  /// the identifier the user actually typed.
  String get _headline => kind == DirectoryQueryKind.phone
      ? 'This number is not on Imo LIVE.'
      : 'This ${DirectorySearchService.labelFor(kind)} is not on Imo LIVE.';

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final String target = query.trim();
    final bool ok = await showConfirmDialog(
      context,
      title: context.l10n.inviteToImoLIVE,
      message: context.l10n.sendAnInviteToSo(target, AppConstants.appName),
      confirmLabel: context.l10n.invite,
    );
    if (!ok || !context.mounted) return;

    // Opens the platform share sheet with a ready-to-send message, so the
    // invite actually leaves the app instead of being a no-op toast.
    await ref.read(shareServiceProvider).shareText(
          'Hey! I\'m on ${AppConstants.appName}. Join me so we can chat: '
          'https://imolive.app/invite',
          subject: 'Join me on ${AppConstants.appName}',
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: <Widget>[
        const SizedBox(height: AppSpacing.xl),
        EmptyState(
          icon: Icons.person_add_alt_1_rounded,
          title: _headline,
          message: context.l10n.inviteThemToImoLIVE2,
          actionLabel: context.l10n.invite,
          onAction: () => _invite(context, ref),
        ),
      ],
    );
  }
}

/// One directory hit, with two distinct tap targets.
///
/// Tapping the picture opens the profile; tapping anywhere else starts a
/// conversation. A single `onTap` for the whole row made the picture
/// indistinguishable from the text, which is why the avatar owns its own
/// gesture.
class _ProfileRow extends ConsumerStatefulWidget {
  const _ProfileRow({required this.profile, required this.highlight});

  final RemoteProfile profile;
  final String highlight;

  @override
  ConsumerState<_ProfileRow> createState() => _ProfileRowState();
}

class _ProfileRowState extends ConsumerState<_ProfileRow> {
  bool _opening = false;

  RemoteProfile get _profile => widget.profile;

  /// Saves the person to the contact list and opens (or creates) the chat.
  Future<void> _openChat() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final String chatId = await ref
          .read(chatServiceProvider)
          .openDirectChat(
            contactId: _profile.uid,
            name: _profile.name.isEmpty ? _profile.handle : _profile.name,
            phone: _profile.phone,
            avatarUrl: _profile.avatarUrl,
            remoteUid: _profile.uid,
            username: _profile.username,
            bio: _profile.bio,
          );
      if (!mounted) return;
      context.push('${AppRoutes.chat}/$chatId');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openProfile() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final String contactId = await ref
          .read(chatServiceProvider)
          .saveDirectoryContact(_profile);
      if (!mounted) return;
      context.push('${AppRoutes.contactInfo}/$contactId');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title =
        _profile.name.isEmpty ? _profile.handle : _profile.name;
    final String subtitle = _profile.handle.isNotEmpty
        ? _profile.handle
        : _profile.phone.isNotEmpty
            ? _profile.phone
            : _profile.email;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: _opening ? null : _openChat,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              GestureDetector(
                onTap: _opening ? null : _openProfile,
                behavior: HitTestBehavior.opaque,
                child: IAvatar(
                  name: title,
                  imageUrl: _profile.avatarUrl.isEmpty ? null : _profile.avatarUrl,
                  size: AppSizes.avatarMd,
                  isOnline: _profile.isOnline,
                  showPresence: true,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_profile.isVerified) ...<Widget>[
                          const SizedBox(width: AppSpacing.xs),
                          Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: context.c.onInfo,
                          ),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...<Widget>[
                      SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.bodySmall?.copyWith(
                          color: context.c.accent,
                        ),
                      ),
                    ],
                    if (_profile.bio.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        _profile.bio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (_opening)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: AppIconSizes.sm,
                  color: context.c.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shared spinner used while an avatar uploads.
class DirectoryAvatar extends StatelessWidget {
  const DirectoryAvatar({super.key, required this.profile, this.size = 48});

  final RemoteProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IAvatar(
      name: profile.name.isEmpty ? profile.handle : profile.name,
      imageUrl: profile.avatarUrl.isEmpty ? null : profile.avatarUrl,
      size: size,
      isOnline: profile.isOnline,
      showPresence: true,
    );
  }
}
