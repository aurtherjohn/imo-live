import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/theme/app_color_scheme.dart';

import '../../../app/app.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/country_data.dart';
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
/// Only the things the user actually chooses are editable — name, about, age,
/// gender and a photo. The **handle, phone number and country are generated at
/// signup** and shown here read-only: the handle is how other people find the
/// account, and the phone number is the account's identity, so neither can be
/// quietly rewritten from an onboarding form. See
/// `FirebaseAuthService._createUserDocument`.
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

  /// The number the account was created with, and the country it implies.
  ///
  /// Both are read-only here. They are resolved from the stored digits rather
  /// than read back as separate fields so the country has exactly one source of
  /// truth — the same `CountryData.byDialPrefix` the signup writer used.
  String _phone = '';
  String _countryLabel = '';

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

    _phone = remote?.phone ?? '';
    // A phone signup always has the number on the profile; the auth address is
    // the fallback for a document that predates the field, because the digits
    // are encoded in it (`p8801712345678@phone.imolive.app`).
    final String digits = _digits(_phone.isEmpty
        ? _digitsFromAuthEmail(auth.currentUser?.email ?? '')
        : _phone);
    _countryLabel = CountryData.byDialPrefix(digits)?.name ?? '';

    setState(() => _loading = false);
  }

  /// `+8801712345678` → `8801712345678`.
  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  /// Recovers the E.164 digits from a derived phone address.
  static String _digitsFromAuthEmail(String email) {
    if (!AppConstants.isPhoneAuthEmail(email)) return '';
    final int at = email.lastIndexOf('@');
    if (at <= 0) return '';
    return _digits(email.substring(0, at));
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
                    // Read-only: the handle is generated at signup and is how
                    // other people find this account, so an onboarding form must
                    // not be able to rewrite it.
                    enabled: false,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(
                      left: AppSpacing.md,
                      top: AppSpacing.sm,
                    ),
                    child: _LockHint(
                      text: 'Your handle was generated for you and cannot be '
                          'changed here.',
                    ),
                  ),
                ],
              ),
            ),
            if (_phone.isNotEmpty || _countryLabel.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              FadeSlideIn(
                delay: const Duration(milliseconds: 155),
                child: _LockedIdentity(
                  phone: _phone,
                  country: _countryLabel,
                ),
              ),
            ],
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
              label: widget.isOnboarding ? context.l10n.finishSetup : context.l10n.saveChanges,
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

/// A one-line explanation under a field that cannot be edited.
class _LockHint extends StatelessWidget {
  const _LockHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.lock_outline_rounded,
          size: 13,
          color: Colors.white.withValues(alpha: 0.45),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }
}

/// The phone number and country the account was created with, read-only.
///
/// Rendered as a locked card rather than two disabled inputs: a greyed-out
/// `TextField` still looks like something the user is expected to fill in, and
/// the point here is the opposite — these values were decided at signup and
/// there is nothing to type.
class _LockedIdentity extends StatelessWidget {
  const _LockedIdentity({required this.phone, required this.country});

  final String phone;
  final String country;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: AppRadius.rMd,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (phone.isNotEmpty) ...<Widget>[
            _row('Phone number', phone.startsWith('+') ? phone : '+$phone'),
            if (country.isNotEmpty) const SizedBox(height: AppSpacing.md),
          ],
          if (country.isNotEmpty) _row('Country', country),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.lock_outline_rounded,
                size: 13,
                color: Colors.white.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.l10n.setFromYourNumberAt,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
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
