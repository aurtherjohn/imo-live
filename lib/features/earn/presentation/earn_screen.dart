import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/gift.dart';
import '../../../core/services/points_service.dart';
import '../../../core/services/rewarded_ad_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../contacts/presentation/dialogs/confirm_dialog.dart';
import 'providers.dart';
import '../../../core/utils/l10n.dart';
import '../../../app/app.dart';

/// Watch-to-Earn: watch rewarded ads, collect points, spend them on premium.
///
/// ### Why the balance is read from a stream
///
/// Every number on this screen is derived from `users/{uid}`, which the points
/// service writes inside a transaction. Watching it rather than fetching once
/// means the balance after an ad is the server's number, not a local guess that
/// could disagree with it — and two devices signed into the same account stay in
/// step without either polling.
class EarnScreen extends ConsumerStatefulWidget {
  const EarnScreen({super.key});

  @override
  ConsumerState<EarnScreen> createState() => _EarnScreenState();
}

class _EarnScreenState extends ConsumerState<EarnScreen> {
  /// True while an ad is loading or on screen, so the button cannot be tapped
  /// twice into two parallel ad sessions.
  bool _watching = false;

  /// True while a premium redemption is in flight.
  bool _redeeming = false;

  /// The payout from the last ad, so the toast can report the real number the
  /// transaction returned rather than the expected one.
  AdRewardResult? _lastReward;

  @override
  void initState() {
    super.initState();
    // Warm an ad up in the background so the first tap shows one immediately
    // instead of waiting out a load. Failure is ignored — the tap will retry.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(rewardedAdServiceProvider).load());
    });
  }

  /// Runs one rewarded ad end to end.
  Future<void> _watchAd() async {
    final String uid = ref.read(currentUidProvider);
    if (uid.isEmpty) {
      iToast(context, context.l10n.signInToStartEarning, isError: true);
      return;
    }

    // Checked here purely to avoid showing an ad that cannot be paid for; the
    // real limit is enforced inside the transaction, because this read can be
    // stale.
    final PointsAccount? account = ref.read(pointsAccountProvider).valueOrNull;
    if ((account?.adsWatchedToday ?? 0) >= PointsService.dailyAdLimit) {
      iToast(
        context,
        "That's all ${PointsService.dailyAdLimit} ads for today — "
        'come back tomorrow',
        isError: true,
      );
      return;
    }

    setState(() => _watching = true);
    try {
      final RewardedAdService ads = ref.read(rewardedAdServiceProvider);
      final PointsService points = ref.read(pointsServiceProvider);

      if (!await ads.load()) {
        if (!mounted) return;
        iToast(
          context,
          ads.lastError ?? context.l10n.couldNotLoadAnAd,
          isError: true,
        );
        return;
      }

      // `show` only returns true once the credit has landed, so `_lastReward`
      // is always populated by the time it is read below.
      final bool earned = await ads.show(
        onReward: () async {
          _lastReward = await points.claimAdReward(uid);
        },
      );

      if (!mounted) return;
      final AdRewardResult? result = _lastReward;
      if (earned && result != null) {
        iToast(context, result.message, isError: !result.isSuccess);
      } else if (!earned) {
        iToast(context, context.l10n.watchTheWholeAdTo, isError: true);
      }
    } finally {
      if (mounted) setState(() => _watching = false);
    }
  }

  /// Buys a premium plan with points.
  Future<void> _redeem(PremiumPlan plan) async {
    final String uid = ref.read(currentUidProvider);
    if (uid.isEmpty) {
      iToast(context, context.l10n.signInFirst, isError: true);
      return;
    }

    final bool ok = await showConfirmDialog(
      context,
      title: context.l10n.getOfPremium(plan.name),
      message: context.l10n.thisSpendsPointsFromYour(TextUtils.grouped(plan.points)),
      confirmLabel: context.l10n.redeem,
    );
    if (!ok || !mounted) return;

    setState(() => _redeeming = true);
    try {
      final GiftResult result = await ref
          .read(pointsServiceProvider)
          .redeemPremium(uid: uid, plan: plan);
      if (!mounted) return;
      iToast(context, result.message, isError: !result.success);
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PointsAccount> account = ref.watch(pointsAccountProvider);

    return Scaffold(
      appBar: AppTopBar(
        title: context.l10n.watchToEarn,
        showBack: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Re-read the balance; the streams are live, so this is only a
          // user-visible "yes, it refreshed" affordance.
          ref.invalidate(pointsAccountProvider);
          await ref.read(pointsAccountProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: <Widget>[
            _BalanceCard(
              account: account.valueOrNull ?? PointsAccount.empty,
              loading: account.isLoading,
            ),
            const SizedBox(height: AppSpacing.lg),
            _WatchCard(
              account: account.valueOrNull ?? PointsAccount.empty,
              busy: _watching,
              onWatch: _watching ? null : _watchAd,
            ),
            const SizedBox(height: AppSpacing.lg),
            _PremiumSection(
              account: account.valueOrNull ?? PointsAccount.empty,
              busy: _redeeming,
              // Wrapped rather than passed directly: `_redeem` is async, and
              // `_PlanRow` disables itself from `busy` instead of from a null
              // callback, so the button stays visible and explains itself.
              onRedeem: (PremiumPlan plan) => unawaited(_redeem(plan)),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _HistorySection(),
          ],
        ),
      ),
    );
  }
}

/// The points balance, with the daily allowance underneath it.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.account, required this.loading});

  final PointsAccount account;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: AppRadius.rXl,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            c.accent,
            AppColors.accentDark,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.stars_rounded,
                color: Colors.white,
                size: AppIconSizes.md,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                context.l10n.yourPoints,
                style: context.t.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (account.premiumActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: AppRadius.rPill,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.workspace_premium_rounded,
                          size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        context.l10n.premium,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (loading)
            const SizedBox(
              height: 46,
              child: Align(
                alignment: Alignment.centerLeft,
                child: ILoader(size: 24, color: Colors.white),
              ),
            )
          else
            ValueSwap(
              // Keyed on the value so the switcher sees a new child and plays
              // the scale-in. Without the key the text would just mutate.
              child: Text(
                TextUtils.grouped(account.points),
                key: ValueKey<int>(account.points),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  letterSpacing: -1,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            account.premiumActive
                ? 'Premium active — ${account.premiumDaysLeft} days left'
                : 'Watch ads to earn more',
            style: context.t.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Watch & Earn control, plus today's progress against the daily cap.
class _WatchCard extends StatelessWidget {
  const _WatchCard({
    required this.account,
    required this.busy,
    required this.onWatch,
  });

  final PointsAccount account;
  final bool busy;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final int watched = account.adsWatchedToday;
    final double progress = (watched / PointsService.dailyAdLimit).clamp(0.0, 1.0);
    final bool capped = watched >= PointsService.dailyAdLimit;

    return ICard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.14),
                  borderRadius: AppRadius.rMd,
                ),
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: c.accent,
                  size: AppIconSizes.lg,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(context.l10n.watchEarn, style: context.t.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.earnPointsPerAd(PointsService.pointsPerAd),
                      style: context.t.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Text(
                context.l10n.today,
                style: context.t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                context.l10n.ofAds(watched, PointsService.dailyAdLimit),
                style: context.t.bodySmall,
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: AppRadius.rPill,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: c.divider,
              valueColor: AlwaysStoppedAnimation<Color>(
                capped ? capped ? context.c.onWarning : c.accent : c.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            capped
                ? 'Daily limit reached. Resets tomorrow — up to '
                    '${TextUtils.grouped(PointsService.dailyAdPointsCap)} '
                    'points a day.'
                : 'Up to ${TextUtils.grouped(PointsService.dailyAdPointsCap)} '
                    'points a day from ads.',
            style: context.t.bodySmall?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          ProminentButton(
            label: busy ? 'Loading ad…' : 'Watch & Earn',
            icon: busy ? null : Icons.ondemand_video_rounded,
            expanded: true,
            onPressed: capped ? null : onWatch,
          ),
        ],
      ),
    );
  }
}

/// Premium status and the plans that can be bought with points.
class _PremiumSection extends StatelessWidget {
  const _PremiumSection({
    required this.account,
    required this.busy,
    required this.onRedeem,
  });

  final PointsAccount account;
  final bool busy;
  final void Function(PremiumPlan plan) onRedeem;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: context.l10n.premium2),
        ICard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (account.premiumActive)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.workspace_premium_rounded,
                        color: context.c.onWarning,
                        size: AppIconSizes.sm,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          context.l10n.premiumIsActiveDaysLeft(account.premiumDaysLeft),
                          style: context.t.bodySmall?.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _PremiumBenefit(
                icon: Icons.block_rounded,
                title: context.l10n.noAds,
                subtitle: context.l10n.nothingToWatchBeforeYour,
              ),
              _PremiumBenefit(
                icon: Icons.verified_rounded,
                title: context.l10n.exclusiveBadge,
                subtitle: context.l10n.aPremiumMarkOnYour,
              ),
              _PremiumBenefit(
                icon: Icons.lock_open_rounded,
                title: context.l10n.premiumChannels,
                subtitle: context.l10n.openChannelsReservedForMembers,
              ),
              const SizedBox(height: AppSpacing.sm),
              const IListDivider(),
              const SizedBox(height: AppSpacing.sm),
              for (final PremiumPlan plan in PremiumPlan.plans)
                _PlanRow(
                  plan: plan,
                  affordable: account.points >= plan.points,
                  busy: busy,
                  onRedeem: onRedeem,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One premium perk row.
class _PremiumBenefit extends StatelessWidget {
  const _PremiumBenefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: AppIconSizes.sm, color: context.c.accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: context.t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(subtitle, style: context.t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One purchasable premium plan.
class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.plan,
    required this.affordable,
    required this.busy,
    required this.onRedeem,
  });

  final PremiumPlan plan;

  /// Whether the current balance covers it. Drives whether the button is
  /// enabled — a visibly disabled control rather than a tap that fails.
  final bool affordable;

  final bool busy;
  final void Function(PremiumPlan plan) onRedeem;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  plan.name,
                  style: context.t.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  context.l10n.points2(TextUtils.grouped(plan.points)),
                  style: context.t.bodySmall?.copyWith(
                    color: affordable ? c.textSecondary : context.c.onWarning,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          FilledButton.tonal(
            onPressed: (!affordable || busy) ? null : () => onRedeem(plan),
            child: Text(context.l10n.redeem),
          ),
        ],
      ),
    );
  }
}

/// The points ledger.
class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PointsTransaction>> history =
        ref.watch(pointsHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: context.l10n.earningHistory),
        ICard(
          padding: EdgeInsets.zero,
          child: history.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: ILoader()),
            ),
            error: (Object error, StackTrace stack) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                context.l10n.couldNotLoadYourHistory,
                style: context.t.bodyMedium,
              ),
            ),
            data: (List<PointsTransaction> items) {
              if (items.isEmpty) {
                return Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.receipt_long_outlined,
                        size: AppIconSizes.xl,
                        color: context.c.textSecondary,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        context.l10n.noActivityYet,
                        style: context.t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.watchYourFirstAdTo,
                        style: context.t.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: <Widget>[
                  for (int i = 0; i < items.length; i++) ...<Widget>[
                    if (i > 0) const IListDivider(),
                    _HistoryRow(entry: items[i]),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One ledger line.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final PointsTransaction entry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final Color tint = entry.isEarn ? entry.isEarn ? context.c.onSuccess : c.textSecondary : c.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              switch (entry.source) {
                PointsSource.rewardedAd => Icons.ondemand_video_rounded,
                PointsSource.premium => Icons.workspace_premium_rounded,
                PointsSource.giftSent => Icons.card_giftcard_rounded,
                PointsSource.giftReceived => Icons.redeem_rounded,
                PointsSource.bonus => Icons.auto_awesome_rounded,
              },
              size: AppIconSizes.sm,
              color: tint,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.description.isEmpty
                      ? entry.source.label
                      : entry.description,
                  style: context.t.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  entry.createdAt == null
                      ? entry.source.label
                      : DateFormatter.relative(entry.createdAt!),
                  style: context.t.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          Text(
            '${entry.isEarn ? '+' : '−'}${TextUtils.grouped(entry.amount)}',
            style: context.t.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: entry.isEarn ? entry.isEarn ? context.c.onSuccess : c.textPrimary : c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
