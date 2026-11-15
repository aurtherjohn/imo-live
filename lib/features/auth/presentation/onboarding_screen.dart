import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app.dart'
    show FadeSlideIn, ListStagger, ValueSwap, prefersReducedMotion;
import '../../../app/auth_gate.dart' show setOnboardingState;
import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/settings.dart';
import '../../../core/utils/l10n.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../chats/presentation/providers.dart';

/// First-run welcome screen: language and country on one page.
///
/// The flow this screen starts is deliberately short — pick a language, pick a
/// country, continue. The name is asked later, on the profile-setup screen the
/// auth gate shows once the user has an account, and [PermissionGrantScreen]
/// owns everything after Continue.
///
/// Both pickers open a searchable bottom sheet rather than navigating away: a
/// sheet keeps the screen — and the user's sense of place — intact, and the
/// search bar is what makes the country list usable instead of a scroll
/// gamble. Selecting a language applies it to the whole app immediately, so
/// the labels that follow already speak the user's choice.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  String? _selectedLanguage;
  Country? _selectedCountry;

  @override
  void initState() {
    super.initState();
    _restoreSavedChoices();
  }

  /// A run that was closed mid-flow resumes where it left off: the saved
  /// language and country come back as the pre-selected values. The language
  /// is deliberately *not* re-applied to [languageProvider] here — that
  /// happens on an explicit tap, so merely reopening the screen never rewrites
  /// the app's language setting.
  Future<void> _restoreSavedChoices() async {
    try {
      final OnboardingSettings saved = await ref
          .read(settingsRepositoryProvider)
          .getOnboarding();
      if (!mounted) return;
      setState(() {
        if (onboardingLanguages.any((l) => l.code == saved.languageCode)) {
          _selectedLanguage = saved.languageCode;
        }
        for (final Country country in onboardingCountries) {
          if (country.iso == saved.countryCode) {
            _selectedCountry = country;
            break;
          }
        }
      });
    } on Object catch (error) {
      // No saved state (or storage is down) — the pickers simply start empty.
      debugPrint('Could not restore onboarding choices: $error');
    }
  }

  bool get _canContinue =>
      _selectedLanguage != null && _selectedCountry != null;

  /// Persists the choices *without* completing onboarding — the permission
  /// screen that follows owns completion. If the process dies there, the next
  /// launch resumes on that screen rather than silently skipping it, and
  /// closing the app here just reopens onboarding with the choices pre-filled.
  Future<void> _continue() async {
    final String language = _selectedLanguage ?? 'en';
    final Country country = _selectedCountry ?? onboardingCountries.first;
    final OnboardingSettings state = OnboardingSettings(
      complete: false,
      languageCode: language,
      countryCode: country.iso,
      countryName: country.name,
    );
    try {
      await ref.read(settingsRepositoryProvider).saveOnboarding(state);
      // The gate answers redirects from its cached snapshot; without this the
      // pushed permission screen would be bounced straight back here until
      // the app restarted.
      setOnboardingState(state);
    } on Object catch (error) {
      debugPrint('Could not save onboarding choices: $error');
    }
    if (mounted) context.push(AppRoutes.permissionGrant);
  }

  // --------------------------------------------------------------- pickers

  Future<String?> _showSheet({
    required String title,
    required String searchHint,
    required String emptyLabel,
    required List<_SheetItem> items,
    required String? selectedId,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (BuildContext sheetContext) => _SearchableSheet(
        title: title,
        searchHint: searchHint,
        emptyLabel: emptyLabel,
        items: items,
        selectedId: selectedId,
      ),
    );
  }

  Future<void> _pickLanguage() async {
    final l10n = context.l10n;
    final List<_SheetItem> items = <_SheetItem>[
      for (final ({String code, String name, String nativeName}) language
          in onboardingLanguages)
        _SheetItem(
          id: language.code,
          leading: _CodeAvatar(code: language.code),
          title: language.name,
          subtitle: language.nativeName == language.name
              ? ''
              : language.nativeName,
        ),
    ];
    final String? picked = await _showSheet(
      title: l10n.selectLanguage,
      searchHint: l10n.onboardingSearchLanguage,
      emptyLabel: l10n.noResults,
      items: items,
      selectedId: _selectedLanguage,
    );
    if (picked == null || !mounted || picked == _selectedLanguage) return;
    setState(() => _selectedLanguage = picked);
    // Switch the whole app right away — the sheet, this screen and everything
    // after it follow the choice with no restart.
    await ref.read(languageProvider.notifier).select(picked);
  }

  Future<void> _pickCountry() async {
    final l10n = context.l10n;
    final List<_SheetItem> items = <_SheetItem>[
      for (final Country country in onboardingCountries)
        _SheetItem(
          id: country.iso,
          leading: _FlagAvatar(emoji: country.flagEmoji),
          title: country.name,
          subtitle: '${country.dialCode}  ·  ${country.nativeName}',
        ),
    ];
    final String? picked = await _showSheet(
      title: l10n.selectCountry,
      searchHint: l10n.onboardingSearchCountry,
      emptyLabel: l10n.noMatchingCountry,
      items: items,
      selectedId: _selectedCountry?.iso,
    );
    if (picked == null || !mounted) return;
    for (final Country country in onboardingCountries) {
      if (country.iso == picked) {
        setState(() => _selectedCountry = country);
        return;
      }
    }
  }

  // ------------------------------------------------------------- labelling

  /// The selected language as shown in the field, e.g. `English · বাংলা`.
  String? get _languageDisplay {
    for (final ({String code, String name, String nativeName}) language
        in onboardingLanguages) {
      if (language.code == _selectedLanguage) {
        return language.nativeName == language.name
            ? language.name
            : '${language.name} · ${language.nativeName}';
      }
    }
    return null;
  }

  /// The selected country as shown in the field, e.g. `🇧🇩 Bangladesh · +880`.
  String? get _countryDisplay {
    final Country? country = _selectedCountry;
    if (country == null) return null;
    return '${country.flagEmoji}  ${country.name}  ·  ${country.dialCode}';
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: context.c.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Phones get the natural layout; tablets and foldables stop the
            // content from stretching edge to edge.
            constraints: const BoxConstraints(
              maxWidth: AppSizes.maxContentWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              // The page is compact, but a small landscape window is still
              // shorter than title + two fields + button. The scroll view with
              // a min-height is the same contract the auth screens use: the
              // layout centers when it fits and scrolls when it does not, so
              // neither state can overflow.
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const SizedBox(height: AppSpacing.xl),
                            FadeSlideIn(
                              child: Text(
                                l10n.onboardingWelcomeTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            FadeSlideIn(
                              delay: const Duration(milliseconds: 60),
                              child: Text(
                                l10n.onboardingWelcomeSubtitle,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: context.c.textSecondary),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxl),
                            FadeSlideIn(
                              delay: const Duration(milliseconds: 120),
                              child: _SelectorField(
                                label: l10n.language,
                                hint: l10n.selectLanguage,
                                value: _languageDisplay,
                                icon: Icons.translate_rounded,
                                onTap: _pickLanguage,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            FadeSlideIn(
                              delay: const Duration(milliseconds: 180),
                              child: _SelectorField(
                                label: l10n.country,
                                hint: l10n.selectCountry,
                                value: _countryDisplay,
                                icon: Icons.public_rounded,
                                onTap: _pickCountry,
                              ),
                            ),
                            const Spacer(),
                            FadeSlideIn(
                              delay: const Duration(milliseconds: 240),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _canContinue ? _continue : null,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.lg,
                                    ),
                                  ),
                                  child: Text(l10n.onboardingContinue),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ selector

/// The dropdown-looking field that opens a picker sheet.
///
/// Reads as a form field rather than a button: a labelled bubble, the current
/// value (or the hint before anything is chosen) and a chevron. The border
/// tints towards the accent once a value is picked, which is the only
/// acknowledgement the row needs.
class _SelectorField extends StatelessWidget {
  const _SelectorField({
    required this.label,
    required this.hint,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String hint;

  /// The selected value, or null while nothing is picked.
  final String? value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool filled = value != null;

    return Material(
      color: context.c.surface,
      borderRadius: AppRadius.rLg,
      child: InkWell(
        borderRadius: AppRadius.rLg,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          curve: AppDurations.curve,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rLg,
            border: Border.all(
              color: filled
                  ? context.c.accent.withValues(alpha: 0.45)
                  : context.c.divider,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.c.surfaceAlt,
                  borderRadius: AppRadius.rMd,
                ),
                child: Icon(icon, size: 20, color: context.c.textSecondary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.c.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    // [ValueSwap] makes a change read as the value arriving
                    // rather than the text flickering; the [ValueKey] is what
                    // tells [AnimatedSwitcher] a real change happened.
                    ValueSwap(
                      child: Text(
                        value ?? hint,
                        key: ValueKey<String>(value ?? ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: filled
                                  ? context.c.textPrimary
                                  : context.c.textSecondary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: context.c.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- picker sheet

/// One row of a picker sheet.
class _SheetItem {
  const _SheetItem({
    required this.id,
    required this.leading,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final Widget leading;
  final String title;
  final String subtitle;
}

/// A small round badge showing a language's code, e.g. `EN`.
class _CodeAvatar extends StatelessWidget {
  const _CodeAvatar({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.c.accent.withValues(alpha: 0.10),
        borderRadius: AppRadius.rPill,
      ),
      child: Text(
        code.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: context.c.accent, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// A small round badge showing a country's flag emoji.
class _FlagAvatar extends StatelessWidget {
  const _FlagAvatar({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.c.surfaceAlt,
        borderRadius: AppRadius.rPill,
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 20)),
    );
  }
}

/// The searchable bottom sheet behind both pickers.
///
/// A fixed fraction of the screen height keeps the sheet feeling like a sheet
/// rather than a second page, and the view-insets padding at the bottom is
/// what stops the keyboard from covering the list while searching.
class _SearchableSheet extends StatefulWidget {
  const _SearchableSheet({
    required this.title,
    required this.searchHint,
    required this.emptyLabel,
    required this.items,
    required this.selectedId,
  });

  final String title;
  final String searchHint;
  final String emptyLabel;
  final List<_SheetItem> items;
  final String? selectedId;

  @override
  State<_SearchableSheet> createState() => _SearchableSheetState();
}

class _SearchableSheetState extends State<_SearchableSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    // The sheet asks for most of the screen, but never more than what is
    // actually visible: with `useSafeArea` the top notch is already avoided,
    // and the keyboard rising from the bottom shrinks what is left. Skipping
    // this cap is how a sheet overflows the moment search opens the keyboard.
    final double screen = MediaQuery.sizeOf(context).height;
    final double visible =
        screen -
        MediaQuery.paddingOf(context).top -
        MediaQuery.viewInsetsOf(context).bottom;
    final double sheetHeight = math.min(screen * 0.78, visible);

    final List<_SheetItem> filtered = _query.trim().isEmpty
        ? widget.items
        : widget.items.where((_SheetItem item) {
            final String q = _query.trim().toLowerCase();
            return item.title.toLowerCase().contains(q) ||
                item.subtitle.toLowerCase().contains(q) ||
                item.id.toLowerCase().contains(q);
          }).toList();

    return Padding(
      // The keyboard rises from the bottom; without this it covers the list.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: AppSpacing.md),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.c.divider,
                  borderRadius: AppRadius.rPill,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: ITextField(
                hint: widget.searchHint,
                autofocus: true,
                onChanged: (String value) => setState(() => _query = value),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: context.c.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.search_off_rounded,
                            size: 32,
                            color: context.c.textSecondary,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            widget.emptyLabel,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: context.c.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      itemCount: filtered.length,
                      itemBuilder: (BuildContext context, int index) {
                        return ListStagger(
                          index: index,
                          child: _row(context, filtered[index]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _SheetItem item) {
    final bool selected = widget.selectedId == item.id;

    return InkWell(
      onTap: () => Navigator.of(context).pop(item.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: <Widget>[
            item.leading,
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (item.subtitle.isNotEmpty)
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.c.textSecondary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // The check scales in on selection instead of appearing, so the
            // tap visibly lands even at the bottom edge of the keyboard.
            AnimatedScale(
              scale: selected ? 1 : 0,
              duration: prefersReducedMotion(context)
                  ? Duration.zero
                  : AppDurations.fast,
              curve: AppDurations.emphasized,
              child: Icon(
                Icons.check_circle_rounded,
                size: 22,
                color: context.c.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
