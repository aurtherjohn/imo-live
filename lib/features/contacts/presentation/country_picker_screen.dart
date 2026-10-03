import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/country_data.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/settings.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/utils/l10n.dart';

/// A searchable, full country / dial-code picker.
///
/// Pops the selected [Country] so callers can prefill a phone field.
class CountryPickerScreen extends ConsumerStatefulWidget {
  const CountryPickerScreen({super.key});

  @override
  ConsumerState<CountryPickerScreen> createState() =>
      _CountryPickerScreenState();
}

class _CountryPickerScreenState extends ConsumerState<CountryPickerScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Country> get _results {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return CountryData.all;
    return CountryData.all
        .where(
          (Country c) =>
              c.name.toLowerCase().contains(q) ||
              c.nativeName.toLowerCase().contains(q) ||
              c.iso.toLowerCase() == q ||
              c.dialCode.replaceAll('+', '').startsWith(q.replaceAll('+', '')),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<Country> results = _results;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.chooseACountry),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: ISearchBar(
              hint: context.l10n.searchCountryCodeOrDial,
              controller: _controller,
              autofocus: true,
              onChanged: (String value) => setState(() => _query = value),
            ),
          ),
          if (results.isEmpty)
            Expanded(
              child: EmptyState(
                icon: Icons.public_off_rounded,
                title: context.l10n.noMatchingCountry,
                message: context.l10n.tryADifferentNameOr2,
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (BuildContext context, int index) {
                  final Country country = results[index];
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(country),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm + 2,
                      ),
                      child: Row(
                        children: <Widget>[
                          Text(
                            country.flagEmoji,
                            style: const TextStyle(fontSize: 26),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  country.name,
                                  style: context.t.bodyLarge?.copyWith(
                                    color: context.c.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (country.nativeName.isNotEmpty &&
                                    country.nativeName != country.name) ...<Widget>[
                                  const SizedBox(height: 1),
                                  Text(
                                    country.nativeName,
                                    style: context.t.bodySmall?.copyWith(
                                      color: context.c.textSecondary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            country.dialCode,
                            style: context.t.bodyMedium?.copyWith(
                              color: context.c.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                context.l10n.countriesAndTerritoriesStoresYour(CountryData.all.length, AppConstants.appName),
                textAlign: TextAlign.center,
                style: context.t.bodySmall?.copyWith(
                  color: context.c.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper used by the new-contact form to resolve a dial code from an ISO code.
Country? countryForIso(String iso) {
  if (iso.isEmpty) return null;
  for (final Country country in CountryData.all) {
    if (country.iso.toUpperCase() == iso.toUpperCase()) return country;
  }
  return null;
}
