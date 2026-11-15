import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/settings.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/utils/l10n.dart';
import '../../chats/presentation/providers.dart';

/// First-run welcome screen: language, country and name before anything else.
///
/// Shown only once — after completion the user is never sent back unless they
/// reset the app. Flows into [PermissionGrantScreen], where the user picks
/// whether permissions are requested all at once or just-in-time.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _page = 0;
  String? _selectedLanguage;
  Country? _selectedCountry;
  final TextEditingController _nameController = TextEditingController();
  String _languageQuery = '';
  String _countryQuery = '';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canContinue {
    if (_page == 0) {
      return _selectedLanguage != null && _selectedCountry != null;
    }
    return _nameController.text.trim().isNotEmpty;
  }

  Future<void> _finish() async {
    final String language = _selectedLanguage ?? 'en';
    final Country country = _selectedCountry!;
    final String name = _nameController.text.trim();

    await ref.read(settingsRepositoryProvider).markOnboardingComplete(
          languageCode: language,
          countryCode: country.iso,
          countryName: country.name,
          userName: name,
          permissionMode: PermissionMode.justInTime,
        );

    if (mounted) context.push(AppRoutes.permissionGrant);
  }

  Widget _buildSearchField({
    required String label,
    required String query,
    required ValueChanged<String> onChanged,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: ITextField(
        hint: label,
        autofocus: true,
        onChanged: onChanged,
        prefixIcon: Icon(icon, size: 20, color: context.c.textSecondary),
      ),
    );
  }

  Widget _buildLanguageList() {
    final List<({String code, String name, String nativeName})> filtered =
        onboardingLanguages.where((l) {
      final q = _languageQuery.toLowerCase();
      return l.name.toLowerCase().contains(q) ||
          l.nativeName.toLowerCase().contains(q);
    }).toList();

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (BuildContext context, int index) {
        final item = filtered[index];
        final bool selected = _selectedLanguage == item.code;
        return SettingsTile(
          title: item.name,
          subtitle: item.nativeName,
          leading: Text(
            item.code.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          trailing: selected ? const Icon(Icons.check) : null,
          onTap: () => setState(() => _selectedLanguage = item.code),
        );
      },
    );
  }

  Widget _buildCountryList() {
    final List<Country> filtered = onboardingCountries.where((c) {
      final q = _countryQuery.toLowerCase();
      return c.name.toLowerCase().contains(q) ||
          c.nativeName.toLowerCase().contains(q) ||
          c.dialCode.contains(q);
    }).toList();

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (BuildContext context, int index) {
        final c = filtered[index];
        final bool selected = _selectedCountry?.iso == c.iso;
        return SettingsTile(
          title: '${c.flagEmoji}  ${c.name}',
          subtitle: '${c.dialCode}  •  ${c.nativeName}',
          trailing: selected ? const Icon(Icons.check) : null,
          onTap: () => setState(() => _selectedCountry = c),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: context.c.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _page == 0
                        ? l10n.onboardingWelcomeTitle
                        : l10n.onboardingNameTitle,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _page == 0
                        ? l10n.onboardingWelcomeSubtitle
                        : l10n.onboardingNameSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: context.c.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Content
            Expanded(
              child: _page == 0
                  ? Column(
                      children: <Widget>[
                        _buildSearchField(
                          label: l10n.onboardingSearchLanguage,
                          query: _languageQuery,
                          icon: Icons.search,
                          onChanged: (v) => setState(() => _languageQuery = v),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: _selectedLanguage == null
                              ? _buildLanguageList()
                              : Column(
                                  children: <Widget>[
                                    // Selected language chip
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.md,
                                      ),
                                      child: IPill(
                                        label:
                                            '${onboardingLanguages.firstWhere((l) => l.code == _selectedLanguage).name}  ${l10n.onboardingSelected}',
                                        filled: true,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    Expanded(
                                      child: _buildLanguageList(),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    )
                  : Column(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (_selectedCountry != null)
                                IPill(
                                  label:
                                      '${_selectedCountry!.flagEmoji}  ${_selectedCountry!.name}  ${l10n.onboardingSelected}',
                                  filled: true,
                                ),
                              if (_selectedCountry != null)
                                const SizedBox(height: AppSpacing.md),
                              _buildSearchField(
                                label: l10n.onboardingSearchCountry,
                                query: _countryQuery,
                                icon: Icons.search,
                                onChanged: (v) => setState(() => _countryQuery = v),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Expanded(
                                child: _selectedCountry == null
                                    ? _buildCountryList()
                                    : Column(
                                        children: <Widget>[
                                          const SizedBox(height: AppSpacing.md),
                                          Expanded(
                                            child: _buildCountryList(),
                                          ),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                ),
                                child: ITextField(
                                  controller: _nameController,
                                  hint: l10n.onboardingNameHint,
                                  prefixIcon: const Icon(
                                    Icons.person_outline_rounded,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),

            // Footer buttons
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  if (_page == 1)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _page = 0),
                        child: Text(l10n.onboardingBack),
                      ),
                    ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _canContinue ? _finish : null,
                      child: Text(
                        _page == 0
                            ? l10n.onboardingContinue
                            : l10n.onboardingFinish,
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
