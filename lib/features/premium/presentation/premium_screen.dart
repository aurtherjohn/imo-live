import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/gift.dart';
import '../../../core/services/premium_service.dart';
import '../../../core/utils/l10n.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../earn/presentation/providers.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';

/// One line of the benefits list.
@immutable
class _Benefit {
  const _Benefit(this.icon, this.title, this.detail);

  final IconData icon;
  final String title;
  final String detail;
}

/// What premium actually buys.
///
/// Kept as data rather than eight hand-written rows so the list cannot drift
/// out of step with the copy above it, and so the "no ads" claim here is the
/// same claim [adsAllowedProvider] enforces.
const List<_Benefit> _benefits = <_Benefit>[
  _Benefit(
    Icons.block_rounded,
    'No ads',
    'Banners, interstitials and sponsored messages all disappear.',
  ),
  _Benefit(
    Icons.bolt_rounded,
    'Faster downloads',
    'Media downloads skip the free-tier queue and start immediately.',
  ),
  _Benefit(
    Icons.cloud_upload_outlined,
    'Unlimited uploads & sharing',
    'No cap on the photos, videos and documents you send.',
  ),
  _Benefit(
    Icons.verified_rounded,
    'Premium badge',
    'A mark on your profile and beside your name in chats.',
  ),
  _Benefit(
    Icons.support_agent_rounded,
    'Priority support',
    'Your support tickets jump to the front of the queue.',
  ),
  _Benefit(
    Icons.emoji_emotions_outlined,
    'Exclusive emoji packs',
    'Sticker and emoji sets only premium members can send.',
  ),
  _Benefit(
    Icons.hd_rounded,
    'HD voice & video calls',
    'A higher bitrate on calls with other premium members.',
  ),
  _Benefit(
    Icons.palette_outlined,
    'Premium chat themes',
    'Exclusive wallpapers and bubble styles for every chat.',
  ),
];

/// The premium upgrade screen.
///
/// Reached from Settings → Go Premium. Two rails: money (a manual transfer that
/// a human confirms) and points (immediate, because the balance is already
/// server-side). See [PremiumService] for why the money rail is manual.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final PointsAccount? account =
        ref.watch(pointsAccountProvider).valueOrNull;
    final bool isPremium = account?.premiumActive ?? false;
    final int balance = account?.points ?? 0;
    final int pointsPrice = PremiumService.calculatePointsForPremium();
    final List<PremiumRequest> requests =
        ref.watch(premiumRequestsProvider).valueOrNull ??
            const <PremiumRequest>[];

    return Scaffold(
      appBar: AppTopBar(title: context.l10n.goPremium, showBack: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: <Widget>[
          _HeroCard(isPremium: isPremium, account: account),

          if (isPremium)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: InfoBanner(
                icon: Icons.verified_rounded,
                color: c.onSuccess,
                message: account?.premiumUntil == null
                    ? context.l10n.premiumIsActiveOnThis
                    : 'Premium is active — '
                        '${account!.premiumDaysLeft} days left. '
                        'Buying more extends it.',
              ),
            ),

          SettingsGroup(
            title: context.l10n.whatYouGet,
            children: <Widget>[
              for (final _Benefit b in _benefits)
                _BenefitRow(benefit: b),
            ],
          ),

          _PriceCard(
            priceUsd: PremiumService.priceUsd,
            priceBdt: PremiumService.priceBdt,
            pointsPrice: pointsPrice,
            balance: balance,
          ),

          // ----------------------------------------------------------- actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              children: <Widget>[
                ProminentButton(
                  label: 'Pay with Money — '
                      '\$${_money(PremiumService.priceUsd)}',
                  icon: Icons.account_balance_wallet_outlined,
                  expanded: true,
                  onPressed: _busy ? null : _openPaymentSheet,
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _buyWithPoints(pointsPrice),
                    icon: const Icon(Icons.stars_rounded),
                    label: Text(
                      'Pay with Points — ${_thousands(pointsPrice)} pts',
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: InfoBanner(
              message: 'Money payments are checked by a human before premium is '
                  'switched on — usually within a few hours. Points activate '
                  'instantly. One month costs \$${_money(PremiumService.priceUsd)} '
                  'or ${_thousands(pointsPrice)} points.',
            ),
          ),

          if (requests.isNotEmpty)
            SettingsGroup(
              title: context.l10n.yourRequests,
              children: <Widget>[
                for (final PremiumRequest r in requests) _RequestRow(r),
              ],
            ),
        ],
      ),
    );
  }

  /// Opens the manual-payment sheet and reports the outcome.
  Future<void> _openPaymentSheet() async {
    final String uid = ref.read(currentUidProvider);
    final PremiumRequestResult? result =
        await showModalBottomSheet<PremiumRequestResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _PaymentSheet(uid: uid),
    );
    if (!mounted || result == null) return;
    iToast(context, result.message, isError: !result.success);
  }

  /// Buys premium with points, after confirming the spend.
  Future<void> _buyWithPoints(int cost) async {
    final String uid = ref.read(currentUidProvider);
    if (uid.isEmpty) {
      iToast(context, context.l10n.signInFirst2, isError: true);
      return;
    }
    final int balance = ref.read(pointsBalanceProvider);
    final bool confirmed = await _confirmPoints(cost, balance);
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final GiftResult result =
        await ref.read(premiumServiceProvider).purchaseWithPoints(uid);
    if (!mounted) return;
    setState(() => _busy = false);
    iToast(context, result.message, isError: !result.success);
  }

  Future<bool> _confirmPoints(int cost, int balance) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(context.l10n.buyPremiumWithPoints),
        content: Text(
          '${_thousands(cost)} points will be taken from your balance of '
          '${_thousands(balance)}. You will get 30 days of premium.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.confirm),
          ),
        ],
      ),
    );
    return yes ?? false;
  }
}

/// `9.90` rather than `9.9`, so a price never reads as a typo.
String _money(double value) => value.toStringAsFixed(2);

/// `18000` → `18,000`.
String _thousands(int value) {
  final String digits = value.abs().toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return value < 0 ? '-$out' : out.toString();
}

/// The gradient header with the price.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.isPremium, this.account});

  final bool isPremium;
  final PointsAccount? account;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          borderRadius: AppRadius.rXl,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              c.accent,
              Color.lerp(c.accent, Colors.black, 0.28) ?? c.accent,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.textOnAccent.withValues(alpha: 0.18),
                    borderRadius: AppRadius.rMd,
                  ),
                  child: Icon(
                    isPremium
                        ? Icons.verified_rounded
                        : Icons.workspace_premium_rounded,
                    color: c.textOnAccent,
                    size: AppIconSizes.lg,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.l10n.imoLIVEPremium,
                        style: context.t.titleLarge?.copyWith(
                          color: c.textOnAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPremium ? context.l10n.activeOnThisAccount : context.l10n.upgradeOnceEveryFeatureUnlocks,
                        style: context.t.bodySmall?.copyWith(
                          color: c.textOnAccent.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  '\$${_money(PremiumService.priceUsd)}',
                  style: context.t.headlineSmall?.copyWith(
                    color: c.textOnAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '/ month · ৳${PremiumService.priceBdt}',
                  style: context.t.bodyMedium?.copyWith(
                    color: c.textOnAccent.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One benefit row: icon, title, detail.
class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.benefit});

  final _Benefit benefit;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(benefit.icon, size: AppIconSizes.md, color: c.accent),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  benefit.title,
                  style: context.t.bodyLarge?.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  benefit.detail,
                  style: context.t.bodySmall?.copyWith(
                    color: c.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The two prices side by side, and the balance the points rail would spend.
class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.priceUsd,
    required this.priceBdt,
    required this.pointsPrice,
    required this.balance,
  });

  final double priceUsd;
  final int priceBdt;
  final int pointsPrice;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final bool affordable = balance >= pointsPrice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: ICard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.s1MonthOfPremium,
              style: context.t.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _PriceLine(
              label: context.l10n.money,
              value: '\$${_money(priceUsd)}  ·  ৳$priceBdt',
            ),
            const SizedBox(height: AppSpacing.sm),
            _PriceLine(
              label: context.l10n.points3,
              value: '${_thousands(pointsPrice)} pts',
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Icon(
                  affordable ? Icons.stars_rounded : Icons.info_outline_rounded,
                  size: AppIconSizes.sm,
                  color: affordable ? c.onSuccess : c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    affordable
                        ? 'Your balance: ${_thousands(balance)} pts — enough for '
                            'premium.'
                        : 'Your balance: ${_thousands(balance)} pts. Watch ads to '
                            'earn the rest.',
                    style: context.t.bodySmall?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: context.t.bodyLarge?.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// One past purchase request.
class _RequestRow extends StatelessWidget {
  const _RequestRow(this.request);

  final PremiumRequest request;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final bool approved = request.status == 'approved';
    final bool rejected = request.status == 'rejected';
    final Color tint = approved
        ? c.onSuccess
        : rejected
            ? c.onDanger
            : c.onWarning;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            approved
                ? Icons.check_circle_rounded
                : rejected
                    ? Icons.cancel_rounded
                    : Icons.schedule_rounded,
            size: AppIconSizes.md,
            color: tint,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${request.method.label} · \$${_money(request.amountUsd)}',
                  style: context.t.bodyLarge?.copyWith(color: c.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  request.txId.isEmpty
                      ? request.status
                      : '${request.status} · ${request.txId}',
                  style: context.t.bodySmall?.copyWith(
                    color: c.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The manual-payment sheet: pick a rail, see where the money goes, paste the
/// transaction id back.
class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.uid});

  final String uid;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  PremiumPaymentMethod? _method;
  final TextEditingController _tx = TextEditingController();
  bool _submitting = false;
  String _error = '';

  @override
  void dispose() {
    _tx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final PremiumPaymentMethod? method = _method;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: AppRadius.rXl,
            border: Border.all(color: c.divider, width: 0.8),
          ),
          clipBehavior: Clip.antiAlias,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.divider,
                      borderRadius: AppRadius.rPill,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    method == null
                        ? context.l10n.payForPremium
                        : 'Pay with ${method.label}',
                    style: context.t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (method == null)
                  ..._methodList(c)
                else
                  ..._paymentForm(c, method),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _methodList(AppColorScheme c) {
    return <Widget>[
      for (final PremiumPaymentMethod m in PremiumPaymentMethod.values)
        ListTile(
          leading: Icon(_methodIcon(m), color: c.accent),
          title: Text(m.label),
          subtitle: Text(_methodBlurb(m)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => setState(() {
            _method = m;
            _error = '';
          }),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          0,
        ),
        child: Text(
          'Send \$${_money(PremiumService.priceUsd)} '
          '(about ৳${PremiumService.priceBdt}) and keep the confirmation — you '
          'will need the ${PremiumPaymentMethod.bkash.proofLabel.toLowerCase()} '
          'it gives you.',
          style: context.t.bodySmall?.copyWith(
            color: c.textSecondary,
            height: 1.4,
          ),
        ),
      ),
    ];
  }

  List<Widget> _paymentForm(AppColorScheme c, PremiumPaymentMethod method) {
    final PremiumPaymentTarget target = PremiumPaymentTarget.targets[method]!;
    return <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: AppRadius.rMd,
                border: Border.all(color: c.divider, width: 0.8),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SelectableText(
                      target.destination,
                      style: context.t.bodyLarge?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.copyCode,
                    icon: const Icon(Icons.copy_rounded),
                    color: c.accent,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: target.destination),
                      );
                      if (!mounted) return;
                      iToast(context, context.l10n.copied2);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              target.instructions,
              style: context.t.bodySmall?.copyWith(
                color: c.textSecondary,
                height: 1.4,
              ),
            ),
            if (target.hasQr) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppRadius.rLg,
                  ),
                  child: QrImageView(
                    data: target.qrPayload,
                    version: QrVersions.auto,
                    size: 168,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF0B0B0D),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF0B0B0D),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _tx,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: method.proofLabel,
                hintText: method == PremiumPaymentMethod.crypto
                    ? context.l10n.s0x
                    : 'e.g. 9F7A2K1LQD',
                border: const OutlineInputBorder(),
                errorText: _error.isEmpty ? null : _error,
              ),
              onChanged: (_) {
                if (_error.isNotEmpty) setState(() => _error = '');
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            ProminentButton(
              label: _submitting ? context.l10n.submitting : context.l10n.submitPayment,
              icon: Icons.send_rounded,
              expanded: true,
              onPressed: _submitting ? null : () => _submit(method),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                        _method = null;
                        _error = '';
                      }),
              child: Text(context.l10n.chooseADifferentMethod),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _submit(PremiumPaymentMethod method) async {
    setState(() {
      _submitting = true;
      _error = '';
    });
    final PremiumRequestResult result =
        await ref.read(premiumServiceProvider).requestPremiumPurchase(
              uid: widget.uid,
              method: method,
              txId: _tx.text,
            );
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _submitting = false;
        _error = result.message;
      });
      return;
    }
    Navigator.of(context).pop(result);
  }

  static IconData _methodIcon(PremiumPaymentMethod m) => switch (m) {
        PremiumPaymentMethod.bkash => Icons.account_balance_wallet_rounded,
        PremiumPaymentMethod.nagad => Icons.account_balance_wallet_outlined,
        PremiumPaymentMethod.crypto => Icons.currency_bitcoin_rounded,
      };

  static String _methodBlurb(PremiumPaymentMethod m) => switch (m) {
        PremiumPaymentMethod.bkash => 'Send from your bKash wallet',
        PremiumPaymentMethod.nagad => 'Send from your Nagad wallet',
        PremiumPaymentMethod.crypto => 'Send USDT (TRC-20) to a wallet address',
      };
}
