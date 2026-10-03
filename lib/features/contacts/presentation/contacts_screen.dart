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
import '../../../core/utils/l10n.dart';
import '../../../app/app.dart';

/// The Contacts tab.
///
/// Lists everything reachable in one place: contacts saved inside the app plus
/// the people already stored in the device address book. Tapping a row opens
/// the contact's profile; the chat bubble action starts a conversation.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Contact>> device = ref.watch(deviceContactsProvider);
    final List<Contact> all = ref.watch(allContactsProvider);

    final String q = _query.trim().toLowerCase();
    final List<Contact> visible = q.isEmpty
        ? all
        : all
            .where((Contact c) =>
                c.fullName.toLowerCase().contains(q) ||
                c.username.toLowerCase().contains(q) ||
                c.phone.contains(q))
            .toList();

    final Map<String, List<Contact>> grouped = <String, List<Contact>>{};
    for (final Contact c in visible) {
      final String name = c.fullName.trim();
      final String letter =
          name.isEmpty ? '#' : name.substring(0, 1).toUpperCase();
      final String key = RegExp(r'^[A-Z]$').hasMatch(letter) ? letter : '#';
      grouped.putIfAbsent(key, () => <Contact>[]).add(c);
    }
    final List<String> keys = grouped.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.tabContacts),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.syncDeviceContacts,
            onPressed: _sync,
            icon: const Icon(Icons.sync_rounded),
          ),
          IconButton(
            tooltip: context.l10n.newContact,
            onPressed: () => context.push(AppRoutes.newContact),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: context.c.accent,
        foregroundColor: Colors.white,
        onPressed: () => context.push(AppRoutes.newContact),
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: ISearchBar(
              hint: context.l10n.searchContacts,
              controller: _search,
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
          if (device.isLoading && all.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.md),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    icon: Icons.contacts_outlined,
                    title: all.isEmpty ? 'No contacts yet' : 'No matches',
                    message: all.isEmpty
                        ? 'People saved on this device will appear here. '
                            'Add a contact or allow contacts access to get '
                            'started.'
                        : 'Nothing matched "$_query".',
                    actionLabel: all.isEmpty ? 'New contact' : null,
                    onAction: all.isEmpty
                        ? () => context.push(AppRoutes.newContact)
                        : null,
                  )
                : RefreshIndicator(
                    color: context.c.accent,
                    backgroundColor: context.c.card,
                    onRefresh: () async {
                      ref.invalidate(deviceContactsProvider);
                      await ref.read(contactsProvider.notifier).refresh();
                      // Let the invalidated provider actually re-read the
                      // address book before the spinner is dismissed.
                      await ref.read(deviceContactsProvider.future);
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: keys.length,
                      itemBuilder: (BuildContext context, int i) {
                        final String key = keys[i];
                        final List<Contact> bucket = grouped[key]!;
                        return ListStagger(
                          index: i,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              SectionHeader(title: key),
                              for (final Contact contact in bucket)
                                _ContactRow(
                                  contact: contact,
                                  onTap: () => context.push(
                                    '${AppRoutes.contactInfo}/${contact.id}',
                                  ),
                                  onMessage: () => _message(contact),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Opens the existing conversation with [contact], or creates one.
  Future<void> _message(Contact contact) async {
    final List<dynamic> chats = ref.read(chatsProvider).orEmpty;
    final dynamic existing = chats
        .where((dynamic c) => c.id == contact.id)
        .firstOrNull;
    if (existing != null) {
      context.push('${AppRoutes.chat}/${existing.id}');
      return;
    }
    // Go through the profile: "Message" there creates the conversation, and
    // the user gets to review the number before a chat row is written.
    context.push('${AppRoutes.contactInfo}/${contact.id}');
  }

  Future<void> _sync() async {
    ref.invalidate(deviceContactsProvider);
    final List<Contact> found =
        await ref.read(deviceContactsProvider.future);
    if (!mounted) return;
    if (found.isEmpty) {
      iToast(
        context,
        context.l10n.noContactsFoundCheckContacts,
        isError: true,
      );
      return;
    }
    await ref.read(contactsProvider.notifier).reconcile(found);
    if (mounted) {
      iToast(
        context,
        context.l10n.contactsImported(found.length),
      );
    }
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.onTap,
    required this.onMessage,
  });

  final Contact contact;
  final VoidCallback onTap;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: <Widget>[
            // The avatar is its own tap target — matches the search behaviour,
            // where the picture opens the profile and the row opens the chat.
            IAvatar(
              name: contact.fullName,
              imagePath: contact.avatarPath,
              colorSeed: contact.avatarColor,
              isOnline: contact.isOnline,
              showPresence: contact.isOnline,
              onTap: onTap,
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
                          contact.fullName.isEmpty
                              ? AppConstants.unsetPhoneLabel
                              : contact.fullName,
                          style: context.t.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.message,
              onPressed: onMessage,
              icon: Icon(
                Icons.chat_bubble_outline_rounded,
                size: AppIconSizes.md,
                color: context.c.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
