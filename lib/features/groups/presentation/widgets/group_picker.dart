import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/widgets/i_avatar.dart';
import '../../../chats/presentation/providers.dart';
import '../../../../core/utils/l10n.dart';

/// A reusable multi-select contact picker sheet.
///
/// Returns the chosen [Contact]s, or `null` when dismissed. Used by group,
/// community, broadcast and forward flows so selection behaves identically
/// everywhere.
Future<List<Contact>?> pickContacts({
  required BuildContext context,
  required WidgetRef ref,
  Set<String> initiallySelected = const <String>{},
  String title = 'Add members',
  String searchHint = 'Search contacts',
  bool allowEmptyResult = false,
}) {
  return showModalBottomSheet<List<Contact>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => _ContactPickerSheet(
      ref: ref,
      title: title,
      searchHint: searchHint,
      initiallySelected: initiallySelected,
      allowEmptyResult: allowEmptyResult,
    ),
  );
}

class _ContactPickerSheet extends ConsumerStatefulWidget {
  const _ContactPickerSheet({
    required this.ref,
    required this.title,
    required this.searchHint,
    required this.initiallySelected,
    required this.allowEmptyResult,
  });

  final WidgetRef ref;
  final String title;
  final String searchHint;
  final Set<String> initiallySelected;
  final bool allowEmptyResult;

  @override
  ConsumerState<_ContactPickerSheet> createState() =>
      _ContactPickerSheetState();
}

class _ContactPickerSheetState extends ConsumerState<_ContactPickerSheet> {
  late final Set<String> _selected = <String>{...widget.initiallySelected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final List<Contact> all = ref.watch(contactsProvider).orEmpty;
    final String q = _query.trim().toLowerCase();
    final List<Contact> results = all
        .where((Contact contact) => !contact.isSelf && !contact.isBlocked)
        .where(
          (Contact contact) =>
              q.isEmpty ||
              contact.fullName.toLowerCase().contains(q) ||
              contact.phone.contains(q) ||
              contact.username.toLowerCase().contains(q),
        )
        .toList()
      ..sort((Contact a, Contact b) => a.sortedKey.compareTo(b.sortedKey));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        margin: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AppRadius.rXl,
          border: Border.all(color: c.divider, width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.divider,
                borderRadius: AppRadius.rPill,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _selected.isEmpty
                          ? widget.title
                          : context.l10n.selected(_selected.length),
                      style: context.t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      final List<Contact> picked = all
                          .where((Contact c) => _selected.contains(c.id))
                          .toList();
                      Navigator.of(context).pop(picked);
                    },
                    child: Text(context.l10n.done),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: ISearchBar(
                hint: widget.searchHint,
                onChanged: (String v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? EmptyState(
                      icon: Icons.person_search_rounded,
                      title: all.isEmpty ? context.l10n.noContactsYet : 'No matches',
                      message: all.isEmpty
                          ? 'Add a contact first, then pick members here.'
                          : 'Nothing matched "$_query".',
                      compact: true,
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (BuildContext context, int index) {
                        final Contact contact = results[index];
                        final bool selected = _selected.contains(contact.id);
                        return InkWell(
                          onTap: () => setState(() {
                            if (!_selected.remove(contact.id)) {
                              _selected.add(contact.id);
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.sm + 2,
                            ),
                            child: Row(
                              children: <Widget>[
                                IAvatar(
                                  name: contact.fullName,
                                  imagePath: contact.avatarPath,
                                  imageUrl: contact.avatarUrl,
                                  colorSeed: contact.avatarColor,
                                  size: AppSizes.avatarSm,
                                ),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(
                                  child: Text(
                                    contact.fullName,
                                    style: context.t.bodyLarge,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                AnimatedContainer(
                                  duration: AppDurations.fast,
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: selected
                                        ? c.accent
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: selected ? c.accent : c.textSecondary,
                                      width: 1.8,
                                    ),
                                  ),
                                  child: selected
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        )
                                      : null,
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
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ProminentButton(
                  label: context.l10n.add2(_selected.length),
                  icon: Icons.check_rounded,
                  expanded: true,
                  onPressed: () {
                    final List<Contact> picked = all
                        .where((Contact c) => _selected.contains(c.id))
                        .toList();
                    Navigator.of(context).pop(picked);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
