import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/chat.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/status.dart';
import '../../../core/services/remote_contact_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../chats/domain/chat_service.dart';
import '../../chats/presentation/providers.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import 'dialogs/confirm_dialog.dart';
import '../../../core/utils/l10n.dart';

/// A contact's profile page: details, media, and every action you can take.
class ContactInfoScreen extends ConsumerStatefulWidget {
  const ContactInfoScreen({super.key, required this.contactId});

  final String contactId;

  @override
  ConsumerState<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends ConsumerState<ContactInfoScreen> {
  /// Guards the one-shot mirror of a directory profile into the address book,
  /// so a rebuild storm cannot queue the same write repeatedly.
  bool _mirrored = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Contact?> contactAsync =
        ref.watch(contactByIdProvider(widget.contactId));

    return contactAsync.when(
      loading: () => const Scaffold(body: Center(child: ILoader(size: 26))),
      error: (Object e, StackTrace s) => Scaffold(
        appBar: AppTopBar(title: context.l10n.contact, showBack: true),
        body: errorStateFor(context, e),
      ),
      data: (Contact? contact) {
        if (contact != null) return _buildBody(contact);
        return _buildFromDirectory();
      },
    );
  }

  /// Fallback for a person who is not in the local address book yet.
  ///
  /// "Not saved on this device" is not the same as "does not exist": a chat
  /// opened from search, a chat row mirrored from another device, or a fresh
  /// install all reach this screen with no local contact row. The profile is
  /// then read from Firestore `users/{uid}` — the same document the search
  /// indexes point at — and cached locally so every later visit is instant and
  /// the contact-list actions have a row to act on.
  Widget _buildFromDirectory() {
    final AsyncValue<RemoteProfile?> remote =
        ref.watch(remoteProfileProvider(widget.contactId));

    return remote.when(
      loading: () => const Scaffold(body: Center(child: ILoader(size: 26))),
      error: (Object e, StackTrace s) => _notFound(),
      data: (RemoteProfile? profile) {
        if (profile == null) return _notFound();

        if (!_mirrored) {
          _mirrored = true;
          // Fire-and-forget: the screen renders from the directory profile
          // immediately, and the local row appears a frame later.
          unawaited(
            ref.read(chatServiceProvider).saveDirectoryContact(profile),
          );
        }
        return _buildBody(_contactFrom(profile));
      },
    );
  }

  Widget _notFound() => Scaffold(
        appBar: AppTopBar(title: context.l10n.contact, showBack: true),
        body: EmptyState(
          icon: Icons.person_off_outlined,
          title: context.l10n.contactNotFound,
          message:
              context.l10n.thisPersonIsNotIn2,
        ),
      );

  /// Presents a directory profile using the same [Contact] shape the rest of
  /// this screen already renders.
  Contact _contactFrom(RemoteProfile profile) {
    final List<String> parts = profile.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    return Contact(
      id: profile.uid,
      firstName: parts.isEmpty
          ? (profile.username.isNotEmpty ? profile.username : profile.phone)
          : parts.first,
      lastName: parts.length > 1 ? parts.skip(1).join(' ') : '',
      username: profile.username,
      phone: profile.phone,
      bio: profile.bio,
      avatarUrl: profile.avatarUrl,
      isOnline: profile.isOnline,
      lastSeen: profile.lastSeen,
    );
  }

  Widget _buildBody(Contact contact) {
    final List<Chat> chats = ref.watch(chatsProvider).orEmpty;
    // Match on membership first: the title is a display string and can be
    // edited, whereas `memberIds` carries the contact's stable id.
    final Chat? chat = chats
        .where(
          (Chat c) =>
              !c.isGroup &&
              !c.isChannel &&
              (c.memberIds.contains(contact.id) ||
                  c.title.toLowerCase() == contact.fullName.toLowerCase()),
        )
        .firstOrNull;

    final List<Status> statuses = ref.watch(statusesProvider).orEmpty;
    final int statusCount =
        statuses.where((Status s) => s.authorId == contact.id).length;

    return Scaffold(
      appBar: AppTopBar(
        title: context.l10n.contactInfo,
        showBack: true,
        actions: <Widget>[
          TopBarAction(
            icon: Icons.edit_outlined,
            tooltip: context.l10n.editContact,
            onPressed: () => context.push(
              '${AppRoutes.newContact}?id=${contact.id}',
            ),
          ),
          TopBarAction(
            icon: Icons.more_vert_rounded,
            tooltip: context.l10n.more,
            onPressed: () => _showActions(contact, chat),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Column(
              children: <Widget>[
                GestureDetector(
                  onTap: () => _openPhoto(contact),
                  child: IAvatar(
                    name: contact.fullName,
                    imagePath: contact.avatarPath,
                    imageUrl: contact.avatarUrl,
                    colorSeed: contact.avatarColor,
                    size: AppSizes.avatarXxl,
                    isOnline: contact.isOnline,
                    showPresence: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  contact.fullName,
                  style: context.t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (contact.username.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '@${contact.username}',
                    style: context.t.bodyMedium?.copyWith(
                      color: context.c.accent,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  contact.presenceLabel,
                  style: context.t.bodySmall?.copyWith(
                    color: contact.isOnline
                        ? context.c.online
                        : context.c.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ------------------------------------------------------ action row
          Padding(
            padding: AppSpacing.pageH,
            child: Row(
              children: <Widget>[
                _Action(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: context.l10n.message,
                  onTap: () => _openChat(contact, chat),
                ),
                _Action(
                  icon: Icons.call_outlined,
                  label: context.l10n.call,
                  onTap: () => context.push(
                    '${AppRoutes.call}?id=${contact.id}'
                    '&name=${Uri.encodeComponent(contact.fullName)}',
                  ),
                ),
                _Action(
                  icon: Icons.videocam_outlined,
                  label: context.l10n.video,
                  onTap: () => context.push(
                    '${AppRoutes.call}?id=${contact.id}'
                    '&name=${Uri.encodeComponent(contact.fullName)}&video=true',
                  ),
                ),
                _Action(
                  icon: Icons.search_rounded,
                  label: context.l10n.search,
                  onTap: () => context.push(AppRoutes.globalSearch),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          SettingsGroup(
            title: context.l10n.about,
            children: <Widget>[
              SettingsTile(
                title: contact.aboutText,
                subtitle: context.l10n.about,
                leadingIcon: Icons.info_outline_rounded,
                onTap: () async {
                  final String? next = await showTextPrompt(
                    context,
                    title: context.l10n.about,
                    initialValue: contact.bio,
                    hint: contact.aboutText,
                    confirmLabel: context.l10n.save,
                    maxLength: 140,
                  );
                  if (next == null || !mounted) return;
                  await ref
                      .read(contactsProvider.notifier)
                      .persist(contact.copyWith(bio: next.trim()));
                  if (mounted) iToast(context, context.l10n.aboutUpdated);
                },
              ),
              SettingsValueRow(
                label: context.l10n.phone,
                value: contact.phone.isEmpty ? 'Not set' : contact.phone,
                leadingIcon: Icons.phone_outlined,
                onTap: contact.phone.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: contact.phone),
                        );
                        if (mounted) iToast(context, context.l10n.phoneNumberCopied);
                      },
              ),
              SettingsValueRow(
                label: context.l10n.country,
                value: contact.countryCode.isEmpty
                    ? 'Not set'
                    : '${contact.countryIso} ${contact.countryCode}',
                leadingIcon: Icons.public_rounded,
              ),
              SettingsValueRow(
                label: context.l10n.favourites,
                value: contact.isFavorite ? 'Yes' : 'No',
                leadingIcon: Icons.star_border_rounded,
                onTap: () async {
                  await ref
                      .read(contactsProvider.notifier)
                      .toggleFavorite(contact.id);
                  if (mounted) {
                    iToast(
                      context,
                      contact.isFavorite
                          ? context.l10n.removedFromFavourites
                          : context.l10n.addedToFavourites,
                    );
                  }
                },
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.mediaActivity,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.mediaLinksAndDocs,
                value: '${chat == null ? 0 : 1} chat',
                leadingIcon: Icons.photo_library_outlined,
                onTap: () => showInfoDialog(
                  context,
                  title: context.l10n.sharedMedia,
                  message:
                      context.l10n.mediaAttachesToConversationsOpen2,
                ),
              ),
              SettingsValueRow(
                label: context.l10n.statusUpdates,
                value: statusCount == 0 ? 'None' : '$statusCount',
                leadingIcon: Icons.donut_large_rounded,
                onTap: statusCount == 0
                    ? null
                    : () => context.push(
                          '${AppRoutes.statusView}/${contact.id}',
                        ),
              ),
              SettingsValueRow(
                label: context.l10n.starredMessages,
                value: '${ref.watch(starCountProvider)}',
                leadingIcon: Icons.star_border_rounded,
                onTap: () => context.push(AppRoutes.starred),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.privacy,
            children: <Widget>[
              SettingsSwitchRow(
                title: contact.isBlocked ? context.l10n.blocked3 : context.l10n.blockContact,
                subtitle: contact.isBlocked
                    ? context.l10n.thisContactCannotMessageOr
                    : context.l10n.stopThisContactFromReaching,
                value: contact.isBlocked,
                onChanged: (bool v) async {
                  await ref
                      .read(contactsProvider.notifier)
                      .toggleBlocked(contact.id);
                  if (mounted) {
                    iToast(
                      context,
                      v ? '${contact.fullName} blocked' : context.l10n.contactUnblocked,
                    );
                  }
                },
              ),
              SettingsSwitchRow(
                title: context.l10n.notifications,
                subtitle: context.l10n.muteAlertsForThisConversation,
                value: chat?.isMuted ?? false,
                enabled: chat != null,
                onChanged: chat == null
                    ? null
                    : (bool v) async {
                        await ref
                            .read(chatsProvider.notifier)
                            .toggleMute(chat.id);
                        if (mounted) {
                          iToast(context, v ? context.l10n.muted : context.l10n.unmuted);
                        }
                      },
              ),
              SettingsValueRow(
                label: context.l10n.disappearingMessages,
                value: chat == null
                    ? 'No chat'
                    : chat.disappearingSeconds == 0
                        ? 'Off'
                        : DateFormatter.longDuration(
                            Duration(seconds: chat.disappearingSeconds),
                          ),
                leadingIcon: Icons.timer_outlined,
                onTap: chat == null
                    ? null
                    : () => showInfoDialog(
                          context,
                          title: context.l10n.disappearingMessages,
                          message:
                              context.l10n.openTheChatAndChoose2,
                        ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.dangerZone,
            children: <Widget>[
              if (chat != null)
                SettingsTile(
                  title: context.l10n.deleteChat,
                  subtitle: context.l10n.removesThisConversationAndIts,
                  leadingIcon: Icons.delete_outline_rounded,
                  leadingIconColor: context.c.onDanger,
                  titleColor: context.c.onDanger,
                  onTap: () async {
                    final bool ok = await showConfirmDialog(
                      context,
                      title: context.l10n.deleteChat2,
                      message:
                          context.l10n.theWholeConversationWithAnd(contact.fullName),
                      confirmLabel: context.l10n.delete,
                      destructive: true,
                    );
                    if (!ok || !mounted) return;
                    await ref.read(chatsProvider.notifier).deleteChat(chat.id);
                    if (mounted) iToast(context, context.l10n.chatDeleted);
                  },
                ),
              SettingsTile(
                title: context.l10n.deleteContact,
                subtitle: context.l10n.removesFromYourContactList(contact.fullName),
                leadingIcon: Icons.person_remove_outlined,
                leadingIconColor: context.c.onDanger,
                titleColor: context.c.onDanger,
                onTap: () async {
                  final bool ok = await showConfirmDialog(
                    context,
                    title: context.l10n.delete4(contact.fullName),
                    message:
                        context.l10n.theContactIsRemovedFrom2,
                    confirmLabel: context.l10n.delete,
                    destructive: true,
                  );
                  if (!ok || !mounted) return;
                  await ref.read(contactsProvider.notifier).remove(contact.id);
                  if (mounted) {
                    iToast(context, context.l10n.contactDeleted);
                    if (context.canPop()) context.pop();
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  void _openChat(Contact contact, Chat? chat) {
    if (chat != null) {
      context.push('${AppRoutes.chat}/${chat.id}');
      return;
    }
    _createChat(contact);
  }

  /// Opens (or creates) the 1:1 conversation with this contact.
  ///
  /// Routed through [ChatService.openDirectChat] rather than building a [Chat]
  /// here, so the id is the deterministic `uidA_uidB` value and the Firestore
  /// `chats/{chatId}` document is created alongside the local row. A hand-rolled
  /// `chat_${id}` id would produce a conversation that only ever existed on this
  /// device.
  Future<void> _createChat(Contact contact) async {
    final String chatId = await ref.read(chatServiceProvider).openDirectChat(
          contactId: contact.id,
          name: contact.fullName,
          phone: contact.phone,
          avatarPath: contact.avatarPath ?? '',
          username: contact.username,
          bio: contact.bio,
        );
    if (!mounted || chatId.isEmpty) return;
    context.push('${AppRoutes.chat}/$chatId');
  }

  void _showActions(Contact contact, Chat? chat) {
    showActionSheet(
      context,
      title: contact.fullName,
      actions: <({IconData icon, String label, VoidCallback onTap, Color? color})>[
        (
          icon: Icons.share_outlined,
          label: context.l10n.shareContact,
          onTap: () {
            Navigator.pop(context);
            // A contact card is text, not a file: the recipient can read it
            // anywhere, and it needs no storage permission to produce.
            final String handle = contact.username.isNotEmpty
                ? '\n@${contact.username}'
                : '';
            final String number =
                contact.phone.isNotEmpty ? '\n${contact.phone}' : '';
            ref.read(shareServiceProvider).shareText(
                  '${contact.fullName}$handle$number',
                  subject: contact.fullName,
                );
          },
          color: null,
        ),
        (
          icon: Icons.favorite_border_rounded,
          label: contact.isFavorite
              ? context.l10n.removeFromFavourites
              : context.l10n.addToFavourites,
          onTap: () async {
            Navigator.pop(context);
            await ref
                .read(contactsProvider.notifier)
                .toggleFavorite(contact.id);
            if (mounted) {
              iToast(
                context,
                contact.isFavorite
                    ? context.l10n.removedFromFavourites
                    : context.l10n.addedToFavourites,
              );
            }
          },
          color: null,
        ),
        (
          icon: Icons.copy_rounded,
          label: context.l10n.copyPhoneNumber,
          onTap: () async {
            Navigator.pop(context);
            await Clipboard.setData(ClipboardData(text: contact.phone));
            if (mounted) iToast(context, context.l10n.phoneNumberCopied);
          },
          color: null,
        ),
        (
          icon: Icons.qr_code_rounded,
          label: context.l10n.showQRCode,
          onTap: () {
            Navigator.pop(context);
            context.push(
              '${AppRoutes.qr}?title=${Uri.encodeComponent(contact.fullName)}'
              '&payload=${Uri.encodeComponent('imo://user/${contact.id}')}',
            );
          },
          color: null,
        ),
        (
          icon: Icons.block_rounded,
          label: contact.isBlocked ? context.l10n.unblock : context.l10n.block,
          onTap: () async {
            Navigator.pop(context);
            await ref
                .read(contactsProvider.notifier)
                .toggleBlocked(contact.id);
            if (mounted) {
              iToast(
                context,
                contact.isBlocked ? context.l10n.contactUnblocked : context.l10n.contactBlocked,
              );
            }
          },
          color: contact.isBlocked ? null : context.c.onDanger,
        ),
      ],
    );
  }

  void _openPhoto(Contact contact) {
    if (contact.avatarPath == null) {
      iToast(context, context.l10n.noProfilePhotoSet);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: ClipRRect(
            borderRadius: AppRadius.rLg,
            child: Image.file(
              File(contact.avatarPath!),
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the four circular quick actions at the top of a profile.
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.c.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: AppIconSizes.md, color: context.c.accent),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: context.t.labelSmall?.copyWith(
                  color: context.c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
