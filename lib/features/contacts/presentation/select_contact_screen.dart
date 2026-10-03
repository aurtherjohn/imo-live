import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/i_avatar.dart';
import '../../chats/presentation/providers.dart';
import '../../../core/services/contact_service.dart';
import 'dialogs/confirm_dialog.dart';
import '../../../core/utils/l10n.dart';

/// Picks a set of contacts and returns their ids.
///
/// Used by "new group", "new community", broadcast lists and forward-to-many.
class SelectContactScreen extends ConsumerStatefulWidget {
  const SelectContactScreen({super.key});

  @override
  ConsumerState<SelectContactScreen> createState() =>
      _SelectContactScreenState();
}

class _SelectContactScreenState extends ConsumerState<SelectContactScreen> {
  final Set<String> _selected = <String>{};
  String _query = '';
  bool _showFavoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final List<Contact> all = ref.watch(contactsProvider).orEmpty;
    final String q = _query.trim().toLowerCase();
    final List<Contact> results = (all
            .where((Contact c) => !c.isBlocked)
            .where((Contact c) => !c.isSelf)
            .where((Contact c) => !_showFavoritesOnly || c.isFavorite)
            .where(
              (Contact c) =>
                  q.isEmpty ||
                  c.fullName.toLowerCase().contains(q) ||
                  c.phone.contains(q) ||
                  c.username.toLowerCase().contains(q),
            )
            .toList()
          ..sort((Contact a, Contact b) => a.sortedKey.compareTo(b.sortedKey)));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: context.l10n.close,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          _selected.isEmpty ? 'Select contacts' : '${_selected.length} selected',
        ),
        actions: <Widget>[
          IconButton(
            onPressed: () => setState(() => _showFavoritesOnly = !_showFavoritesOnly),
            icon: Icon(
              _showFavoritesOnly
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
            tooltip: context.l10n.favouritesOnly,
            color: _showFavoritesOnly ? context.c.accent : null,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_selected.isNotEmpty)
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                children: _selected
                    .map(
                      (String id) => results
                              .where((Contact c) => c.id == id)
                              .map(
                                (Contact c) => Padding(
                                  padding: const EdgeInsets.only(
                                    right: AppSpacing.md,
                                  ),
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _selected.remove(id)),
                                    child: Column(
                                      children: <Widget>[
                                        Stack(
                                          children: <Widget>[
                                            IAvatar(
                                              name: c.fullName,
                                              imagePath: c.avatarPath,
                                              colorSeed: c.avatarColor,
                                              size: AppSizes.avatarMd,
                                            ),
                                            Positioned(
                                              right: -2,
                                              top: -2,
                                              child: Container(
                                                width: 20,
                                                height: 20,
                                                decoration: BoxDecoration(
                                                  color: context.c.textSecondary,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close_rounded,
                                                  size: 13,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        SizedBox(
                                          width: 56,
                                          child: Text(
                                            c.firstName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: context.t.labelSmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                              .firstOrNull,
                    )
                    .whereType<Widget>()
                    .toList(),
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
              hint: context.l10n.searchNameOrNumber,
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),

          Padding(
            padding: AppSpacing.pageH,
            child: Column(
              children: <Widget>[
                SettingsTile(
                  title: context.l10n.newGroup,
                  leading: CircleAvatar(
                    radius: 17,
                    backgroundColor: context.c.accent.withValues(alpha: 0.16),
                    child: Icon(
                      Icons.group_add_rounded,
                      size: AppIconSizes.sm,
                      color: context.c.accent,
                    ),
                  ),
                  onTap: () => context.push(AppRoutes.newGroup),
                ),
                SettingsTile(
                  title: context.l10n.newContact,
                  leading: CircleAvatar(
                    radius: 17,
                    backgroundColor: context.c.accent.withValues(alpha: 0.16),
                    child: Icon(
                      Icons.person_add_alt_1_rounded,
                      size: AppIconSizes.sm,
                      color: context.c.accent,
                    ),
                  ),
                  onTap: () => context.push(AppRoutes.newContact),
                ),
                SettingsTile(
                  title: context.l10n.newCommunity,
                  leading: CircleAvatar(
                    radius: 17,
                    backgroundColor: context.c.accent.withValues(alpha: 0.16),
                    child: Icon(
                      Icons.groups_rounded,
                      size: AppIconSizes.sm,
                      color: context.c.accent,
                    ),
                  ),
                  onTap: () => context.push(AppRoutes.newCommunity),
                ),
                SettingsTile(
                  title: context.l10n.syncDeviceContacts,
                  subtitle: context.l10n.importNamesAndNumbersFrom,
                  leading: CircleAvatar(
                    radius: 17,
                    backgroundColor: context.c.accent.withValues(alpha: 0.16),
                    child: Icon(
                      Icons.sync_rounded,
                      size: AppIconSizes.sm,
                      color: context.c.accent,
                    ),
                  ),
                  onTap: _syncDeviceContacts,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: results.isEmpty
                ? EmptyState(
                    icon: Icons.person_search_rounded,
                    title: all.isEmpty ? 'No contacts yet' : 'No matches',
                    message: all.isEmpty
                        ? 'Add a contact or sync your address book to get '
                            'started.'
                        : 'Nothing matched "$_query". Try a different search.',
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
                                colorSeed: contact.avatarColor,
                                isOnline: contact.isOnline,
                                showPresence: true,
                              ),
                              const SizedBox(width: AppSpacing.lg),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Flexible(
                                          child: Text(
                                            contact.fullName,
                                            style: context.t.bodyLarge,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (contact.isFavorite) ...<Widget>[
                                          const SizedBox(width: AppSpacing.xs),
                                          Icon(
                                            Icons.star_rounded,
                                            size: 14,
                                            color: context.c.accent,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      contact.aboutText,
                                      style: context.t.bodySmall?.copyWith(
                                        color: context.c.textSecondary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              AnimatedContainer(
                                duration: AppDurations.fast,
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected
                                      ? context.c.accent
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: selected
                                        ? context.c.accent
                                        : context.c.textSecondary,
                                    width: 1.8,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 15,
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

          if (_selected.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: ProminentButton(
                  label: context.l10n.continueWith(_selected.length),
                  icon: Icons.arrow_forward_rounded,
                  expanded: true,
                  onPressed: () => Navigator.of(context).pop(_selected.toList()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _syncDeviceContacts() async {
    final DeviceContactService service = ref.read(deviceContactServiceProvider);
    final bool available = await service.isAvailable();
    if (!mounted) return;
    if (!available) {
      showInfoDialog(
        context,
        title: context.l10n.addressBookUnavailable,
        message:
            context.l10n.imoLIVECouldNotRead2,
      );
      return;
    }

    final List<Contact> found = await service.read();
    if (!mounted) return;
    if (found.isEmpty) {
      iToast(context, context.l10n.noNewContactsFoundIn);
      return;
    }

    await ref.read(contactsProvider.notifier).reconcile(found);
    if (mounted) {
      iToast(context, context.l10n.contactsImported(found.length));
    }
  }
}
