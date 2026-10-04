import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/contact.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../chats/presentation/providers.dart';
import '../../../core/utils/l10n.dart';

/// Dial pad with contact matching and a direct call action.
class KeypadScreen extends ConsumerStatefulWidget {
  const KeypadScreen({super.key});

  @override
  ConsumerState<KeypadScreen> createState() => _KeypadScreenState();
}

class _KeypadScreenState extends ConsumerState<KeypadScreen> {
  String _number = '';

  static const List<({String digit, String letters})> _keys =
      <({String digit, String letters})>[
    (digit: '1', letters: ''),
    (digit: '2', letters: 'ABC'),
    (digit: '3', letters: 'DEF'),
    (digit: '4', letters: 'GHI'),
    (digit: '5', letters: 'JKL'),
    (digit: '6', letters: 'MNO'),
    (digit: '7', letters: 'PQRS'),
    (digit: '8', letters: 'TUV'),
    (digit: '9', letters: 'WXYZ'),
    (digit: '*', letters: ''),
    (digit: '0', letters: '+'),
    (digit: '#', letters: ''),
  ];

  @override
  Widget build(BuildContext context) {
    final List<Contact> matches = _matches();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(context.l10n.keypad),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.pasteANumber,
            onPressed: _paste,
            icon: const Icon(Icons.content_paste_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Column(
              children: <Widget>[
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Text(
                    _number.isEmpty ? context.l10n.enterANumber : _number,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.headlineSmall?.copyWith(
                      fontSize: _number.length > 14 ? 22 : 30,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.4,
                      color: _number.isEmpty
                          ? context.c.textSecondary
                          : context.c.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_number.isNotEmpty)
                  Text(
                    TextUtils.isValidPhone(_number)
                        ? context.l10n.looksLikeAPhoneNumber
                        : context.l10n.keepTyping,
                    style: context.t.bodySmall?.copyWith(
                      color: context.c.textSecondary,
                    ),
                  ),
                const Spacer(),
                if (matches.isNotEmpty && _number.length >= 2)
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: matches.length.clamp(0, 3),
                      itemBuilder: (BuildContext context, int i) {
                        final Contact c = matches[i];
                        return SettingsTile(
                          title: c.fullName,
                          subtitle: c.phone,
                          leadingIcon: Icons.person_outline_rounded,
                          dense: true,
                          onTap: () {
                            setState(() => _number = c.phone);
                          },
                        );
                      },
                    ),
                  ),
                const Spacer(),
                _buildPad(),
                const SizedBox(height: AppSpacing.lg),
              ],
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
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: _number.isEmpty ? null : () => _call(false),
                      icon: const Icon(Icons.call_rounded),
                      label: Text(context.l10n.call),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: context.c.accent,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: _number.isEmpty ? null : () => _call(true),
                      icon: const Icon(Icons.videocam_rounded),
                      label: Text(context.l10n.video),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        children: <Widget>[
          for (int row = 0; row < 4; row++)
            Row(
              children: <Widget>[
                for (int col = 0; col < 3; col++)
                  Expanded(
                    child: _KeypadKey(
                      digit: _keys[row * 3 + col].digit,
                      letters: _keys[row * 3 + col].letters,
                      onTap: () => setState(() {
                        _number = _number + _keys[row * 3 + col].digit;
                      }),
                      onLongPress:
                          _keys[row * 3 + col].digit == '0' && _number.isEmpty
                              ? () => setState(() => _number = '+')
                              : null,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Opacity(
                opacity: _number.isEmpty ? 0 : 1,
                child: IconButton(
                  tooltip: context.l10n.delete,
                  onPressed: _number.isEmpty
                      ? null
                      : () => setState(() {
                            _number = _number.substring(0, _number.length - 1);
                          }),
                  iconSize: 26,
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ),
              const SizedBox(width: AppSpacing.xxl),
              IconButton(
                tooltip: context.l10n.clear,
                onPressed: _number.isEmpty
                    ? null
                    : () => setState(() => _number = ''),
                icon: const Icon(Icons.clear_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Contact> _matches() {
    final String q = _number.replaceAll(RegExp(r'[^0-9+]'), '');
    if (q.length < 2) return const <Contact>[];
    final List<Contact> contacts = ref.watch(contactsProvider).orEmpty;
    return contacts
        .where((Contact c) =>
            c.phone.replaceAll(RegExp(r'[^0-9+]'), '').contains(q))
        .toList();
  }

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text;
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      iToast(context, context.l10n.clipboardIsEmpty, isError: true);
      return;
    }
    setState(() => _number = text.trim());
  }

  void _call(bool video) {
    final List<Contact> matches = _matches();
    final Contact? known = matches.isNotEmpty ? matches.first : null;

    context.push(
      Uri(
        path: AppRoutes.call,
        queryParameters: <String, String>{
          'id': known?.id ?? _number,
          'name': known?.fullName ?? _number,
          'video': video ? '1' : '0',
          'outgoing': '1',
        },
      ).toString(),
    );
  }
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({
    required this.digit,
    required this.letters,
    required this.onTap,
    this.onLongPress,
  });

  final String digit;
  final String letters;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      onLongPress: onLongPress,
      radius: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: <Widget>[
            Text(
              digit,
              style: context.t.headlineSmall?.copyWith(
                fontSize: 28,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (letters.isNotEmpty)
              Text(
                letters,
                style: context.t.labelSmall?.copyWith(
                  color: context.c.textSecondary,
                  letterSpacing: 1.6,
                  fontSize: 10,
                ),
              )
            else
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
