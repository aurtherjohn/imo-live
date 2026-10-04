import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app.dart';
import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/group.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/contact_service.dart';
import '../../../core/services/media_service.dart';
import '../../../core/widgets/brand_assets.dart';
import '../../../core/widgets/camera_sheet.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../../local/database/local_database.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../earn/presentation/providers.dart';
import '../../misc/presentation/startup.dart';
import '../../misc/presentation/widgets/app_drawer.dart';
import '../../settings/presentation/widgets/chat_actions_sheet.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../channels/presentation/widgets/channel_chat_tile.dart';
import '../domain/chat_rows.dart';
import '../domain/remote_chats_sync.dart';
import 'providers.dart';
import 'widgets/chat_tile.dart';
import '../../../core/utils/l10n.dart';
import '../../../core/utils/haptics.dart';

/// The Chats tab — the app's home screen.
class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ChatFilter filter = ref.watch(chatFilterProvider);

    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _TopBar(
              onMenu: () => _scaffoldKey.currentState?.openDrawer(),
              onCamera: _openCameraSheet,
              onMore: _openMoreMenu,
            ),
            const _StorageWarningBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: ISearchBar(
                hint: context.l10n.searchNameHandlePhoneOr,
                controller: _searchController,
                onChanged: (String value) => setState(() => _query = value),
                // Opens the real-time directory search: phone, email, @handle
                // and uid all resolve against Firestore from one field.
                onTap: () => context.push(AppRoutes.directorySearch),
                readOnly: true,
                trailing: IAvatar(
                  name: ref.watch(selfProfileProvider).valueOrNull?.fullName ?? 'You',
                  imagePath: ref.watch(selfProfileProvider).valueOrNull?.avatarPath,
                  imageUrl: ref.watch(selfProfileProvider).valueOrNull?.avatarUrl,
                  size: 38,
                  isOnline: true,
                  showPresence: true,
                  onTap: () => context.push(AppRoutes.profile),
                ),
              ),
            ),
            _FilterChips(
              selected: filter,
              onSelect: (ChatFilter f) =>
                  ref.read(chatFilterProvider.notifier).select(f),
            ),

            // ------------------------------------------------------ the list
            // Driven by a `StreamBuilder` over the Firestore `chats`
            // collection (query: `participants` array-contains the signed-in
            // uid). Each snapshot is mirrored into the local store before it is
            // published, so a conversation created on another device — or by
            // saving a contact on this one — shows up here with no refresh.
            Expanded(
              child: StreamBuilder<List<Chat>>(
                stream: ref.watch(liveChatsStreamProvider),
                builder: (
                  BuildContext context,
                  AsyncSnapshot<List<Chat>> snapshot,
                ) {
                  // The local cache paints the first frame and covers the
                  // offline case, before Firestore's first snapshot lands.
                  final List<Chat> local =
                      ref.watch(chatsProvider).valueOrNull ?? <Chat>[];
                  final List<Chat> all = snapshot.data ?? local;

                  final List<Chat> visible = applyChatFilter(all, filter);
                  final List<Contact> contacts =
                      ref.watch(allContactsProvider);
                  final List<Chat> filtered = _query.trim().isEmpty
                      ? visible
                      : visible
                          .where((Chat c) => _matchesQuery(c, contacts))
                          .toList();

                  // -------------------------------------------------------
                  // The merged list.
                  //
                  // Channels are folded in here rather than given their own
                  // section, so the list is genuinely "everything that
                  // happened", newest first — which is what a chat list
                  // promises. The direct/group filter still governs the
                  // conversation half; a channel is shown under `all`.
                  // -------------------------------------------------------
                  final List<Channel> channels =
                      filter == ChatFilter.all || filter == ChatFilter.groups
                          ? ref.watch(chatListChannelsProvider)
                          : const <Channel>[];

                  final List<Channel> filteredChannels =
                      _query.trim().isEmpty
                          ? channels
                          : channels
                              .where((Channel ch) =>
                                  ch.name.toLowerCase().contains(
                                        _query.trim().toLowerCase(),
                                      ) ||
                                  ch.username.toLowerCase().contains(
                                        _query.trim().toLowerCase(),
                                      ))
                              .toList();

                  final List<ChatRow> rows = mergeChatRows(
                    chats: filtered,
                    channels: filteredChannels,
                  );

                  final int archivedCount =
                      all.where((Chat c) => c.isArchived).length;

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData &&
                      local.isEmpty) {
                    return const ChatListSkeleton();
                  }

                  return Column(
                    children: <Widget>[
                      if (archivedCount > 0 && filter == ChatFilter.all)
                        _ArchivedRow(count: archivedCount),
                      Expanded(
                        child: rows.isEmpty
                            ? _EmptyChats(
                                filter: filter,
                                hasQuery: _query.isNotEmpty,
                              )
                            : RefreshIndicator(
                                color: context.c.accent,
                                backgroundColor: context.c.card,
                                onRefresh: _refresh,
                                child: ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 96),
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  itemCount: rows.length,
                                  itemBuilder:
                                      (BuildContext context, int index) {
                                    final ChatRow row = rows[index];
                                    return ListStagger(
                                      key: ValueKey<String>(row.rowKey),
                                      index: index,
                                      offset: 8,
                                      child: switch (row) {
                                        ChatRowConversation(:final Chat chat) =>
                                          ChatTile(
                                            chat: chat,
                                            onTap: () => _openConversation(chat),
                                            // Avatar → the person's profile;
                                            // the rest of the row → the chat.
                                            onAvatarTap: () =>
                                                _openProfileFor(chat),
                                            onLongPress: () {
                                              Haptics.tap();
                                              showChatActionsSheet(
                                                context,
                                                ref,
                                                chat,
                                              );
                                            },
                                          ),
                                        ChatRowChannel(:final Channel channel) =>
                                          ChannelChatTile(
                                            channel: channel,
                                            onTap: () =>
                                                _openChannel(channel),
                                            onLongPress: () {
                                              Haptics.tap();
                                              _showChannelActions(channel);
                                            },
                                          ),
                                      },
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      // Always available — a brand-new install has an empty list, which is
      // exactly when the user most needs a way to start a conversation.
      floatingActionButton: _query.trim().isEmpty
          ? FloatingActionButton(
              onPressed: _openNewChatSheet,
              backgroundColor: context.c.accent,
              foregroundColor: Colors.white,
              elevation: 3,
              child: const Icon(Icons.add_comment_rounded, size: 24),
            )
          : null,
    );
  }

  /// Whether a chat row matches the search box.
  ///
  /// A person is findable by the identifiers the user actually knows them by —
  /// their name, their phone number, their `@handle` — not only by the name
  /// printed on the row. That is what makes a contact saved seconds ago
  /// searchable here straight away.
  bool _matchesQuery(Chat chat, List<Contact> contacts) {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    if (chat.title.toLowerCase().contains(query)) return true;
    if (chat.lastMessage.toLowerCase().contains(query)) return true;

    final String handle = query.replaceAll('@', '');
    final String digits = query.replaceAll(RegExp(r'[^0-9]'), '');

    for (final Contact contact in contacts) {
      final bool belongsToChat = chat.memberIds.contains(contact.id) ||
          contact.fullName.toLowerCase() == chat.title.toLowerCase();
      if (!belongsToChat) continue;

      if (handle.isNotEmpty &&
          contact.username.toLowerCase().contains(handle)) {
        return true;
      }
      if (digits.length >= 4 &&
          contact.phone
              .replaceAll(RegExp(r'[^0-9]'), '')
              .contains(digits)) {
        return true;
      }
    }
    return false;
  }

  /// Re-reads the local cache and re-subscribes to the Firestore stream.
  ///
  /// Invalidating [liveChatsStreamProvider] is what makes a pull-to-refresh
  /// actually re-query `chats`; refreshing the local notifier alone would only
  /// re-read the cache the stream had already filled.
  Future<void> _refresh() async {
    ref.invalidate(liveChatsStreamProvider);
    await ref.read(chatsProvider.notifier).refresh();
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  /// Opens the camera (or the gallery) and posts the result as a status.
  ///
  /// Previously this only pushed the status composer, so tapping the header
  /// camera icon never touched the device camera at all — the single most
  /// reported defect in the app.
  Future<void> _openCameraSheet() async {
    final CameraSource? source = await showCameraSourceSheet(context);
    if (source == null || !mounted) return;

    final MediaService media = ref.read(mediaServiceProvider);

    if (source == CameraSource.gallery) {
      if (mounted) context.push(AppRoutes.statusCompose);
      return;
    }

    final MediaPickResult result = await media.capturePhoto();
    if (!mounted) return;

    if (result.hasError) {
      showMediaErrorSnack(
        context,
        result,
        onOpenSettings: () => ref.read(permissionServiceProvider).openSettings(),
      );
      return;
    }
    // A null attachment without an error means the user backed out of the
    // camera — nothing to report.
    if (result.isEmpty) return;

    final String? path = result.attachments.first.localPath;
    if (path == null) {
      iToast(context, context.l10n.couldNotReadTheCaptured, isError: true);
      return;
    }
    context.push(
      Uri(
        path: AppRoutes.statusCompose,
        queryParameters: <String, String>{'media': path},
      ).toString(),
    );
  }

  /// The home (+) action: start a contact, channel or community, or jump
  /// straight into a conversation with someone from the device address book.
  Future<void> _openNewChatSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (BuildContext sheetContext) => _NewChatSheet(
        onNewContact: () => context.push(AppRoutes.newContact),
        onNewChannel: () => context.push(AppRoutes.newChannel),
        onNewCommunity: () => context.push(AppRoutes.newCommunity),
      ),
    );
  }

  /// Opens a conversation from the merged list.
  ///
  /// The ad trigger is fired here rather than inside [ChatTile] so the tile
  /// stays a presentational widget. Deliberately not awaited: opening a
  /// conversation must never wait on an ad load.
  void _openConversation(Chat chat) {
    ref.read(chatsProvider.notifier).markRead(chat.id);
    unawaited(
      ref.read(adServiceProvider).noteAndMaybeShow(AdTrigger.chatsOpened),
    );
    context.push('/chat/${chat.id}');
  }

  /// Opens a channel as a conversation.
  void _openChannel(Channel channel) {
    unawaited(
      ref.read(adServiceProvider).noteAndMaybeShow(AdTrigger.chatsOpened),
    );
    context.push('${AppRoutes.channelChat}/${channel.id}');
  }

  /// Long-press actions for a channel row.
  ///
  /// Deliberately a shorter menu than a conversation's: a channel has no
  /// archive, no pin and no "mark unread" in this app, and offering actions
  /// that do nothing is how a list starts feeling broken. Mute, follow and
  /// open-info are the three that exist.
  Future<void> _showChannelActions(Channel channel) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: Text(sheetContext.l10n.openChannel),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openChannel(channel);
              },
            ),
            ListTile(
              leading: Icon(
                channel.isMuted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
              ),
              title: Text(
                channel.isMuted
                    ? sheetContext.l10n.unmute
                    : sheetContext.l10n.mute,
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await ref
                    .read(channelsProvider.notifier)
                    .toggleMute(channel.id);
              },
            ),
            ListTile(
              leading: Icon(
                channel.isFollowing
                    ? Icons.person_remove_outlined
                    : Icons.person_add_outlined,
              ),
              title: Text(
                channel.isFollowing
                    ? sheetContext.l10n.unfollow
                    : sheetContext.l10n.follow,
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await ref
                    .read(channelsProvider.notifier)
                    .toggleFollow(channel.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(sheetContext.l10n.channelInfo),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('${AppRoutes.channel}/${channel.id}');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the profile behind a chat row.
  ///
  /// The peer is the *other* uid in `memberIds`. [Chat.id] is a composite
  /// (`uidA_uidB`) for direct chats, so passing it here is exactly what produced
  /// "User Not Found": `users/{uidA_uidB}` does not exist. Groups, channels and
  /// broadcasts have no single person and fall through to the chat itself.
  void _openProfileFor(Chat chat) {
    if (!chat.isDirect) {
      context.push('${AppRoutes.chat}/${chat.id}');
      return;
    }
    final String? peerUid = chat.peerUid(ref.read(currentUidProvider));
    if (peerUid == null) {
      // No resolvable peer (e.g. a chat mirrored before members were recorded).
      // Opening the conversation is honest; a contact page cannot be built.
      context.push('${AppRoutes.chat}/${chat.id}');
      return;
    }
    context.push('${AppRoutes.contactInfo}/$peerUid');
  }

  Future<void> _openMoreMenu() async {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => ChatMoreMenu(
        onNewGroup: () => context.push(AppRoutes.newGroup),
        onNewBroadcast: () => context.push(AppRoutes.broadcast),
        onLinkedDevices: () => context.push(AppRoutes.linkedDevices),
        onStarred: () => context.push(AppRoutes.starred),
        onReadAll: () {
          ref.read(chatsProvider.notifier).markAllRead();
          _toast('All chats marked as read');
        },
        onSettings: () => context.push(AppRoutes.settings),
      ),
    );
  }

  void _toast(String message) => iToast(context, message);
}

/// Warns that local storage could not be opened.
///
/// `startupFailedProvider` was previously set but never read, so a device whose
/// Hive boxes failed to open silently showed an empty chat list — the user had
/// no way to tell "no messages yet" from "your messages cannot be read". The
/// banner also offers a retry, which re-attempts the boxes that are missing.
class _StorageWarningBanner extends ConsumerStatefulWidget {
  const _StorageWarningBanner();

  @override
  ConsumerState<_StorageWarningBanner> createState() =>
      _StorageWarningBannerState();
}

class _StorageWarningBannerState extends ConsumerState<_StorageWarningBanner> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      final bool recovered = await LocalDatabase.instance.retryUnavailable();
      ref.read(storageReadyStateProvider.notifier).state = recovered;
      if (recovered) {
        ref.invalidate(startupFailedProvider);
        ref.invalidate(chatsProvider);
        ref.invalidate(contactsProvider);
        ref.invalidate(groupsProvider);
      }
      if (mounted) {
        iToast(
          context,
          recovered
              ? 'Local storage is working again'
              : 'Storage is still unavailable',
          isError: !recovered,
        );
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(startupFailedProvider)) return const SizedBox.shrink();

    return Stack(
      children: <Widget>[
        InfoBanner(
          message: context.l10n.localStorageCouldNotBe2,
          icon: Icons.sd_card_alert_outlined,
          color: context.c.onWarning,
        ),
        Positioned(
          right: AppSpacing.lg + AppSpacing.sm,
          top: AppSpacing.md + AppSpacing.xs,
          child: TextButton(
            onPressed: _retrying ? null : _retry,
            child: Text(_retrying ? 'Retrying…' : 'Retry'),
          ),
        ),
      ],
    );
  }
}

/// Header row: menu, title, camera, more.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onMenu,
    required this.onCamera,
    required this.onMore,
  });

  final VoidCallback onMenu;
  final VoidCallback onCamera;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    // The bar grows with the text scale instead of pinning to a fixed height,
    // which overflowed once accessibility text scaling pushed the title past
    // 58dp. `constraints` keeps the design height as a minimum.
    final double height = AppSizes.topBarHeight *
        MediaQuery.textScalerOf(context).scale(1);

    return SizedBox(
      height: height,
      child: Row(
        children: <Widget>[
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            onPressed: onMenu,
            icon: const Icon(Icons.menu_rounded),
            tooltip: context.l10n.menu,
          ),
          // Text-only wordmark, by request. The logo used to sit beside it, but
          // the mark plus the name read as two competing brand elements in a
          // 58dp bar. The rest of the app keeps its branding (splash, auth,
          // About, the QR plate); only this header is wordmark-only.
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              AppConstants.appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          IconButton(
            onPressed: onCamera,
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: context.l10n.camera,
          ),
          IconButton(
            onPressed: onMore,
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: context.l10n.moreOptions,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
    );
  }
}

/// Horizontally scrollable filter chips.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});

  final ChatFilter selected;
  final ValueChanged<ChatFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: ChatFilter.values.map((ChatFilter filter) {
          final bool isSelected = filter == selected;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: Text(filter.label),
              selected: isSelected,
              onSelected: (_) => onSelect(filter),
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? context.c.accent : context.c.textSecondary,
              ),
              backgroundColor: context.c.surfaceAlt,
              selectedColor: context.c.accent.withValues(alpha: 0.16),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.rPill),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Row linking to archived chats.
class _ArchivedRow extends ConsumerWidget {
  const _ArchivedRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => context.push(AppRoutes.archived),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md - 2,
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 40,
              child: Icon(
                Icons.archive_rounded,
                size: AppIconSizes.md,
                color: context.c.accent,
              ),
            ),
            Expanded(
              child: Text(
                context.l10n.archived,
                style: context.t.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              '$count',
              style: context.t.bodySmall?.copyWith(color: context.c.accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right_rounded,
              size: AppIconSizes.md,
              color: context.c.textSecondary.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state that adapts to the active filter.
class _EmptyChats extends ConsumerWidget {
  const _EmptyChats({required this.filter, required this.hasQuery});

  final ChatFilter filter;
  final bool hasQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hasQuery) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: context.l10n.noChatsFound,
        message: context.l10n.tryADifferentNameOr,
      );
    }

    final (IconData icon, String title, String message) = switch (filter) {
      ChatFilter.all => (
          Icons.chat_bubble_outline_rounded,
          context.l10n.noChatsYet,
          context.l10n.noChatsMessage,
        ),
      ChatFilter.unread => (
          Icons.mark_chat_read_outlined,
          context.l10n.emptyChatsUnreadTitle,
          context.l10n.emptyChatsUnreadMessage,
        ),
      ChatFilter.favorites => (
          Icons.star_border_rounded,
          context.l10n.emptyChatsFavoritesTitle,
          context.l10n.emptyChatsFavoritesMessage,
        ),
      ChatFilter.groups => (
          Icons.groups_outlined,
          context.l10n.emptyChatsGroupsTitle,
          context.l10n.emptyChatsGroupsMessage,
        ),
      ChatFilter.work => (
          Icons.work_outline_rounded,
          context.l10n.emptyChatsWorkTitle,
          context.l10n.emptyChatsWorkMessage,
        ),
    };

    return EmptyState(
      // A brand-new install lands on `all`, so that is the one empty state that
      // carries the logo instead of a themed glyph. The filter-specific states
      // keep their own iconography — six identical logos would tell the user
      // nothing about why the list is empty.
      imageAsset: filter == ChatFilter.all ? BrandAssets.logo : null,
      icon: icon,
      title: title,
      message: message,
      actionLabel: filter == ChatFilter.all ? context.l10n.startAChat : null,
      onAction: filter == ChatFilter.all
          ? () => context.push(AppRoutes.selectContact)
          : null,
    );
  }
}

/// The sheet behind the home (+) button.
///
/// Three creation shortcuts up top (contact, channel, community), then the
/// device address book so the user can start a conversation with someone they
/// already know without leaving the sheet.
class _NewChatSheet extends ConsumerStatefulWidget {
  const _NewChatSheet({
    required this.onNewContact,
    required this.onNewChannel,
    required this.onNewCommunity,
  });

  final VoidCallback onNewContact;
  final VoidCallback onNewChannel;
  final VoidCallback onNewCommunity;

  @override
  ConsumerState<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<_NewChatSheet> {
  final TextEditingController _search = TextEditingController();
  List<Contact> _deviceContacts = <Contact>[];
  bool _loading = true;
  bool _denied = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final DeviceContactService service = ref.read(deviceContactServiceProvider);
    List<Contact> found = <Contact>[];
    try {
      found = await service.read();
    } on Object {
      found = <Contact>[];
    }
    if (!mounted) return;
    setState(() {
      _deviceContacts = found;
      _denied = found.isEmpty;
      _loading = false;
    });
  }

  void _openChat(Contact contact) {
    // Reuse an existing chat for this person when there is one, so the sheet
    // never creates a duplicate conversation for the same contact.
    final List<Chat> chats = ref.read(chatsProvider).orEmpty;
    final Chat? existing = chats
        .where((Chat c) =>
            !c.isGroup &&
            (c.id == contact.id ||
                (contact.phone.isNotEmpty && c.id.endsWith(contact.phone))))
        .firstOrNull;

    Navigator.pop(context);
    if (existing != null) {
      context.push('${AppRoutes.chat}/${existing.id}');
      return;
    }
    // No conversation yet: hand off to the contact profile, where "Message"
    // creates it. Creating the chat row here would leave an empty chat behind
    // if the user changed their mind and never sent anything.
    context.push('${AppRoutes.contactInfo}/${contact.id}');
  }

  @override
  Widget build(BuildContext context) {
    final List<Contact> filtered = _query.trim().isEmpty
        ? _deviceContacts
        : _deviceContacts
            .where((Contact c) =>
                c.fullName.toLowerCase().contains(_query.toLowerCase()) ||
                c.phone.contains(_query))
            .toList();

    return FractionallySizedBox(
      heightFactor: 0.82,
      child: Column(
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.c.divider,
              borderRadius: AppRadius.rPill,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(context.l10n.newChat, style: context.t.titleMedium),
            ),
          ),

          // ------------------------------------------------ creation shortcuts
          SettingsTile(
            title: context.l10n.newContact,
            subtitle: context.l10n.saveSomeoneToThisDevice,
            leadingIcon: Icons.person_add_alt_1_rounded,
            leadingIconColor: context.c.accent,
            onTap: () {
              Navigator.pop(context);
              widget.onNewContact();
            },
          ),
          SettingsTile(
            title: context.l10n.newChannel,
            subtitle: context.l10n.broadcastToAnUnlimitedAudience,
            leadingIcon: Icons.campaign_rounded,
            leadingIconColor: context.c.accent,
            onTap: () {
              Navigator.pop(context);
              widget.onNewChannel();
            },
          ),
          SettingsTile(
            title: context.l10n.newCommunity,
            subtitle: context.l10n.groupRelatedChatsTogether,
            leadingIcon: Icons.groups_rounded,
            leadingIconColor: context.c.accent,
            onTap: () {
              Navigator.pop(context);
              widget.onNewCommunity();
            },
          ),

          const Divider(height: 1),

          // ------------------------------------------------- device contacts
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.contactsOnThisDevice,
                style: context.t.labelMedium?.copyWith(
                  color: context.c.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: ISearchBar(
              hint: context.l10n.searchContacts,
              controller: _search,
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: ILoader(size: 24))
                : filtered.isEmpty
                    ? EmptyState(
                        icon: _denied
                            ? Icons.contacts_outlined
                            : Icons.person_search_rounded,
                        title: _denied
                            ? 'No contacts to show'
                            : 'No matches',
                        message: _denied
                            ? 'Allow contacts access to see the people already '
                                'saved on your phone, or create a new contact.'
                            : 'Nothing matched "$_query".',
                        compact: true,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        itemCount: filtered.length,
                        itemBuilder: (BuildContext context, int i) {
                          final Contact contact = filtered[i];
                          return ListTile(
                            leading: IAvatar(
                              name: contact.fullName,
                              imagePath: contact.avatarPath,
                              colorSeed: contact.avatarColor,
                              size: AppSizes.avatarSm + 8,
                            ),
                            title: Text(
                              contact.fullName,
                              style: context.t.bodyLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: contact.phone.isEmpty
                                ? null
                                : Text(
                                    contact.phone,
                                    style: context.t.bodySmall?.copyWith(
                                      color: context.c.textSecondary,
                                    ),
                                  ),
                            trailing: Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: AppIconSizes.sm,
                              color: context.c.accent,
                            ),
                            onTap: () => _openChat(contact),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// The Chats top-right menu.
class ChatMoreMenu extends StatelessWidget {
  const ChatMoreMenu({
    super.key,
    required this.onNewGroup,
    required this.onNewBroadcast,
    required this.onLinkedDevices,
    required this.onStarred,
    required this.onReadAll,
    required this.onSettings,
  });

  final VoidCallback onNewGroup;
  final VoidCallback onNewBroadcast;
  final VoidCallback onLinkedDevices;
  final VoidCallback onStarred;
  final VoidCallback onReadAll;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    void close(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.c.divider,
              borderRadius: AppRadius.rPill,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SettingsTile(
            title: context.l10n.newGroup,
            leadingIcon: Icons.group_add_outlined,
            onTap: () => close(onNewGroup),
          ),
          SettingsTile(
            title: context.l10n.newBroadcast,
            leadingIcon: Icons.podcasts_rounded,
            onTap: () => close(onNewBroadcast),
          ),
          SettingsTile(
            title: context.l10n.linkedDevices,
            leadingIcon: Icons.devices_rounded,
            onTap: () => close(onLinkedDevices),
          ),
          SettingsTile(
            title: context.l10n.starredMessages,
            leadingIcon: Icons.star_border_rounded,
            onTap: () => close(onStarred),
          ),
          SettingsTile(
            title: context.l10n.readAll,
            leadingIcon: Icons.done_all_rounded,
            onTap: () => close(onReadAll),
          ),
          SettingsTile(
            title: context.l10n.settings,
            leadingIcon: Icons.settings_outlined,
            onTap: () => close(onSettings),
            showDivider: false,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

