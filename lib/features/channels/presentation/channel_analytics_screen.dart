import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_color_scheme.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/channel_models.dart';
import '../../../core/models/group.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import 'providers.dart';
import '../../../core/utils/l10n.dart';

/// The channel analytics dashboard.
///
/// Four views over the last 28 days, in the shape YouTube and Facebook use:
/// a follower-growth line, a daily-reach bar chart, a reaction breakdown pie,
/// and a ranked list of the best posts. Every series is built from the
/// `channels/{id}/analytics/{yyyy-MM-dd}` documents, which are incremented
/// server-side on each event and carry server timestamps.
class ChannelAnalyticsScreen extends ConsumerWidget {
  const ChannelAnalyticsScreen({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ChannelDayStats>> analytics =
        ref.watch(channelAnalyticsProvider(channelId));
    final AsyncValue<Channel?> channel = ref.watch(channelDocProvider(channelId));
    final AsyncValue<List<ChannelPost>> posts =
        ref.watch(channelPostsProvider(channelId));

    final List<ChannelDayStats> series =
        analytics.valueOrNull ?? const <ChannelDayStats>[];
    final Channel? doc = channel.valueOrNull;
    final List<ChannelPost> postList =
        posts.valueOrNull ?? const <ChannelPost>[];

    return Scaffold(
      appBar: AppTopBar(
        title: context.l10n.analytics,
        showBack: true,
        subtitle: doc?.name,
      ),
      body: analytics.isLoading && series.isEmpty
          ? const Center(child: ILoader(size: 26))
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
              children: <Widget>[
                _KpiRow(series: series, channel: doc),
                _Section(
                  title: context.l10n.followerGrowth,
                  subtitle: context.l10n.netNewFollowersPerDay,
                  child: _FollowerLine(series: series),
                ),
                _Section(
                  title: context.l10n.postReach,
                  subtitle: context.l10n.postImpressionsPerDayLast,
                  child: _ReachBars(series: series),
                ),
                _Section(
                  title: context.l10n.reactions,
                  subtitle: context.l10n.breakdownAcrossAllPosts,
                  child: _ReactionPie(posts: postList),
                ),
                _Section(
                  title: context.l10n.topPosts,
                  subtitle: context.l10n.rankedByViews,
                  child: _TopPosts(posts: postList),
                ),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return ICard(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: context.t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: context.t.bodySmall?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(height: 180, child: child),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.series, required this.channel});

  final List<ChannelDayStats> series;
  final Channel? channel;

  @override
  Widget build(BuildContext context) {
    final int reach = series.fold<int>(0, (int s, ChannelDayStats d) => s + d.reach);
    final int reactions =
        series.fold<int>(0, (int s, ChannelDayStats d) => s + d.reactions);
    final int net = series.fold<int>(0, (int s, ChannelDayStats d) => s + d.netFollowers);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: <Widget>[
          _Kpi(
            label: context.l10n.followers,
            value: TextUtils.compactCount(channel?.followerCount ?? 0),
            icon: Icons.people_alt_outlined,
          ),
          _Kpi(
            label: context.l10n.net28d,
            value: '${net >= 0 ? '+' : ''}${TextUtils.compactCount(net)}',
            icon: Icons.trending_up_rounded,
          ),
          _Kpi(
            label: context.l10n.reach,
            value: TextUtils.compactCount(reach),
            icon: Icons.visibility_outlined,
          ),
          _Kpi(
            label: context.l10n.reactions,
            value: TextUtils.compactCount(reactions),
            icon: Icons.favorite_border_rounded,
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Expanded(
      child: Column(
        children: <Widget>[
          Icon(icon, size: 18, color: c.accent),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: context.t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: context.t.bodySmall?.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Follower growth as a line chart, with the zero line marked.
class _FollowerLine extends StatelessWidget {
  const _FollowerLine({required this.series});

  final List<ChannelDayStats> series;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    if (series.isEmpty) return const _NoData();

    double running = 0;
    final List<FlSpot> spots = <FlSpot>[];
    for (int i = 0; i < series.length; i++) {
      running += series[i].netFollowers;
      spots.add(FlSpot(i.toDouble(), running));
    }

    final double maxY = spots
        .map((FlSpot s) => s.y)
        .fold<double>(0, (double a, double b) => b > a ? b : a);
    final double minY = spots
        .map((FlSpot s) => s.y)
        .fold<double>(0, (double a, double b) => b < a ? b : a);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (series.length - 1).toDouble(),
        minY: minY < 0 ? minY * 1.15 : 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.15,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _interval(maxY - minY),
          getDrawingHorizontalLine: (double value) => FlLine(
            color: c.divider,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: _interval(maxY - minY),
              getTitlesWidget: (double value, TitleMeta meta) => Text(
                TextUtils.compactCount(value.round()),
                style: context.t.bodySmall?.copyWith(color: c.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 7,
              getTitlesWidget: (double value, TitleMeta meta) =>
                  _DayLabel(index: value.round(), series: series),
            ),
          ),
        ),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.22,
            color: c.accent,
            barWidth: 2.4,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: c.accent.withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Daily reach as a bar chart.
class _ReachBars extends StatelessWidget {
  const _ReachBars({required this.series});

  final List<ChannelDayStats> series;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    if (series.isEmpty) return const _NoData();

    final int maxY = series
        .map((ChannelDayStats d) => d.reach)
        .fold<int>(0, (int a, int b) => b > a ? b : a);

    return BarChart(
      BarChartData(
        maxY: (maxY <= 0 ? 1 : maxY * 1.2).toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _interval(maxY.toDouble()),
          getDrawingHorizontalLine: (double value) => FlLine(
            color: c.divider,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: _interval(maxY.toDouble()),
              getTitlesWidget: (double value, TitleMeta meta) => Text(
                TextUtils.compactCount(value.round()),
                style: context.t.bodySmall?.copyWith(color: c.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 7,
              getTitlesWidget: (double value, TitleMeta meta) =>
                  _DayLabel(index: value.round(), series: series),
            ),
          ),
        ),
        barGroups: <BarChartGroupData>[
          for (int i = 0; i < series.length; i++)
            BarChartGroupData(
              x: i,
              barRods: <BarChartRodData>[
                BarChartRodData(
                  toY: series[i].reach.toDouble(),
                  color: c.accent.withValues(alpha: 0.85),
                  width: 6,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Reaction breakdown as a pie chart.
class _ReactionPie extends StatelessWidget {
  const _ReactionPie({required this.posts});

  final List<ChannelPost> posts;

  static const List<Color> _palette = <Color>[
    Color(0xFF2D7DFF),
    Color(0xFFFF2D55),
    Color(0xFFFFB020),
    Color(0xFF8E7CFF),
    Color(0xFF34C759),
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;

    final Map<ChannelReactionKind, int> tally = <ChannelReactionKind, int>{};
    for (final ChannelPost post in posts) {
      for (final ChannelReactionKind kind in ChannelReactionKind.values) {
        final int n = post.countOf(kind);
        if (n > 0) tally[kind] = (tally[kind] ?? 0) + n;
      }
    }
    final int total = tally.values.fold<int>(0, (int a, int b) => a + b);
    if (total == 0) return const _NoData();

    final List<ChannelReactionKind> kinds = tally.keys.toList();

    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 34,
              sections: <PieChartSectionData>[
                for (int i = 0; i < kinds.length; i++)
                  PieChartSectionData(
                    value: tally[kinds[i]]!.toDouble(),
                    color: _palette[i % _palette.length],
                    radius: 34,
                    title: '${((tally[kinds[i]]! / total) * 100).round()}%',
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < kinds.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _palette[i % _palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        channelReactionEmoji(kinds[i]),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        TextUtils.compactCount(tally[kinds[i]]!),
                        style: context.t.bodySmall?.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The five best-performing posts by view count.
class _TopPosts extends StatelessWidget {
  const _TopPosts({required this.posts});

  final List<ChannelPost> posts;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final List<ChannelPost> ranked = <ChannelPost>[...posts]
      ..sort((ChannelPost a, ChannelPost b) => b.viewCount.compareTo(a.viewCount));
    final List<ChannelPost> top = ranked.take(5).toList();

    if (top.isEmpty) return const _NoData();

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: top.length,
      itemBuilder: (BuildContext context, int index) {
        final ChannelPost post = top[index];
        final String preview = post.text.trim().isEmpty
            ? (post.hasMedia
                ? context.l10n.photoPost
                : context.l10n.textPost)
            : post.text.trim();
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 22,
                child: Text(
                  '${index + 1}',
                  style: context.t.titleSmall?.copyWith(
                    color: c.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  TextUtils.truncate(preview, 46),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodyMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.visibility_outlined,
                size: 13,
                color: c.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                TextUtils.compactCount(post.viewCount),
                style: context.t.bodySmall?.copyWith(color: c.textSecondary),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '❤ ${TextUtils.compactCount(post.totalReactions)}',
                style: context.t.bodySmall?.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.insights_outlined, size: 28, color: c.textSecondary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.noDataForThisPeriod,
            style: context.t.bodySmall?.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A `d MMM` axis label for a series index, or nothing when out of range.
class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.index, required this.series});

  final int index;
  final List<ChannelDayStats> series;

  @override
  Widget build(BuildContext context) {
    if (index < 0 || index >= series.length) return const SizedBox.shrink();
    final DateTime date = series[index].date;
    return Text(
      DateFormat('d/M').format(date),
      style: context.t.bodySmall?.copyWith(
        color: context.c.textSecondary,
        fontSize: 10,
      ),
    );
  }
}

/// A grid interval that keeps the axis readable for both tiny and large values.
double _interval(double range) {
  if (range <= 0) return 1;
  final double rough = range / 4;
  final double magnitude =
      rough <= 1 ? 1 : (rough <= 10 ? 2 : (rough <= 50 ? 10 : rough / 5));
  return magnitude <= 0 ? 1 : magnitude;
}
