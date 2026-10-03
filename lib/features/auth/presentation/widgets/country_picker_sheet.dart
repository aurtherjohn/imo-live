import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/country.dart';
import '../../../../core/utils/l10n.dart';

/// Opens the country picker and resolves to the chosen country, or null if the
/// sheet was dismissed.
///
/// A modal bottom sheet rather than a full route: choosing a dial code is a
/// detour inside the phone form, not a destination. Keeping the form mounted
/// underneath means the number the user already typed is still there when the
/// sheet closes — a `push` would rebuild the screen and lose it.
Future<Country?> showCountryPicker(
  BuildContext context, {
  Country? selected,
}) {
  return showModalBottomSheet<Country>(
    context: context,
    // Scroll-controlled so the sheet can take most of the screen and still let
    // the keyboard push it up.
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (BuildContext sheetContext) =>
        _CountryPickerSheet(selected: selected),
  );
}

/// The sheet body: a search field over the full calling-code table.
///
/// Hard-coded to the dark palette on purpose. The auth screens run *before* the
/// user has any settings, so they must not read the persisted theme — see
/// `AuthScaffold`.
class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({this.selected});

  final Country? selected;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late List<Country> _results = Countries.all;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _results = Countries.search(value));
    // A new result set starts at the top; leaving the old offset would land the
    // user in the middle of an unrelated list.
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.of(context).size.height * 0.86;
    return Padding(
      // Lifts the sheet above the keyboard so the search field stays visible.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: <Widget>[
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        context.l10n.selectCountry,
                        style: const TextStyle(
                          color: AppColors.darkTextPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.close,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.darkTextSecondary,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                ),
                child: TextField(
                  controller: _query,
                  autofocus: false,
                  onChanged: _onQueryChanged,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.search,
                  cursorColor: AppColors.accent,
                  style: const TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: context.l10n.searchCountryOrCode,
                    hintStyle: const TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: AppColors.darkTextSecondary,
                    ),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: context.l10n.cancel,
                            onPressed: () {
                              _query.clear();
                              _onQueryChanged('');
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: AppColors.darkTextSecondary,
                          ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.055),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.rMd,
                      borderSide:
                          BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadius.rMd,
                      borderSide:
                          BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: AppRadius.rMd,
                      borderSide:
                          BorderSide(color: AppColors.accent, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              Expanded(
                child: _results.isEmpty
                    ? _EmptyResults(message: context.l10n.noCountryMatchesSearch)
                    : ListView.builder(
                        controller: _scroll,
                        // The whole table is a fixed ~250 rows of pure text, so
                        // building them lazily costs nothing and keeps the first
                        // frame cheap.
                        itemCount: _results.length,
                        itemExtent: 56,
                        itemBuilder: (BuildContext context, int index) {
                          final Country country = _results[index];
                          return _CountryRow(
                            country: country,
                            isSelected:
                                country.isoCode == widget.selected?.isoCode,
                            onTap: () => Navigator.of(context).pop(country),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.country,
    required this.isSelected,
    required this.onTap,
  });

  final Country country;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Row(
          children: <Widget>[
            // The flag is a font ligature, so it needs a fallback font size and
            // no tint — a colour filter would flatten it to a rectangle.
            Text(country.flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                country.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.darkTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              country.dial,
              style: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(
              width: 26,
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppColors.accent,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.public_off_rounded,
              size: 34,
              color: AppColors.darkTextSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The drag affordance at the top of a modal sheet.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: AppRadius.rPill,
        ),
      ),
    );
  }
}
