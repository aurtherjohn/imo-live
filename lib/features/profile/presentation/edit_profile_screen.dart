import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/contact.dart';
import '../../../core/services/firebase_auth_service.dart';
import '../../../core/services/media_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/widgets/camera_sheet.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../chats/domain/remote_chats_sync.dart' show liveChatsStreamProvider;
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../chats/presentation/providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import '../../../core/utils/l10n.dart';

/// Edit your own name, about text, username and profile photo.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _last = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _bio = TextEditingController();

  Contact _original = const Contact(id: 'self', firstName: 'You');
  String? _avatarPath;

  /// The R2 **public URL** of a photo picked in this session, or null when the
  /// user has not changed it.
  ///
  /// Distinct from [_avatarPath] on purpose, and the distinction is the whole
  /// profile-picture bug: `avatarPath` is a device-local file path, which is
  /// what the editor and this device render, while `avatarUrl` is the only
  /// thing another account can fetch. Before this field existed, picking a
  /// photo stored the local path and uploaded the bytes to R2 *without keeping
  /// the URL it returned* — so `users/{uid}.avatarUrl` was never written and
  /// nobody else could ever see the picture.
  ///
  /// Null means "unchanged", so saving a name edit cannot blank out an avatar
  /// that was set on another device (or by Google at sign-in).
  String? _avatarUrl;

  /// True while the picked photo is uploading, so the UI can show progress
  /// instead of appearing frozen.
  bool _uploadingAvatar = false;

  bool _ready = false;
  bool _saving = false;

  static const List<String> _aboutSuggestions = <String>[
    'Available',
    'Busy',
    'At work',
    'Battery about to die',
    'In a meeting',
    'Can\'t talk, chat only',
    'Sleeping',
    'Hey there! I am using Imo LIVE.',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final Contact me = ref.read(selfProfileProvider).valueOrNull ??
        const Contact(id: 'self', firstName: 'You');
    setState(() {
      _original = me;
      _first.text = me.firstName;
      _last.text = me.lastName;
      _username.text = me.username;
      _phone.text = me.phone;
      _bio.text = me.bio;
      _avatarPath = me.avatarPath;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _username.dispose();
    _phone.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// True when anything the user may actually change has been edited.
  ///
  /// The phone number is deliberately absent: it is fixed at signup and the
  /// field is read-only, so counting it here would leave "Save" permanently
  /// enabled (or, worse, permanently disabled) for a value nobody can move.
  bool get _dirty =>
      _first.text.trim() != _original.firstName ||
      _last.text.trim() != _original.lastName ||
      _username.text.trim() != _original.username ||
      _bio.text.trim() != _original.bio ||
      _avatarPath != _original.avatarPath ||
      _avatarUrl != null;

  bool get _valid => _first.text.trim().isNotEmpty;

  /// Saves locally **and** publishes the change to `users/{uid}`.
  ///
  /// The local write is what this device renders immediately. The Firestore
  /// write is what every other account reads — without it the name, handle,
  /// about text and avatar only ever existed on one phone, which is why a
  /// second device saw a blank profile for a user who had clearly filled one
  /// in.
  ///
  /// `avatarUrl` is only sent when the user actually picked a photo this
  /// session (see [_avatarUrl]), so an ordinary name edit cannot wipe an avatar
  /// set elsewhere.
  Future<void> _save() async {
    if (!_valid) {
      iToast(context, context.l10n.aFirstNameIsRequired, isError: true);
      return;
    }
    setState(() => _saving = true);

    final String first = _first.text.trim();
    final String last = _last.text.trim();
    final String fullName = <String>[first, last]
        .where((String part) => part.isNotEmpty)
        .join(' ');

    await ref.read(selfProfileProvider.notifier).save(
          _original.copyWith(
            firstName: first,
            lastName: last,
            username: _username.text.trim(),
            // The stored number is the signup one, never the field's contents —
            // the field is read-only, so re-sending it would only risk writing
            // a stale value back over a number changed by support.
            phone: _original.phone,
            bio: _bio.text.trim(),
            avatarPath: _avatarPath,
            // Keep the remote URL on the local row too: it is what the drawer,
            // the profile screen and the chat list fall back to when the local
            // file is gone (a reinstall, or media cleared), and it is what
            // `mirrorRemoteChat` reads when it upgrades a peer's chat row.
            avatarUrl: _avatarUrl ?? _original.avatarUrl,
            isSelf: true,
          ),
        );

    String? remoteError;
    try {
      await ref.read(firebaseAuthServiceProvider).updateProfile(
            name: fullName.isEmpty ? _original.fullName : fullName,
            username: _username.text.trim(),
            bio: _bio.text.trim(),
            avatarUrl: _avatarUrl,
          );
    } on AuthException catch (error) {
      // The common case is a taken @handle. The local save already happened, so
      // the honest report is "saved here, not published" rather than a blanket
      // failure.
      remoteError = error.message;
    } on Object catch (error) {
      debugPrint('Publishing profile to Firestore failed: $error');
      remoteError = 'Your profile was saved on this device but could not be '
          'published. Check your connection and save again.';
    }

    // The published name/avatar is what every other row derives from, so the
    // mirrors are rebuilt rather than left holding the pre-edit copy.
    if (remoteError == null) {
      ref.invalidate(liveChatsStreamProvider);
      ref.invalidate(contactsProvider);
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _original = _original.copyWith(
        firstName: first,
        lastName: last,
        username: _username.text.trim(),
        bio: _bio.text.trim(),
      );
      _avatarUrl = null;
    });

    if (remoteError != null) {
      iToast(context, remoteError, isError: true);
      return;
    }
    iToast(context, context.l10n.profileUpdated);
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: ILoader(size: 26)));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.editProfile),
        actions: <Widget>[
          if (_dirty)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      context.l10n.save,
                      style: TextStyle(
                        color: context.c.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Column(
              children: <Widget>[
                Stack(
                  children: <Widget>[
                    IAvatar(
                      name: _first.text.trim().isEmpty
                          ? 'You'
                          : '${_first.text} ${_last.text}'.trim(),
                      imagePath: _avatarPath,
                      colorSeed: _original.avatarColor,
                      size: AppSizes.avatarXxl,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _uploadingAvatar
                            ? null
                            : () => _pickPhoto(fromCamera: true),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: context.c.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 3,
                            ),
                          ),
                          child: _uploadingAvatar
                              ? const Padding(
                                  padding: EdgeInsets.all(9),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.photo_camera_rounded,
                                  size: 17,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: () => _pickPhoto(),
                      icon: const Icon(Icons.photo_library_outlined, size: 17),
                      label: Text(context.l10n.changePhoto),
                    ),
                    if (_avatarPath != null)
                      TextButton.icon(
                        onPressed: () async {
                          final bool ok = await showConfirmDialog(
                            context,
                            title: context.l10n.removePhoto,
                            message:
                                context.l10n.yourProfilePhotoIsDeleted,
                            confirmLabel: context.l10n.remove,
                            destructive: true,
                          );
                          if (!ok || !mounted) return;
                          await ref
                              .read(fileStorageProvider)
                              .deleteFile(_avatarPath);
                          if (mounted) setState(() => _avatarPath = null);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 17),
                        label: Text(context.l10n.remove),
                        style: TextButton.styleFrom(
                          foregroundColor: context.c.onDanger,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          Padding(
            padding: AppSpacing.pageH,
            child: Text(
              context.l10n.yourNameIsVisibleTo,
              style: context.t.bodySmall?.copyWith(
                color: context.c.textSecondary,
              ),
            ),
          ),

          _ProfileField(
            controller: _first,
            label: context.l10n.firstName,
            hint: context.l10n.requiredLabel,
            capitalization: TextCapitalization.words,
            maxLength: 40,
            onChanged: () => setState(() {}),
          ),
          _ProfileField(
            controller: _last,
            label: context.l10n.lastName,
            hint: context.l10n.optional,
            capitalization: TextCapitalization.words,
            maxLength: 40,
            onChanged: () => setState(() {}),
          ),

          // ------------------------------------------------------------ about
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    context.l10n.about2,
                    style: context.t.labelMedium?.copyWith(
                      color: context.c.textSecondary,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${_bio.text.runes.length}/140',
                  style: context.t.labelSmall?.copyWith(
                    color: context.c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _ProfileField(
            controller: _bio,
            label: '',
            hint: context.l10n.writeSomethingAboutYourself,
            maxLines: 3,
            maxLength: 140,
            onChanged: () => setState(() {}),
            hideLabel: true,
          ),
          Padding(
            padding: AppSpacing.pageH,
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _aboutSuggestions
                  .map(
                    (String suggestion) => GestureDetector(
                      onTap: () => setState(() => _bio.text = suggestion),
                      child: IPill(label: suggestion),
                    ),
                  )
                  .toList(),
            ),
          ),

          _ProfileField(
            controller: _username,
            label: context.l10n.username,
            hint: context.l10n.optionalHandleOthersCanSearch,
            prefix: '@',
            maxLength: 24,
            capitalization: TextCapitalization.none,
            onChanged: () => setState(() {}),
          ),
          // ------------------------------------------------------------ phone
          //
          // Locked on purpose. The number is the account's credential — it is
          // what the derived sign-in address is built from — so allowing it to
          // be edited here would let a user point their login at a number they
          // do not own, or strand themselves with an address they can no longer
          // authenticate against. Changing it is a support operation, not a
          // profile edit.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.lock_rounded,
                      size: 13,
                      color: context.c.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.l10n.phone.toUpperCase(),
                        style: context.t.labelMedium?.copyWith(
                          color: context.c.textSecondary,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ITextField(
                  controller: _phone,
                  hint: context.l10n.eG8801711234567,
                  keyboardType: TextInputType.phone,
                  maxLength: 20,
                  enabled: false,
                  suffix: Icon(
                    Icons.lock_rounded,
                    size: 16,
                    color: context.c.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Phone number cannot be changed.',
                  style: context.t.bodySmall?.copyWith(
                    color: context.c.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Contact support to change your phone number.',
                  style: context.t.bodySmall?.copyWith(
                    color: context.c.textSecondary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          Padding(
            padding: AppSpacing.pageH,
            child: ProminentButton(
              label: _dirty ? 'Save changes' : 'Nothing to save',
              icon: Icons.check_rounded,
              expanded: true,
              onPressed: _dirty && _valid ? _save : () => context.pop(),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: InfoBanner(
              message:
                  context.l10n.yourNameAboutTextAnd2,
            ),
          ),
        ],
      ),
    );
  }

  /// Camera badge → real camera; "Change photo" → gallery.
  ///
  /// `fromCamera` used to be ignored entirely, so the camera badge opened the
  /// gallery picker — indistinguishable from the button right below it.
  ///
  /// ### Why the upload is awaited here and not deferred
  ///
  /// This is the one place a local path is not enough. An avatar has to be
  /// *fetchable by other accounts*, so the file must reach R2 before the save
  /// can promise anything, and the URL R2 returns is what gets written to
  /// `users/{uid}.avatarUrl`. The old code fired the upload off with `unawaited`
  /// and threw the returned URL away, which is why the picture never left the
  /// device. The cost is a spinner for the duration of the upload, which is
  /// exactly what [_uploadingAvatar] is for.
  Future<void> _pickPhoto({bool fromCamera = false}) async {
    if (_uploadingAvatar) return;

    final MediaService media = ref.read(mediaServiceProvider);
    final MediaPickResult result = fromCamera
        ? await media.capturePhoto()
        : await media.pickImages();

    if (!mounted) return;

    if (result.hasError) {
      showMediaErrorSnack(
        context,
        result,
        onOpenSettings: () => ref.read(permissionServiceProvider).openSettings(),
      );
      return;
    }
    if (result.isEmpty) return;

    final String? path = result.attachments.first.localPath;
    if (path == null) {
      iToast(context, context.l10n.couldNotReadTheSelected, isError: true);
      return;
    }

    // The local copy is imported first so the avatar renders instantly and
    // survives a failed upload.
    final String stored = await ref.read(mediaRepositoryProvider).upload(path);
    if (!mounted) return;
    setState(() {
      _avatarPath = stored;
      _uploadingAvatar = true;
    });

    final String uid = ref.read(currentUidProvider);
    final String? url = uid.isEmpty
        ? null
        : await ref.read(storageServiceProvider).uploadAvatar(stored, uid);

    debugPrint('EDIT_PROFILE: uploading, uid=$uid, url=$url');

    if (!mounted) return;
    setState(() {
      _uploadingAvatar = false;
      if (url != null && url.isNotEmpty) _avatarUrl = url;
    });

    if (url == null || url.isEmpty) {
      iToast(
        context,
        'The photo was saved on this device but could not be uploaded, so '
        'others will not see it yet. Check your connection and try again.',
        isError: true,
      );
      return;
    }
    iToast(context, context.l10n.photoUpdatedTapSaveTo);
  }
}

/// A labelled field used by the profile editor.
class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.controller,
    required this.label,
    this.hint = '',
    this.prefix,
    this.maxLines = 1,
    this.maxLength,
    this.capitalization = TextCapitalization.sentences,
    this.onChanged,
    this.hideLabel = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? prefix;
  final int maxLines;
  final int? maxLength;
  final TextCapitalization capitalization;
  final VoidCallback? onChanged;
  final bool hideLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        hideLabel ? AppSpacing.sm : AppSpacing.xl,
        AppSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!hideLabel && label.isNotEmpty) ...<Widget>[
            Text(
              label.toUpperCase(),
              style: context.t.labelMedium?.copyWith(
                color: context.c.textSecondary,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          ITextField(
            controller: controller,
            hint: hint,
            maxLines: maxLines,
            maxLength: maxLength,
            textCapitalization: capitalization,
            onChanged: (_) => onChanged?.call(),
          ),
        ],
      ),
    );
  }
}
