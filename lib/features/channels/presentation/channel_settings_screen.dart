import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/group.dart';
import '../../../core/services/channel_service.dart';
import '../../../core/services/media_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import 'channel_join_requests_screen.dart';
import '../../../core/utils/l10n.dart';

/// Owner-only channel settings.
///
/// Everything here writes straight to Firestore and mirrors the result into the
/// local Hive copy, so the channel list stays correct offline.
class ChannelSettingsScreen extends ConsumerStatefulWidget {
  const ChannelSettingsScreen({super.key, required this.channel});

  final Channel channel;

  @override
  ConsumerState<ChannelSettingsScreen> createState() =>
      _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState
    extends ConsumerState<ChannelSettingsScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.channel.name);
  late final TextEditingController _username =
      TextEditingController(text: widget.channel.username);
  late final TextEditingController _description =
      TextEditingController(text: widget.channel.description);

  late String _category = widget.channel.category;
  late bool _isPublic = widget.channel.isPublic;
  late bool _isPremiumOnly = widget.channel.isPremiumOnly;
  String? _avatarUrl;
  String? _coverUrl;
  String? _issuedKey;
  bool _busy = false;

  static const List<String> _categories = <String>[
    'News',
    'Sports',
    'Technology',
    'Entertainment',
    'Education',
    'Business',
    'Lifestyle',
    'Other',
  ];

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Channel channel = widget.channel;

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.channelSettings, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Column(
              children: <Widget>[
                GestureDetector(
                  onTap: _busy ? null : _pickAvatar,
                  child: Stack(
                    children: <Widget>[
                      IAvatar(
                        name: _name.text.isEmpty ? 'C' : _name.text,
                        imagePath: channel.avatarPath,
                        imageUrl: _avatarUrl,
                        size: AppSizes.avatarXl,
                        icon: Icons.podcasts_rounded,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: context.c.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.l10n.tapToChangeTheChannel,
                  style: context.t.bodySmall?.copyWith(
                    color: context.c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          SettingsGroup(
            title: context.l10n.identity,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: ITextField(
                  controller: _name,
                  hint: context.l10n.channelName,
                  maxLength: 60,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: ITextField(
                  controller: _username,
                  hint: context.l10n.uniqueUsername,
                  maxLength: 32,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: ITextField(
                  controller: _description,
                  hint: context.l10n.description,
                  maxLines: 3,
                  maxLength: 200,
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.discovery,
            children: <Widget>[
              SettingsValueRow(
                label: context.l10n.category,
                value: _category,
                leadingIcon: Icons.category_outlined,
                onTap: _busy ? null : _pickCategory,
              ),
              SettingsSwitchRow(
                title: context.l10n.publicChannel,
                subtitle: _isPublic
                    ? 'Anyone can find and follow this channel'
                    : 'Only people with the secret key can request to join',
                value: _isPublic,
                onChanged: (bool v) => setState(() => _isPublic = v),
              ),
              SettingsSwitchRow(
                title: context.l10n.premiumOnly,
                subtitle: _isPremiumOnly
                    ? 'Only members with premium can read the posts'
                    : 'Anyone who follows can read the posts',
                value: _isPremiumOnly,
                // A private channel is already gated by its key, so stacking a
                // second gate on top would leave a key holder still locked out.
                // The two are alternatives, not layers.
                onChanged: _isPublic
                    ? (bool v) => setState(() => _isPremiumOnly = v)
                    : null,
              ),
              SettingsTile(
                title: context.l10n.coverImage,
                subtitle: _coverUrl == null
                    ? 'Add a wide banner behind the header'
                    : 'Cover updated — tap to replace',
                leadingIcon: Icons.wallpaper_rounded,
                onTap: _busy ? null : _pickCover,
              ),
            ],
          ),

          if (!_isPublic)
            SettingsGroup(
              title: context.l10n.secretKey,
              children: <Widget>[
                SettingsTile(
                  title: channel.hasSecretKey
                      ? 'Rotate secret key'
                      : 'Generate secret key',
                  subtitle: channel.hasSecretKey
                      ? 'The old key stops working immediately'
                      : 'A 12-character key, shown to you once',
                  leadingIcon: Icons.key_rounded,
                  onTap: _busy ? null : _rotateKey,
                ),
                if (_issuedKey != null)
                  SettingsTile(
                    title: _issuedKey!,
                    subtitle: context.l10n.tapToCopyThisIs,
                    leadingIcon: Icons.copy_rounded,
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _issuedKey!),
                      );
                      if (!context.mounted) return;
                      iToast(context, context.l10n.secretKeyCopied);
                    },
                  ),
                SettingsTile(
                  title: context.l10n.joinRequests,
                  subtitle: context.l10n.approveOrRejectPeopleWho,
                  leadingIcon: Icons.how_to_reg_rounded,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) =>
                          ChannelJoinRequestsScreen(channelId: channel.id),
                    ),
                  ),
                ),
              ],
            ),

          _MonetizationGroup(channel: channel),

          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ProminentButton(
              label: _busy ? 'Saving…' : 'Save changes',
              icon: Icons.check_rounded,
              expanded: true,
              onPressed: _busy ? null : () => _save(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              context.l10n.changesAreWrittenToFirestore2,
              textAlign: TextAlign.center,
              style: context.t.bodySmall?.copyWith(
                color: context.c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- actions

  Future<void> _pickAvatar() async {
    final String? url = await _upload(kind: 'avatar');
    if (url == null || !mounted) return;
    setState(() => _avatarUrl = url);
  }

  Future<void> _pickCover() async {
    final String? url = await _upload(kind: 'cover');
    if (url == null || !mounted) return;
    setState(() => _coverUrl = url);
  }

  /// Picks an image and uploads it, returning the public URL.
  ///
  /// Returns null when the user cancels, denies permission, or the upload
  /// fails — each of which has already been reported to the user by then.
  Future<String?> _upload({required String kind}) async {
    final MediaPickResult picked =
        await ref.read(mediaServiceProvider).pickImages();
    if (!mounted) return null;
    if (picked.permissionDenied) {
      iToast(context, context.l10n.galleryPermissionIsRequired, isError: true);
      return null;
    }
    final String? path = picked.attachments.firstOrNull?.localPath;
    if (path == null) return null;

    setState(() => _busy = true);
    final String? url = await ref.read(storageServiceProvider).uploadFile(
          path,
          folder: 'channels',
          owner: widget.channel.id,
          kind: kind,
        );
    if (!mounted) return null;
    setState(() => _busy = false);

    if (url == null) {
      iToast(
        context,
        context.l10n.uploadFailedCheckTheStorage,
        isError: true,
      );
    }
    return url;
  }

  Future<void> _pickCategory() async {
    final String? value = await showChoiceSheet<String>(
      context: context,
      title: context.l10n.category,
      selected: _category,
      options: <({String value, String? subtitle, String label})>[
        for (final String c in _categories)
          (value: c, label: c, subtitle: null),
      ],
    );
    if (value == null) return;
    setState(() => _category = value);
  }

  Future<void> _rotateKey() async {
    final bool ok = await showConfirmDialog(
      context,
      title: context.l10n.rotateTheSecretKey,
      message: context.l10n.everyoneCurrentlyUsingTheOld2,
      confirmLabel: context.l10n.generate,
    );
    if (!ok || !mounted) return;

    final String key = ChannelFirestoreService.generateSecretKey();
    setState(() {
      _issuedKey = key;
      _isPublic = false;
    });
    // Persist immediately: the key is only shown once, so it must not be lost
    // if the user leaves the screen without pressing Save.
    await _save(silent: true);
  }

  Future<void> _save({bool silent = false}) async {
    final String name = _name.text.trim();
    final String username =
        ChannelFirestoreService.normaliseUsername(_username.text);
    if (name.isEmpty) {
      iToast(context, context.l10n.aChannelNeedsAName, isError: true);
      return;
    }

    setState(() => _busy = true);

    final bool usernameChanged = username != widget.channel.username;
    if (usernameChanged && username.isNotEmpty) {
      final bool free = await ref
          .read(channelFirestoreProvider)
          .isUsernameAvailable(username, exceptChannelId: widget.channel.id);
      if (!free) {
        if (!mounted) return;
        setState(() => _busy = false);
        final List<String> suggestions = await ref
            .read(channelFirestoreProvider)
            .suggestUsernames(username);
        if (!mounted) return;
        iToast(
          context,
          suggestions.isEmpty
              ? context.l10n.usernameTaken('@$username')
              : context.l10n.usernameTakenWithSuggestions(
                  '@$username',
                  suggestions.map((String s) => '@$s').join(', '),
                ),
          isError: true,
        );
        return;
      }
    }

    final bool ok = await ref.read(channelFirestoreProvider).updateChannel(
          channelId: widget.channel.id,
          name: name,
          username: username,
          description: _description.text.trim(),
          category: _category,
          avatarUrl: _avatarUrl,
          coverUrl: _coverUrl,
          isPublic: _isPublic,
          isPremiumOnly: _isPremiumOnly && _isPublic,
          secretKey: _issuedKey,
        );

    if (!mounted) return;

    if (!ok) {
      setState(() => _busy = false);
      iToast(context, context.l10n.couldNotSaveIsThe, isError: true);
      return;
    }

    // Mirror into the local copy so the channel list and header update without
    // waiting for a Firestore round-trip.
    final Channel updated = widget.channel.copyWith(
      name: name,
      username: username,
      description: _description.text.trim(),
      category: _category,
      coverUrl: _coverUrl,
      isPublic: _isPublic,
      isPremiumOnly: _isPremiumOnly && _isPublic,
    );
    await ref.read(channelsProvider.notifier).persist(updated);
    if (!mounted) return;

    setState(() => _busy = false);
    if (!silent) {
      iToast(context, context.l10n.channelUpdated);
      context.pop();
    }
  }
}

/// The monetization status card, gated on the directive's thresholds.
class _MonetizationGroup extends ConsumerWidget {
  const _MonetizationGroup({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColorScheme c = context.c;
    final MonetizationStatus status = channel.monetizationStatus;

    return SettingsGroup(
      title: context.l10n.monetization,
      children: <Widget>[
        SettingsTile(
          title: switch (status) {
            MonetizationStatus.approved => 'Monetized',
            MonetizationStatus.pending => 'Application under review',
            MonetizationStatus.rejected => 'Application was rejected',
            MonetizationStatus.none => channel.isEligibleForMonetization
                ? 'You are eligible to apply'
                : 'Not eligible yet',
          },
          subtitle: switch (status) {
            MonetizationStatus.approved =>
              'Your channel can now earn from its audience',
            MonetizationStatus.pending =>
              'We will notify you once a reviewer has decided',
            MonetizationStatus.rejected =>
              'You can re-apply once the channel grows further',
            MonetizationStatus.none =>
              'Needs ${TextUtils.grouped(Channel.monetizationFollowerThreshold)} '
                  'followers and '
                  '${TextUtils.grouped(Channel.monetizationReactionThreshold)} '
                  'reactions in 60 days.\n'
                  'Currently: ${TextUtils.grouped(channel.followerCount)} '
                  'followers · ${TextUtils.grouped(channel.totalReactions)} '
                  'reactions',
          },
          leadingIcon: Icons.paid_outlined,
          leadingIconColor:
              status == MonetizationStatus.approved ? c.accent : null,
          trailing: channel.isEligibleForMonetization
              ? const Icon(Icons.chevron_right_rounded)
              : null,
          onTap: channel.isEligibleForMonetization
              ? () async {
                  final bool ok = await showConfirmDialog(
                    context,
                    title: context.l10n.applyForMonetization2,
                    message: context.l10n.aReviewerWillCheckThat2,
                    confirmLabel: context.l10n.apply,
                  );
                  if (!ok || !context.mounted) return;
                  await ref
                      .read(channelFirestoreProvider)
                      .applyForMonetization(
                        channel.id,
                        followersAtApply: channel.followerCount,
                        reactionsAtApply: channel.totalReactions,
                      );
                  if (!context.mounted) return;
                  iToast(context, context.l10n.applicationSubmitted);
                }
              : null,
        ),
      ],
    );
  }
}
