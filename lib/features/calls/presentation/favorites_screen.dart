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

/// Quick-dial list of favourite contacts.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  bool _editing = false;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Contact> contacts = ref.watch(contactsProvider).orEmpty;
    final String q = _search.text.trim().toLowerCase();

    final List<Contact> candidates = contacts
        .where((Contact c) =>
            q.isEmpty || c.fullName.toLowerCase().contains(q))
        .toList();

    final List<Contact> favorites =
        candidates.where((Contact c) => c.isFavorite).toList();
    final List<Contact> others =
        candidates.where((Contact c) => !c.isFavorite).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.favourites),
        actions: <Widget>[
          TextButton(
            onPressed: () => setState(() => _editing = !_editing),
            child: Text(_editing ? context.l10n.done : context.l10n.edit),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: ISearchBar(
              controller: _search,
              hint: context.l10n.searchContacts,
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: contacts.isEmpty
                ? EmptyState(
                    icon: Icons.star_border_rounded,
                    title: context.l10n.noContactsYet,
                    message:
                        context.l10n.addContactsThenStarThe2,
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
                    children: <Widget>[
                      if (favorites.isNotEmpty) ...<Widget>[
                        SectionHeader(title: context.l10n.favourites),
                        for (final Contact c in favorites)
                          _FavoriteRow(
                            contact: c,
                            editing: _editing,
                            onToggle: () => _toggleFavorite(c),
                            onCall: () => _call(c, video: false),
                            onVideo: () => _call(c, video: true),
                          ),
                      ],
                      if (favorites.isEmpty && !_editing)
                        Padding(
                          padding: EdgeInsets.only(top: AppSpacing.xl),
                          child: EmptyState(
                            icon: Icons.star_outline_rounded,
                            title: context.l10n.noFavouritesYet,
                            message:
                                context.l10n.tapEditAndStarThe2,
                            compact: true,
                          ),
                        ),
                      if (_editing && others.isNotEmpty) ...<Widget>[
                        SectionHeader(title: context.l10n.otherContacts),
                        for (final Contact c in others)
                          _FavoriteRow(
                            contact: c,
                            editing: true,
                            onToggle: () => _toggleFavorite(c),
                            onCall: () => _call(c, video: false),
                            onVideo: () => _call(c, video: true),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite(Contact contact) async {
    await ref.read(contactsProvider.notifier).toggleFavorite(contact.id);
    if (!mounted) return;
    iToast(
      context,
      contact.isFavorite
          ? '${contact.firstName} removed from favourites'
          : '${contact.firstName} added to favourites',
    );
  }

  void _call(Contact contact, {required bool video}) {
    context.push(
      Uri(
        path: AppRoutes.call,
        queryParameters: <String, String>{
          'id': contact.id,
          'name': contact.fullName,
          if (video) 'video': '1',
          'outgoing': '1',
        },
      ).toString(),
    );
  }
}

class _FavoriteRow extends StatelessWidget {
  const _FavoriteRow({
    required this.contact,
    required this.editing,
    required this.onToggle,
    required this.onCall,
    required this.onVideo,
  });

  final Contact contact;
  final bool editing;
  final VoidCallback onToggle;
  final VoidCallback onCall;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      title: contact.fullName,
      subtitle: contact.aboutText,
      leading: IAvatar(
        name: contact.fullName,
        imagePath: contact.avatarPath,
        colorSeed: contact.avatarColor,
        size: AppSizes.avatarMd,
        isOnline: contact.isOnline,
        showPresence: true,
      ),
      trailing: editing
          ? IconButton(
              tooltip: contact.isFavorite ? context.l10n.unstar : context.l10n.star,
              onPressed: onToggle,
              icon: Icon(
                contact.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: contact.isFavorite ? contact.isFavorite ? context.c.onWarning : null : null,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: context.l10n.voiceCall,
                  onPressed: onCall,
                  icon: Icon(Icons.call_outlined, color: context.c.accent),
                ),
                IconButton(
                  tooltip: context.l10n.videoCall,
                  onPressed: onVideo,
                  icon: Icon(Icons.videocam_outlined, color: context.c.accent),
                ),
              ],
            ),
      onTap: editing ? onToggle : () => context.push('${AppRoutes.contactInfo}/${contact.id}'),
    );
  }
}
