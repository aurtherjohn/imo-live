import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/group.dart';
import '../../../core/services/channel_service.dart';
import '../../../core/services/media_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import 'providers.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../../core/utils/l10n.dart';

/// Create a broadcast channel.
///
/// A unique `@username` is required, and a private channel additionally gets a
/// 12-character secret key. The Firestore document — including the username and
/// key indexes — is written **before** navigation, so the channel screen always
/// opens onto a document that exists.
class NewChannelScreen extends ConsumerStatefulWidget {
  const NewChannelScreen({super.key});

  @override
  ConsumerState<NewChannelScreen> createState() => _NewChannelScreenState();
}

class _NewChannelScreenState extends ConsumerState<NewChannelScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _description = TextEditingController();

  String _category = 'Other';
  bool _isPublic = true;
  String? _avatarPath;
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
    final String handle =
        ChannelFirestoreService.normaliseUsername(_username.text);
    final bool canCreate =
        _name.text.trim().isNotEmpty && handle.isNotEmpty && !_busy;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.newChannel),
        actions: <Widget>[
          TextButton(
            onPressed: canCreate ? _create : null,
            child: Text(
              context.l10n.create,
              style: TextStyle(
                color: canCreate ? context.c.accent : context.c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: GestureDetector(
              onTap: _busy ? null : _pickAvatar,
              child: Stack(
                children: <Widget>[
                  IAvatar(
                    name: _name.text.isEmpty ? 'C' : _name.text,
                    imagePath: _avatarPath,
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
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              context.l10n.channelPhoto,
              style: context.t.bodySmall?.copyWith(
                color: context.c.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          SettingsGroup(
            title: context.l10n.details,
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
                  hint: context.l10n.uniqueUsernameRequired,
                  maxLength: 32,
                  keyboardType: TextInputType.text,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (handle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Text(
                    context.l10n.followersWillFindYouAs(handle),
                    style: context.t.bodySmall?.copyWith(
                      color: context.c.textSecondary,
                    ),
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
                  hint: context.l10n.whatDoesThisChannelPost,
                  maxLines: 3,
                  maxLength: 200,
                ),
              ),
            ],
          ),

          SettingsGroup(
            title: context.l10n.visibility,
            children: <Widget>[
              SettingsSwitchRow(
                title: context.l10n.publicChannel,
                subtitle: _isPublic
                    ? 'Anyone can find this channel by its @username'
                    : 'Private — people need a secret key to request to join',
                value: _isPublic,
                onChanged: (bool v) => setState(() => _isPublic = v),
              ),
              if (!_isPublic)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: InfoBanner(
                    message:
                        context.l10n.a12CharacterSecretKey2,
                  ),
                ),
              SettingsValueRow(
                label: context.l10n.category,
                value: _category,
                leadingIcon: Icons.category_outlined,
                onTap: _busy ? null : _pickCategory,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ProminentButton(
              label: _busy ? 'Creating…' : 'Create channel',
              icon: Icons.check_rounded,
              expanded: true,
              onPressed: canCreate ? () => _create() : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final MediaPickResult picked =
        await ref.read(mediaServiceProvider).pickImages();
    if (!mounted) return;
    if (picked.permissionDenied) {
      iToast(context, context.l10n.galleryPermissionIsRequired, isError: true);
      return;
    }
    final String? path = picked.attachments.firstOrNull?.localPath;
    if (path == null) return;
    setState(() => _avatarPath = path);
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
    if (!mounted || value == null) return;
    setState(() => _category = value);
  }

  Future<void> _create() async {
    final String name = _name.text.trim();
    final String handle =
        ChannelFirestoreService.normaliseUsername(_username.text);
    if (name.isEmpty || handle.isEmpty) return;

    setState(() => _busy = true);
    final ChannelFirestoreService service = ref.read(channelFirestoreProvider);
    final String uid = ref.read(channelViewerUidProvider);

    // 1. The handle must be free. Checked here so the user gets a fix, and
    //    again inside createChannel (in a batch) so a race cannot create two
    //    channels with the same name.
    if (!await service.isUsernameAvailable(handle)) {
      final List<String> suggestions = await service.suggestUsernames(handle);
      if (!mounted) return;
      setState(() => _busy = false);
      iToast(
        context,
        suggestions.isEmpty
            ? '@$handle is taken'
            : '@$handle is taken — try ${suggestions.map((String s) => '@$s').join(', ')}',
        isError: true,
      );
      return;
    }

    // 2. Private channels get a key now; only its hash is ever stored.
    final String? secretKey =
        _isPublic ? null : ChannelFirestoreService.generateSecretKey();
    final String keyHash = secretKey == null
        ? ''
        : await ChannelFirestoreService.hashSecretKey(secretKey);

    // 3. Upload the photo, so followers on other devices can see it.
    String? avatarUrl;
    if (_avatarPath != null) {
      avatarUrl = await ref.read(storageServiceProvider).uploadFile(
            _avatarPath!,
            folder: 'channels',
            owner: uid,
            kind: 'avatar',
          );
      if (!mounted) return;
    }

    final Channel channel = Channel(
      id: '',
      name: name,
      username: handle,
      description: _description.text.trim(),
      avatarPath: _avatarPath,
      avatarUrl: avatarUrl,
      category: _category,
      isPublic: _isPublic,
      isFollowing: true,
      followerCount: 1,
      inviteCode: _inviteCode(),
      secretKeyHash: keyHash,
      createdAt: DateTime.now(),
    );

    // 4. Write the Firestore document FIRST — with the id resolved by Firestore
    //    — so the channel screen opens onto a document that already exists.
    final Channel? remote = await service.createChannel(
      channel: channel,
      uid: uid,
      secretKey: secretKey,
    );
    if (!mounted) return;

    // 5. Mirror locally so the channel list and offline open both work.
    final Channel saved = await ref.read(channelsProvider.notifier).create(
          remote ?? channel.copyWith(id: 'channel_${DateTime.now().microsecondsSinceEpoch}'),
        );
    if (!mounted) return;

    setState(() => _busy = false);

    if (remote == null) {
      iToast(
        context,
        context.l10n.savedOnThisDeviceThe,
        isError: true,
      );
    } else {
      iToast(context, context.l10n.channelCreatedName(name));
    }

    if (secretKey != null) {
      await _showSecretKey(secretKey, name);
      if (!mounted) return;
    }

    // Straight to the conversation, where the composer now lives. Landing on
    // the management feed would show a freshly made channel with no visible
    // way to write the first post.
    context.pushReplacement('${AppRoutes.channelChat}/${saved.id}');
  }

  /// Shows the secret key exactly once, with a copy button.
  Future<void> _showSecretKey(String key, String channelName) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(context.l10n.secretKey),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.shareSecretKeyFor(channelName),
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            SelectableText(
              key,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.4,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: key));
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
            },
            child: Text(context.l10n.copyClose),
          ),
        ],
      ),
    );
  }

  String _inviteCode() {
    const String alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
    final int seed = DateTime.now().microsecondsSinceEpoch;
    final StringBuffer buffer = StringBuffer();
    int value = seed;
    for (int i = 0; i < 10; i++) {
      value = value * 1103515245 + 12345;
      buffer.write(alphabet[(value.abs() ~/ 65536) % alphabet.length]);
    }
    return buffer.toString();
  }
}
