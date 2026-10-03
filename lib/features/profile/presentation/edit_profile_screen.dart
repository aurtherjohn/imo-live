import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/contact.dart';
import '../../../core/services/media_service.dart';
import '../../../core/widgets/camera_sheet.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
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

  bool get _dirty =>
      _first.text.trim() != _original.firstName ||
      _last.text.trim() != _original.lastName ||
      _username.text.trim() != _original.username ||
      _phone.text.trim() != _original.phone ||
      _bio.text.trim() != _original.bio ||
      _avatarPath != _original.avatarPath;

  bool get _valid => _first.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_valid) {
      iToast(context, context.l10n.aFirstNameIsRequired, isError: true);
      return;
    }
    setState(() => _saving = true);

    await ref.read(selfProfileProvider.notifier).save(
          _original.copyWith(
            firstName: _first.text.trim(),
            lastName: _last.text.trim(),
            username: _username.text.trim(),
            phone: _phone.text.trim(),
            bio: _bio.text.trim(),
            avatarPath: _avatarPath,
            isSelf: true,
          ),
        );

    if (!mounted) return;
    setState(() => _saving = false);
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
                        onTap: () => _pickPhoto(fromCamera: true),
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
                          child: const Icon(
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
          _ProfileField(
            controller: _phone,
            label: context.l10n.phone,
            hint: context.l10n.eG8801711234567,
            keyboardType: TextInputType.phone,
            maxLength: 20,
            onChanged: () => setState(() {}),
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
  Future<void> _pickPhoto({bool fromCamera = false}) async {
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
    final String stored = await ref.read(mediaRepositoryProvider).upload(path);
    if (!mounted) return;
    setState(() => _avatarPath = stored);
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
    this.keyboardType,
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
  final TextInputType? keyboardType;
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
            keyboardType: keyboardType,
            textCapitalization: capitalization,
            onChanged: (_) => onChanged?.call(),
          ),
        ],
      ),
    );
  }
}
