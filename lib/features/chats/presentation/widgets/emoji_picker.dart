import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/widgets/common_widgets.dart';
import 'emoji_data.dart';
import '../../../../core/utils/l10n.dart';

/// A full emoji picker: eight categories, live search and a recents row.
///
/// Rendered inline inside the composer (not as a sheet) so the keyboard
/// hand-off feels native. [recent] is kept by the caller so recents survive
/// across openings within the session.
class EmojiPicker extends StatefulWidget {
  const EmojiPicker({
    super.key,
    required this.onSelected,
    this.recent = const <String>[],
    this.height = 288,
    this.onBackspace,
  });

  final ValueChanged<String> onSelected;
  final List<String> recent;
  final double height;

  /// When provided a backspace key is shown next to the search field.
  final VoidCallback? onBackspace;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _categoryIndex = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final bool searching = _query.trim().isNotEmpty;

    final List<({String char, String keywords})> visible = searching
        ? allEmoji
            .where((({String char, String keywords}) e) =>
                e.keywords.contains(_query.toLowerCase().trim()))
            .toList()
        : emojiCategories[_categoryIndex].emoji;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.divider, width: 0.6)),
      ),
      child: Column(
        children: <Widget>[
          _SearchRow(
            controller: _searchController,
            onChanged: (String value) => setState(() => _query = value),
            onBackspace: widget.onBackspace,
          ),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: context.l10n.noEmojiFound,
                    message: context.l10n.tryAnotherKeyword,
                    compact: true,
                  )
                : CustomScrollView(
                    controller: _scrollController,
                    slivers: <Widget>[
                      if (!searching && _categoryIndex == 0 && widget.recent.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _EmojiSection(
                            title: context.l10n.frequentlyUsed,
                            emoji: widget.recent
                                .map(((String char) => (char: char, keywords: char)))
                                .toList(),
                            onSelected: widget.onSelected,
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: _EmojiSection(
                          title: searching ? context.l10n.results : emojiCategories[_categoryIndex].name,
                          emoji: visible,
                          onSelected: widget.onSelected,
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
                    ],
                  ),
          ),
          if (!searching)
            _CategoryBar(
              selectedIndex: _categoryIndex,
              onSelect: (int index) {
                setState(() => _categoryIndex = index);
                if (_scrollController.hasClients) _scrollController.jumpTo(0);
              },
            ),
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.onChanged,
    this.onBackspace,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onBackspace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ITextField(
              controller: controller,
              hint: context.l10n.searchEmoji,
              onChanged: onChanged,
              prefixIcon: Icon(
                Icons.search_rounded,
                size: AppIconSizes.sm,
                color: context.c.textSecondary,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              style: context.t.bodyMedium,
            ),
          ),
          if (onBackspace != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: onBackspace,
              icon: const Icon(Icons.backspace_outlined, size: AppIconSizes.md),
              tooltip: context.l10n.delete,
              color: context.c.textSecondary,
              splashRadius: 20,
            ),
          ],
        ],
      ),
    );
  }
}

class _EmojiSection extends StatelessWidget {
  const _EmojiSection({
    required this.title,
    required this.emoji,
    required this.onSelected,
  });

  final String title;
  final List<({String char, String keywords})> emoji;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            title.toUpperCase(),
            style: context.t.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 46,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: emoji.length,
          itemBuilder: (BuildContext context, int index) {
            final String char = emoji[index].char;
            return InkWell(
              onTap: () => onSelected(char),
              borderRadius: AppRadius.rSm,
              child: Center(
                child: Text(char, style: const TextStyle(fontSize: 26)),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        border: Border(top: BorderSide(color: c.divider, width: 0.6)),
      ),
      child: Row(
        children: List<Widget>.generate(emojiCategories.length, (int index) {
          final EmojiCategory category = emojiCategories[index];
          final bool isSelected = index == selectedIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onSelect(index),
              child: Semantics(
                label: category.name,
                selected: isSelected,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      category.icon,
                      style: TextStyle(
                        fontSize: 19,
                        color: isSelected ? null : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedContainer(
                      duration: AppDurations.fast,
                      height: 2,
                      width: isSelected ? 18 : 0,
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: AppRadius.rPill,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
