import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/commits_vm.dart';
import '../../view_models/members_vm.dart';
import '../../view_models/stats_vm.dart';
import '../../view_models/tasks_board_vm.dart';

// StatsViewPage — four fl_chart visualizations derived from the per-repo
// ViewModels: a task-status donut, commits-per-author bars, a 14-day commits
// trend, and per-member task load.
//
// CAVEAT: the two commit-derived charts (author bars + daily trend) only
// reflect the commits currently loaded by CommitsViewModel — the recent-50
// window, or the day range picked on the Daily page. They are intentionally
// not a separate full-history query (task 06-06 prd §5).
class StatsViewPage extends StatelessWidget {
  const StatsViewPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProxyProvider3<TasksBoardViewModel, CommitsViewModel,
        MembersViewModel, StatsViewModel>(
      create: (_) => StatsViewModel(),
      update: (_, tasks, commits, members, prev) =>
          (prev ?? StatsViewModel())
            ..updateFromUpstream(
              tasks: tasks,
              commits: commits,
              members: members,
            ),
      child: Scaffold(
        appBar: AppBar(title: const Text('Stats')),
        body: Consumer<StatsViewModel>(
          builder: (ctx, vm, _) {
            return ListView(
              padding: const EdgeInsets.all(AppDimens.spacingMd),
              children: [
                _StatCard(
                  title: 'Task status',
                  icon: Icons.task_alt_outlined,
                  child: _TaskStatusDonut(counts: vm.statusCounts),
                ),
                const SizedBox(height: AppDimens.spacingMd),
                _StatCard(
                  title: 'Commits per author',
                  icon: Icons.commit_outlined,
                  child: _CommitsPerAuthorBar(perAuthor: vm.commitsPerAuthor),
                ),
                const SizedBox(height: AppDimens.spacingMd),
                _StatCard(
                  title: 'Daily commits (last 14 days)',
                  icon: Icons.show_chart_outlined,
                  child: _DailyCommitsTrend(days: vm.commitsPerDay),
                ),
                const SizedBox(height: AppDimens.spacingMd),
                _StatCard(
                  title: 'Member load',
                  icon: Icons.people_alt_outlined,
                  child: _MemberLoadBar(loads: vm.memberLoad),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---- Task status donut ------------------------------------------------------

class _TaskStatusDonut extends StatelessWidget {
  const _TaskStatusDonut({required this.counts});
  final Map<TaskStatus, int> counts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = counts.values.fold<int>(0, (a, b) => a + b);

    if (total == 0) {
      return const _EmptyHint('No tasks yet');
    }

    final entries = [
      for (final status in TaskStatus.values)
        (
          status: status,
          label: _statusLabel(status),
          value: counts[status] ?? 0,
          color: _statusColor(status, scheme),
        ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 52,
                  sections: [
                    for (final e in entries)
                      if (e.value > 0)
                        PieChartSectionData(
                          value: e.value.toDouble(),
                          color: e.color,
                          title: '${e.value}',
                          radius: 36,
                          titleStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimary,
                          ),
                        ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'tasks',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.spacingMd),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppDimens.spacingMd,
          runSpacing: AppDimens.spacingXs,
          children: [
            for (final e in entries)
              _LegendDot(color: e.color, label: '${e.label} (${e.value})'),
          ],
        ),
      ],
    );
  }
}

// ---- Commits per author -----------------------------------------------------

class _CommitsPerAuthorBar extends StatelessWidget {
  const _CommitsPerAuthorBar({required this.perAuthor});
  final Map<String, int> perAuthor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (perAuthor.isEmpty) {
      return const _EmptyHint('No commits in the loaded window');
    }

    final authors = perAuthor.keys.toList();
    final maxY = perAuthor.values.fold<int>(0, (a, b) => a > b ? a : b);
    final palette = _categoricalPalette(scheme);

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (maxY + 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _yInterval(maxY),
                getTitlesWidget: (value, meta) => _axisText(
                  context,
                  value.toInt().toString(),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= authors.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: 64,
                      child: Text(
                        authors[i],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < authors.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (perAuthor[authors[i]] ?? 0).toDouble(),
                    color: palette[i % palette.length],
                    width: 18,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppDimens.radiusSm),
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

// ---- Daily commits trend ----------------------------------------------------

class _DailyCommitsTrend extends StatelessWidget {
  const _DailyCommitsTrend({required this.days});
  final List<DayCount> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = days.fold<int>(0, (a, b) => a + b.count);
    if (days.isEmpty || total == 0) {
      return const _EmptyHint('No commits in the loaded window');
    }

    final maxY = days.fold<int>(0, (a, b) => a > b.count ? a : b.count);

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (days.length - 1).toDouble(),
          minY: 0,
          maxY: (maxY + 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _yInterval(maxY),
                getTitlesWidget: (value, meta) =>
                    _axisText(context, value.toInt().toString()),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                // Sparse labels: every 3rd day reads as MM/dd.
                interval: 3,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= days.length) {
                    return const SizedBox.shrink();
                  }
                  if (i % 3 != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _axisText(context, _mmdd(days[i].day)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              isCurved: true,
              color: scheme.primary,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.12),
              ),
              spots: [
                for (var i = 0; i < days.length; i++)
                  FlSpot(i.toDouble(), days[i].count.toDouble()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Member load ------------------------------------------------------------

class _MemberLoadBar extends StatelessWidget {
  const _MemberLoadBar({required this.loads});
  final List<MemberLoad> loads;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (loads.isEmpty) {
      return const _EmptyHint('No assigned in-progress or done tasks');
    }

    final inProgressColor = scheme.tertiary;
    final doneColor = scheme.primary;
    final maxY = loads.fold<int>(
      0,
      (a, l) => a > l.total ? a : l.total,
    );

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (maxY + 1).toDouble(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: scheme.outlineVariant, strokeWidth: 0.5),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: _yInterval(maxY),
                    getTitlesWidget: (value, meta) =>
                        _axisText(context, value.toInt().toString()),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= loads.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: 72,
                          child: Text(
                            loads[i].label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Stacked bar: in-progress sits below done.
              barGroups: [
                for (var i = 0; i < loads.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: loads[i].total.toDouble(),
                        width: 22,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppDimens.radiusSm),
                        ),
                        rodStackItems: [
                          BarChartRodStackItem(
                            0,
                            loads[i].inProgress.toDouble(),
                            inProgressColor,
                          ),
                          BarChartRodStackItem(
                            loads[i].inProgress.toDouble(),
                            loads[i].total.toDouble(),
                            doneColor,
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppDimens.spacingMd),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppDimens.spacingMd,
          runSpacing: AppDimens.spacingXs,
          children: [
            _LegendDot(color: inProgressColor, label: 'In progress'),
            _LegendDot(color: doneColor, label: 'Done'),
          ],
        ),
      ],
    );
  }
}

// ---- Shared bits ------------------------------------------------------------

// Titled card wrapper for a stats section.
class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: AppDimens.spacingSm),
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: AppDimens.spacingMd),
            child,
          ],
        ),
      ),
    );
  }
}

// A small colored dot + label, used by chart legends.
class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: AppDimens.spacingXs + 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// Compact per-card empty-state hint (not the full-screen EmptyState widget).
class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingLg),
      child: Center(
        child: Text(
          message,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ---- helpers ----------------------------------------------------------------

String _statusLabel(TaskStatus s) => switch (s) {
      TaskStatus.todo => 'To do',
      TaskStatus.inProgress => 'In progress',
      TaskStatus.done => 'Done',
    };

// Exhaustive switch on TaskStatus (mirrors task_graph_tab) so a new status is a
// compile error rather than a silent default.
Color _statusColor(TaskStatus s, ColorScheme scheme) => switch (s) {
      TaskStatus.todo => scheme.secondary,
      TaskStatus.inProgress => scheme.tertiary,
      TaskStatus.done => scheme.primary,
    };

// Categorical palette derived from the theme for the per-author bars.
List<Color> _categoricalPalette(ColorScheme scheme) => [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.primaryContainer,
      scheme.tertiaryContainer,
      scheme.secondaryContainer,
    ];

// Keep the y-axis to a handful of integer gridlines.
double _yInterval(int maxY) {
  if (maxY <= 5) return 1;
  return (maxY / 5).ceilToDouble();
}

Widget _axisText(BuildContext context, String text) => Text(
      text,
      style: Theme.of(context).textTheme.labelSmall,
    );

String _mmdd(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
