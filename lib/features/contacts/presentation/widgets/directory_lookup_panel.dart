import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/services/remote_contact_service.dart';
import '../../../../core/widgets/i_avatar.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../../../../core/utils/l10n.dart';

/// The state of a "is this number on Imo LIVE?" probe.
enum DirectoryProbeState { idle, searching, found, notFound, unavailable }

/// The result of a probe, ready to render.
@immutable
class DirectoryProbe {
  const DirectoryProbe({
    required this.state,
    this.profile,
    this.query = '',
  });

  const DirectoryProbe.idle() : this(state: DirectoryProbeState.idle);

  final DirectoryProbeState state;
  final RemoteProfile? profile;

  /// The identifier that produced this result, so stale results can be told
  /// apart from the value currently in the field.
  final String query;
}

/// Owns the debounced real-time lookup for one identifier.
///
/// Kept separate from the widget so the same behaviour drives both the
/// "New contact" phone field and the smart search bar. Firestore is queried
/// live — there is no local directory cache — because a phone number that was
/// just registered elsewhere on another device must resolve immediately.
class DirectoryProbeController extends ChangeNotifier {
  DirectoryProbeController(this._service);

  final RemoteContactService _service;

  Timer? _debounce;
  int _generation = 0;
  bool _disposed = false;
  DirectoryProbe _value = const DirectoryProbe.idle();

  DirectoryProbe get value => _value;

  /// Fires a lookup 350 ms after the last keystroke.
  void probe(String raw, {Duration debounce = const Duration(milliseconds: 350)}) {
    _debounce?.cancel();
    final String query = raw.trim();
    if (query.length < 6) {
      _emit(const DirectoryProbe.idle());
      return;
    }
    _emit(DirectoryProbe(state: DirectoryProbeState.searching, query: query));
    _debounce = Timer(debounce, () => _run(query));
  }

  /// Runs a lookup immediately, bypassing the debounce (e.g. on submit).
  Future<DirectoryProbe> probeNow(String raw) async {
    _debounce?.cancel();
    final String query = raw.trim();
    if (query.isEmpty) {
      _emit(const DirectoryProbe.idle());
      return _value;
    }
    _emit(DirectoryProbe(state: DirectoryProbeState.searching, query: query));
    await _run(query);
    return _value;
  }

  Future<void> _run(String query) async {
    final int generation = ++_generation;
    final LookupResult result = await _service.findByAnyIdentifier(query);
    // A later keystroke already started a newer query — drop this one.
    if (_disposed || generation != _generation) return;

    switch (result) {
      case LookupResult(isFound: true, profile: final RemoteProfile profile):
        _emit(DirectoryProbe(
          state: DirectoryProbeState.found,
          profile: profile,
          query: query,
        ));
      case LookupResult(isUnavailable: true):
        _emit(DirectoryProbe(
          state: DirectoryProbeState.unavailable,
          query: query,
        ));
      default:
        _emit(DirectoryProbe(
          state: DirectoryProbeState.notFound,
          query: query,
        ));
    }
  }

  void reset() {
    _debounce?.cancel();
    _generation++;
    _emit(const DirectoryProbe.idle());
  }

  void _emit(DirectoryProbe next) {
    if (_disposed) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}

/// Renders the live result for [probe] under a form field.
///
/// Three distinct outcomes, matching the WhatsApp-style behaviour:
/// * found → the real profile (avatar, name, @handle, verified badge) plus a
///   "This user is on Imo LIVE" banner and an "Add" action;
/// * not found → "This number is not on Imo LIVE yet. Invite them?" + Invite;
/// * unavailable → a neutral message, never the invite prompt, so a network
///   blip is not mistaken for "no account".
class DirectoryLookupPanel extends StatelessWidget {
  const DirectoryLookupPanel({
    super.key,
    required this.probe,
    this.onAdd,
    this.onInvite,
    this.onOpenChat,
    this.compact = false,
  });

  final DirectoryProbe probe;

  /// Called with the resolved profile when the user taps "Add contact".
  final ValueChanged<RemoteProfile>? onAdd;

  /// Called with the raw identifier when the user taps "Invite".
  final ValueChanged<String>? onInvite;

  /// Called when the user taps the resolved row itself (open the chat).
  final ValueChanged<RemoteProfile>? onOpenChat;

  /// Tightens paddings for use inside a search list.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final EdgeInsets margin = compact
        ? const EdgeInsets.only(top: AppSpacing.sm)
        : const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          );

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: switch (probe.state) {
        DirectoryProbeState.idle => const SizedBox(width: double.infinity),
        DirectoryProbeState.searching => Padding(
            padding: margin,
            child: Row(
              children: <Widget>[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  context.l10n.checkingImoLIVE,
                  style: context.t.bodySmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        DirectoryProbeState.found => Padding(
            padding: margin,
            child: _FoundCard(
              profile: probe.profile!,
              onAdd: onAdd,
              onOpenChat: onOpenChat,
            ),
          ),
        DirectoryProbeState.notFound => Padding(
            padding: margin,
            child: _NotFoundCard(
              query: probe.query,
              onInvite: onInvite,
            ),
          ),
        DirectoryProbeState.unavailable => Padding(
            padding: margin,
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.cloud_off_rounded,
                  size: 15,
                  color: c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    context.l10n.couldNotReachImoLIVE,
                    style: context.t.bodySmall?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      },
    );
  }
}

class _FoundCard extends StatelessWidget {
  const _FoundCard({required this.profile, this.onAdd, this.onOpenChat});

  final RemoteProfile profile;
  final ValueChanged<RemoteProfile>? onAdd;
  final ValueChanged<RemoteProfile>? onOpenChat;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: AppRadius.rLg,
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.45),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: onOpenChat == null ? null : () => onOpenChat!(profile),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: <Widget>[
                    IAvatar(
                      name: profile.name.isEmpty ? profile.handle : profile.name,
                      imageUrl: profile.hasAvatar ? profile.avatarUrl : null,
                      size: AppSizes.avatarMd,
                      isOnline: profile.isOnline,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  profile.name.isEmpty
                                      ? (profile.handle.isEmpty
                                          ? profile.phone
                                          : profile.handle)
                                      : profile.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.t.titleSmall,
                                ),
                              ),
                              if (profile.isVerified) ...<Widget>[
                                const SizedBox(width: 5),
                                const VerifiedBadge(size: 15),
                              ],
                            ],
                          ),
                          if (profile.handle.isNotEmpty)
                            Text(
                              profile.handle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.t.bodySmall?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (onAdd != null)
                      TextButton(
                        onPressed: () => onAdd!(profile),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                        ),
                        child: Text(
                          context.l10n.add,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: AppColors.accent.withValues(alpha: 0.10),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.verified_user_rounded,
                    size: 14,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      context.l10n.thisUserIsOnImo,
                      style: context.t.bodySmall?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFoundCard extends StatelessWidget {
  const _NotFoundCard({required this.query, this.onInvite});

  final String query;
  final ValueChanged<String>? onInvite;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: AppRadius.rLg,
          border: Border.all(color: c.divider, width: 0.8),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.inputFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_search_rounded,
                size: 19,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                context.l10n.thisNumberIsNotOn,
                style: context.t.bodySmall?.copyWith(color: c.textSecondary),
              ),
            ),
            if (onInvite != null)
              TextButton(
                onPressed: () => onInvite!(query),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                ),
                child: Text(
                  context.l10n.invite,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Provider-backed probe controller, one per widget key.
final ProviderFamily<DirectoryProbeController, String>
    directoryProbeProvider =
    Provider.family<DirectoryProbeController, String>((Ref ref, String key) {
  final DirectoryProbeController controller = DirectoryProbeController(
    ref.watch(remoteContactServiceProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
