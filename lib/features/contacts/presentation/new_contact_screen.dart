import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/settings.dart';
import '../../../core/services/media_service.dart';
import '../../../core/services/remote_contact_service.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../chats/domain/chat_service.dart';
import '../../chats/presentation/providers.dart';
import 'country_picker_screen.dart';
import 'dialogs/confirm_dialog.dart';
import 'widgets/directory_lookup_panel.dart';
import '../../../core/utils/l10n.dart';

/// Create or edit a contact.
///
/// Passing `contactId` switches the screen into edit mode.
class NewContactScreen extends ConsumerStatefulWidget {
  const NewContactScreen({super.key, this.contactId});

  final String? contactId;

  bool get isEditing => contactId != null && contactId!.isNotEmpty;

  @override
  ConsumerState<NewContactScreen> createState() => _NewContactScreenState();
}

class _NewContactScreenState extends ConsumerState<NewContactScreen> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _last = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _bio = TextEditingController();

  Contact? _existing;
  Country _country = countryForIso('BD') ??
      const Country(name: 'Bangladesh', iso: 'BD', dialCode: '+880');
  bool _saveToDevice = false;
  bool _loading = true;

  /// Debounced live probe against the shared Imo LIVE directory.
  DirectoryProbeController? _probe;

  /// The directory account resolved for the number being typed, if any.
  RemoteProfile? _remoteProfile;
  final ValueNotifier<DirectoryProbe> _probeValue =
      ValueNotifier<DirectoryProbe>(const DirectoryProbe.idle());

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Lazily creates the probe so it can read providers after the first frame.
  DirectoryProbeController get _lookup {
    final DirectoryProbeController existing = _probe ??
        DirectoryProbeController(ref.read(remoteContactServiceProvider));
    _probe = existing;
    existing.removeListener(_onProbeChanged);
    existing.addListener(_onProbeChanged);
    return existing;
  }

  void _onProbeChanged() {
    final DirectoryProbeController? controller = _probe;
    if (controller == null || !mounted) return;
    _probeValue.value = controller.value;
  }

  Future<void> _load() async {
    if (widget.isEditing) {
      final Contact? found =
          await ref.read(contactRepositoryProvider).findById(widget.contactId!);
      if (found != null && mounted) {
        setState(() {
          _existing = found;
          _first.text = found.firstName;
          _last.text = found.lastName;
          _phone.text = found.phone;
          _username.text = found.username;
          _bio.text = found.bio;
          _country = countryForIso(found.countryIso) ?? _country;
          _loading = false;
        });
        return;
      }
    } else {
      final bool sync = ref.read(syncContactsOnSaveProvider).valueOrNull ?? false;
      if (mounted) {
        setState(() {
          _saveToDevice = sync;
          _loading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _probe?.removeListener(_onProbeChanged);
    _probe?.dispose();
    _probeValue.dispose();
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _first.text.trim().isNotEmpty && _phone.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) {
      iToast(context, context.l10n.aFirstNameAndPhone, isError: true);
      return;
    }

    final String digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    final String normalised = digits.isEmpty ? '' : '${_country.dialCode} $digits';

    final Contact? duplicate =
        await ref.read(contactRepositoryProvider).findByPhone(normalised);
    if (duplicate != null && duplicate.id != _existing?.id && mounted) {
      final bool proceed = await showConfirmDialog(
        context,
        title: context.l10n.numberAlreadySaved,
        message:
            context.l10n.alreadyUsesSaveAnotherContact(duplicate.fullName, normalised),
        confirmLabel: context.l10n.saveAnyway,
      );
      if (!proceed || !mounted) return;
    }

    final Contact contact = Contact(
      id: _existing?.id ??
          'c_${DateTime.now().microsecondsSinceEpoch}',
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      username: _username.text.trim(),
      phone: normalised,
      countryCode: _country.dialCode,
      countryIso: _country.iso,
      bio: _bio.text.trim(),
      avatarPath: _existing?.avatarPath,
      avatarColor: _existing?.avatarColor,
      isFavorite: _existing?.isFavorite ?? false,
      isBlocked: _existing?.isBlocked ?? false,
      isSyncedToDevice: _existing?.isSyncedToDevice ?? false,
    );
    if (_saveToDevice) {
      final bool ok = await ref.read(deviceContactServiceProvider).writeToDevice(
            firstName: contact.firstName,
            lastName: contact.lastName,
            phone: contact.phone,
          );
      if (!mounted) return;
      {
        iToast(
          context,
          ok
              ? 'Saved to your address book'
              : 'Could not write to the address book',
          isError: !ok,
        );
      }
    }

    await ref.read(contactsProvider.notifier).create(
          _saveToDevice ? contact.copyWith(isSyncedToDevice: true) : contact,
        );

    // Mirror into the shared directory so the address book survives a
    // reinstall, and link the local row to the account when the number
    // resolved to a real one. Best-effort: the contact is already saved
    // locally, so a network failure must not undo it.
    //
    //   users/{uid}                      the person's own account (created when
    //                                    they sign up — never written here)
    //   contacts/{myUid}/list/{id}       my address book, mirrored for my
    //                                    other devices
    //   chats/{chatId}                   the conversation row, created below
    final String ownerUid = ref.read(currentUidProvider);
    final RemoteProfile? remote = _remoteProfile;
    final ChatService service = ref.read(chatServiceProvider);
    if (ownerUid.isNotEmpty) {
      // Genuinely best-effort, as described above. Without this catch a network
      // failure here would escape `_save` and take the rest of it with it — so
      // the chat row would never be created and the confirmation would never
      // appear, which is the opposite of "a network failure must not undo it".
      try {
        if (remote != null) {
          await service.saveDirectoryContact(remote);
        } else {
          await service.saveContact(
            contactId: contact.id,
            name: contact.fullName,
            phone: contact.phone,
            avatarPath: contact.avatarPath ?? '',
            username: contact.username,
            bio: contact.bio,
            countryCode: contact.countryCode,
            countryIso: contact.countryIso,
          );
        }
      } on Object catch (error) {
        debugPrint('Directory mirror failed for ${contact.id}: $error');
      }
    }

    // Create the conversation as part of saving. This is what puts the person
    // in the Chats tab straight away — the StreamBuilder picks the row up
    // without the user having to send anything first.
    //
    // Guarded for the same reason: the contact is already saved locally, so a
    // failure here should cost the "Message" action on the confirmation, not
    // the confirmation itself.
    String chatId = '';
    try {
      chatId = await service.openDirectChat(
        contactId: contact.id,
        name: contact.fullName.trim().isEmpty ? contact.phone : contact.fullName,
        phone: contact.phone,
        avatarPath: contact.avatarPath ?? '',
        remoteUid: remote?.uid ?? '',
        username: contact.username,
        bio: contact.bio,
      );
    } on Object catch (error) {
      debugPrint('Could not open a chat for ${contact.id}: $error');
    }

    if (!mounted) return;

    // Editing an existing contact keeps the plain confirmation: there is no new
    // conversation to offer.
    if (widget.isEditing) {
      iToast(context, context.l10n.contactUpdated(_labelFor(contact)));
      if (context.canPop()) context.pop();
      return;
    }

    // Capture the messenger before popping — the root ScaffoldMessenger
    // outlives this route, so the SnackBar lands on the Chats tab.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.chats);
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.contactSaved(_labelFor(contact))),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          action: chatId.isEmpty
              ? null
              : SnackBarAction(
                  label: context.l10n.message,
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    // The app-level router, not this screen's context: the
                    // SnackBar outlives the route, so a `context` captured here
                    // would be defunct by the time the action is tapped.
                    appRouter.push('${AppRoutes.chat}/$chatId');
                  },
                ),
        ),
      );
  }

  /// The name to show for a contact, falling back to the number.
  String _labelFor(Contact contact) =>
      contact.fullName.trim().isEmpty ? contact.phone : contact.fullName.trim();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: ILoader(size: 26)));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.isEditing ? context.l10n.editContact : context.l10n.newContact),
        actions: <Widget>[
          TextButton(
            onPressed: _canSave ? _save : null,
            child: Text(
              context.l10n.save,
              style: TextStyle(
                color: _canSave ? context.c.accent : context.c.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: GestureDetector(
              onTap: () => _pickAvatar(),
              child: Column(
                children: <Widget>[
                  Stack(
                    children: <Widget>[
                      IAvatar(
                        name: _first.text.trim().isEmpty
                            ? 'New contact'
                            : '${_first.text} ${_last.text}'.trim(),
                        imagePath: _existing?.avatarPath,
                        colorSeed: _existing?.avatarColor,
                        size: AppSizes.avatarXl,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: context.c.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.photo_camera_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _existing?.avatarPath == null
                        ? 'Add photo'
                        : context.l10n.changePhoto,
                    style: context.t.bodySmall?.copyWith(
                      color: context.c.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          _Field(
            controller: _first,
            label: context.l10n.firstName,
            hint: context.l10n.requiredLabel,
            capitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          _Field(
            controller: _last,
            label: context.l10n.lastName,
            hint: context.l10n.optional,
            capitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),

          // --------------------------------------------------------- phone
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              context.l10n.phone,
              style: context.t.labelMedium?.copyWith(
                color: context.c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                GestureDetector(
                  onTap: _pickCountry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md + 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.c.inputFill,
                      borderRadius: AppRadius.rMd,
                      border: Border.all(
                        color: context.c.divider,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _country.flagEmoji,
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          _country.dialCode,
                          style: context.t.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          size: AppIconSizes.md,
                          color: context.c.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ITextField(
                    controller: _phone,
                    hint: context.l10n.phoneNumber,
                    keyboardType: TextInputType.phone,
                    onChanged: (String value) {
                      setState(() {});
                      // Real-time directory probe: stops on the last keystroke
                      // for 350 ms, then asks Firestore whether this number has
                      // an Imo LIVE account.
                      if (!widget.isEditing) {
                        _lookup.probe('${_country.dialCode} $value');
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // Live "is this person on Imo LIVE?" result.
          if (!widget.isEditing)
            ValueListenableBuilder<DirectoryProbe>(
              valueListenable: _probeValue,
              builder: (BuildContext context, DirectoryProbe probe, Widget? _) =>
                  DirectoryLookupPanel(
                probe: probe,
                onAdd: _adoptDirectoryProfile,
                onInvite: _invite,
                onOpenChat: _openChatWith,
              ),
            ),

          _Field(
            controller: _username,
            label: context.l10n.username,
            hint: context.l10n.optionalHandle,
            prefix: '@',
            onChanged: (_) => setState(() {}),
          ),
          _Field(
            controller: _bio,
            label: context.l10n.about,
            hint: context.l10n.heyThereIAmUsing,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: context.c.card,
                borderRadius: AppRadius.rLg,
                border: Border.all(
                  color: context.c.divider.withValues(alpha: 0.7),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: AppSpacing.lg),
                  Icon(
                    Icons.contacts_outlined,
                    size: AppIconSizes.md,
                    color: context.c.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            context.l10n.saveToDeviceContacts,
                            style: context.t.bodyLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.l10n.alsoWriteThisPersonInto,
                            style: context.t.bodySmall?.copyWith(
                              color: context.c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _saveToDevice,
                    onChanged: (bool v) {
                      setState(() => _saveToDevice = v);
                      ref
                          .read(syncContactsOnSaveProvider.notifier)
                          .select(v);
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ),
            ),
          ),

          if (widget.isEditing) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            SettingsLikeActions(
              onDelete: () async {
                final bool ok = await showConfirmDialog(
                  context,
                  title: context.l10n.deleteContact2,
                  message:
                      context.l10n.xRemovedFromYourList(_existing?.fullName ?? context.l10n.thisContact),
                  confirmLabel: context.l10n.delete,
                  destructive: true,
                );
                if (!ok) return;
                await ref
                    .read(contactsProvider.notifier)
                    .remove(_existing!.id);
                if (context.mounted) {
                  iToast(context, context.l10n.contactDeleted);
                  context.pop();
                }
              },
              onBlock: () async {
                await ref
                    .read(contactsProvider.notifier)
                    .toggleBlocked(_existing!.id);
                if (context.mounted) {
                  iToast(
                    context,
                    _existing!.isBlocked ? 'Contact unblocked' : 'Contact blocked',
                  );
                }
              },
              isBlocked: _existing?.isBlocked ?? false,
              onFavorite: () async {
                await ref
                    .read(contactsProvider.notifier)
                    .toggleFavorite(_existing!.id);
                if (context.mounted) {
                  iToast(
                    context,
                    _existing!.isFavorite
                        ? 'Removed from favourites'
                        : 'Added to favourites',
                  );
                }
              },
              isFavorite: _existing?.isFavorite ?? false,
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: AppSpacing.pageH,
            child: ProminentButton(
              label: widget.isEditing ? 'Save changes' : 'Create contact',
              icon: Icons.check_rounded,
              expanded: true,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }

  /// Copies the discovered account into the form so "Add" behaves like the
  /// user having typed the details themselves.
  Future<void> _adoptDirectoryProfile(RemoteProfile profile) async {
    final List<String> names =
        profile.name.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    setState(() {
      if (names.isNotEmpty) _first.text = names.first;
      if (names.length > 1) _last.text = names.sublist(1).join(' ');
      if (profile.username.isNotEmpty) _username.text = profile.username;
      if (profile.bio.isNotEmpty) _bio.text = profile.bio;
      _remoteProfile = profile;
    });
    iToast(context, context.l10n.addedX(profile.name.isEmpty ? context.l10n.contact : profile.name));
  }

  /// Opens the invite sheet for a number that has no account yet.
  Future<void> _invite(String query) async {
    final String target = query.trim().isEmpty ? _phone.text.trim() : query;
    final bool ok = await showConfirmDialog(
      context,
      title: context.l10n.inviteToImoLIVE,
      message: context.l10n.sendInviteTo(target),
      confirmLabel: context.l10n.invite,
    );
    if (!ok || !mounted) return;
    iToast(context, context.l10n.inviteSentTo(target));
  }

  /// Opens (or creates) the 1:1 chat with a directory profile.
  Future<void> _openChatWith(RemoteProfile profile) async {
    await ref.read(chatServiceProvider).saveDirectoryContact(profile);
    final String chatId = await ref.read(chatServiceProvider).openDirectChat(
          contactId: profile.uid,
          name: profile.name.isEmpty ? profile.handle : profile.name,
          phone: profile.phone,
          avatarUrl: profile.avatarUrl,
          remoteUid: profile.uid,
          username: profile.username,
          bio: profile.bio,
        );
    if (!mounted || chatId.isEmpty) return;
    context.push('${AppRoutes.chats}/$chatId');
  }

  Future<void> _pickCountry() async {
    final Country? picked = await Navigator.of(context).push<Country>(
      MaterialPageRoute<Country>(
        builder: (BuildContext context) => const CountryPickerScreen(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _country = picked);
  }

  Future<void> _pickAvatar() async {
    final MediaPickResult picked =
        await ref.read(mediaServiceProvider).pickImages();
    if (picked.isEmpty) {
      if (picked.error != null && mounted) {
        iToast(context, picked.error!, isError: true);
      }
      return;
    }
    final String? path = picked.attachments.first.localPath;
    if (path == null || !mounted) return;
    final String stored = await ref.read(mediaRepositoryProvider).upload(path);
    if (!mounted) return;
    setState(() {
      _existing = (_existing ??
              const Contact(id: 'draft', firstName: 'Draft'))
          .copyWith(avatarPath: stored);
    });
  }
}

/// A labelled text field used by the contact form.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint = '',
    this.prefix,
    this.maxLines = 1,
    this.capitalization = TextCapitalization.sentences,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? prefix;
  final int maxLines;
  final TextCapitalization capitalization;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: context.t.labelMedium?.copyWith(
              color: context.c.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ITextField(
            controller: controller,
            hint: hint,
            maxLines: maxLines,
            textCapitalization: capitalization,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Destructive / preference actions shown when editing an existing contact.
class SettingsLikeActions extends StatelessWidget {
  const SettingsLikeActions({
    super.key,
    required this.onDelete,
    required this.onBlock,
    required this.isBlocked,
    required this.onFavorite,
    required this.isFavorite,
  });

  final VoidCallback onDelete;
  final VoidCallback onBlock;
  final bool isBlocked;
  final VoidCallback onFavorite;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Padding(
      padding: AppSpacing.pageH,
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: AppRadius.rLg,
          border: Border.all(color: c.divider.withValues(alpha: 0.7), width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: <Widget>[
            SettingsTile(
              title: isFavorite ? 'Remove from favourites' : 'Add to favourites',
              leadingIcon: isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              leadingIconColor: isFavorite ? c.accent : null,
              onTap: onFavorite,
            ),
            IListDivider(indent: AppSpacing.lg),
            SettingsTile(
              title: isBlocked ? 'Unblock contact' : 'Block contact',
              leadingIcon: Icons.block_rounded,
              onTap: onBlock,
            ),
            IListDivider(indent: AppSpacing.lg),
            SettingsTile(
              title: context.l10n.deleteContact,
              leadingIcon: Icons.delete_outline_rounded,
              leadingIconColor: context.c.onDanger,
              titleColor: context.c.onDanger,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
