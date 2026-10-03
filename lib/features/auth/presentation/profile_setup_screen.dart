import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/theme/app_color_scheme.dart';

import '../../../app/app.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/contact.dart';
import '../../../core/services/firebase_auth_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/remote_contact_service.dart';
import '../../../core/widgets/brand_assets.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import 'auth_providers.dart';
import 'widgets/auth_widgets.dart';
import '../../../core/utils/l10n.dart';

/// The last step of onboarding: who you are.
///
/// Name, handle, bio, age, gender and a photo. The handle is checked against
/// the directory live, so the user finds out it is taken while typing rather
/// than after tapping Save.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key, this.isOnboarding = true});

  /// Onboarding shows a "skip for now" escape; editing from Settings does not.
  final bool isOnboarding;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _bio = TextEditingController();
  final TextEditingController _age = TextEditingController();

  String _gender = '';
  bool _saving = false;
  bool _loading = true;

  /// Live handle availability: null while unknown or unchecked.
  bool? _usernameAvailable;
  bool _checkingUsername = false;
  Timer? _usernameDebounce;
  String? _error;

  /// Locally picked avatar before upload.
  String? _localAvatarPath;
  String _remoteAvatarUrl = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    _age.dispose();
    super.dispose();
  }

  /// Pre-fills from the account Firebase created, then from the Firestore
  /// profile when one exists.
  Future<void> _load() async {
    final FirebaseAuthService auth = ref.read(firebaseAuthServiceProvider);
    final String uid = auth.currentUid;
    if (uid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final RemoteProfile? remote =
        await ref.read(remoteContactServiceProvider).findByUid(uid).then(
              (LookupResult result) => result.profile,
            );
    if (!mounted) return;

    if (remote != null) {
      _name.text = remote.name;
      _username.text = remote.username;
      _bio.text = remote.bio;
      _remoteAvatarUrl = remote.avatarUrl;
    } else {
      _name.text = auth.currentUser?.displayName ?? '';
    }
    _usernameAvailable = true; // their own handle is always available
    setState(() => _loading = false);
  }

  Future<void> _checkUsername(String value) async {
    _usernameDebounce?.cancel();
    final String candidate = RemoteContactService.normaliseUsername(value);
    if (candidate.isEmpty) {
      setState(() {
        _usernameAvailable = null;
        _checkingUsername = false;
      });
      return;
    }
    setState(() => _checkingUsername = true);
    // Debounced so a fast typist produces one query, not ten.
    _usernameDebounce = Timer(const Duration(milliseconds: 420), () async {
      final bool free =
          await ref.read(firebaseAuthServiceProvider).isUsernameAvailable(candidate);
      if (!mounted) return;
      setState(() {
        _usernameAvailable = free;
        _checkingUsername = false;
      });
    });
  }

  Future<void> _pickAvatar() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (file == null || !mounted) return;

    final String? url = await ref
        .read(storageServiceProvider)
        .uploadAvatar(file.path, ref.read(currentUidProvider));
    if (!mounted) return;
    if (url == null) {
      iToast(
        context,
        context.l10n.thePhotoCouldNotBe,
        isError: true,
      );
      // Keep the local copy so the profile still shows the picture the user
      // picked, even though it could not be shared yet.
      setState(() => _localAvatarPath = file.path);
      return;
    }
    setState(() {
      _remoteAvatarUrl = url;
      // Keep the local copy too, so the preview is instant even before the
      // network image resolves.
      _localAvatarPath = file.path;
    });
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    if (_usernameAvailable == false) {
      setState(() => _error = 'That handle is taken. Pick another one.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final FirebaseAuthService auth =
          ref.read(firebaseAuthServiceProvider);
      await auth.updateProfile(
        name: name,
        username: _username.text.trim(),
        bio: _bio.text.trim(),
        age: int.tryParse(_age.text.trim()) ?? 0,
        gender: _gender,
        avatarUrl: _remoteAvatarUrl.isEmpty ? null : _remoteAvatarUrl,
      );
      // The local self-profile mirrors the same values so the app's own
      // screens do not need a network read to show the user's name.
      await ref.read(selfProfileProvider.notifier).save(
            (ref.read(selfProfileProvider).valueOrNull ??
                    const Contact(id: 'self', firstName: ''))
                .copyWith(
              firstName: name.split(' ').first,
              lastName: name.split(' ').skip(1).join(' '),
              username: RemoteContactService.normaliseUsername(_username.text),
              bio: _bio.text.trim(),
              avatarPath: _localAvatarPath,
            ),
          );
      ref.invalidate(remoteProfileProvider);
      if (!mounted) return;
      iToast(context, context.l10n.profileSaved);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AuthScaffold(child: Center(child: ILoader(size: 26)));
    }

    return AuthScaffold(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.xl,
          AppSpacing.xxl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: AppSpacing.lg),
            FadeSlideIn(
              child: Column(
                children: <Widget>[
                  Text(
                    context.l10n.setUpYourProfile,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.thisIsHowOtherPeople,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ---------------------------------------------------- avatar
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Column(
                    children: <Widget>[
                      Stack(
                        children: <Widget>[
                          IAvatar(
                            name: _name.text.trim().isEmpty
                                ? 'You'
                                : _name.text.trim(),
                            imagePath: _localAvatarPath,
                            imageUrl: _remoteAvatarUrl.isEmpty
                                ? null
                                : _remoteAvatarUrl,
                            size: 104,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                gradient: kAuthPrimaryGradient,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.darkBg,
                                  width: 2.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.photo_camera_rounded,
                                size: 17,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        context.l10n.addAPhoto,
                        style: TextStyle(
                          color: AppColors.accentLight,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ------------------------------------------------------ form
            FadeSlideIn(
              delay: const Duration(milliseconds: 110),
              child: AuthField(
                controller: _name,
                hint: context.l10n.yourName,
                iconAsset: BrandAssets.userCheck,
                capitalization: TextCapitalization.words,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AuthField(
                    controller: _username,
                    hint: context.l10n.username2,
                    iconAsset: BrandAssets.userCheck,
                    prefixText: '@',
                    enabled: !_saving,
                    onChanged: _checkUsername,
                  ),
                  if (_checkingUsername || _usernameAvailable != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.md,
                        top: AppSpacing.sm,
                      ),
                      child: Row(
                        children: <Widget>[
                          if (_checkingUsername)
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.6),
                            )
                          else
                            Icon(
                              _usernameAvailable == true
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              size: 14,
                              color: _usernameAvailable == true
                                  ? context.c.onSuccess
                                  : context.c.onDanger,
                            ),
                          SizedBox(width: 6),
                          Text(
                            _checkingUsername
                                ? 'Checking…'
                                : _usernameAvailable == true
                                    ? 'Available'
                                    : 'Already taken',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _checkingUsername
                                  ? Colors.white54
                                  : _usernameAvailable == true
                                      ? context.c.onSuccess
                                      : context.c.onDanger,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FadeSlideIn(
              delay: const Duration(milliseconds: 170),
              child: AuthField(
                controller: _bio,
                hint: context.l10n.aboutAShortLineAbout,
                iconAsset: BrandAssets.userCheck,
                enabled: !_saving,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: AuthField(
                    controller: _age,
                    hint: context.l10n.age,
                    iconAsset: BrandAssets.userCheck,
                    keyboardType: TextInputType.number,
                    enabled: !_saving,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _GenderPicker(
                    value: _gender,
                    enabled: !_saving,
                    onChanged: (String v) => setState(() => _gender = v),
                  ),
                ),
              ],
            ),

            AnimatedSize(
              duration: AppDurations.fast,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.c.onDanger,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: AppSpacing.xxl),
            AuthPrimaryButton(
              label: widget.isOnboarding ? 'Finish setup' : 'Save changes',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
            if (widget.isOnboarding) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => ref.read(authControllerProvider.notifier).signOut(),
                child: Text(
                  context.l10n.signOut,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

/// A compact gender selector styled like the surrounding fields.
class _GenderPicker extends StatelessWidget {
  const _GenderPicker({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  static const List<String> _options = <String>[
    'Female',
    'Male',
    'Other',
    'Prefer not to say',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: AppRadius.rMd,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value.isEmpty ? null : value,
          hint: Text(
            context.l10n.gender,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 15,
            ),
          ),
          isExpanded: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          dropdownColor: AppColors.darkCard,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          onChanged: enabled
              ? (String? v) => onChanged(v ?? '')
              : null,
          items: _options
              .map(
                (String option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
