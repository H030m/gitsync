import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_dimens.dart';
import '../../view_models/members_vm.dart';
import '../../view_models/stats_vm.dart';
import '../../view_models/tasks_board_vm.dart';

// StatsViewPage — faithful rebuild of the design prototype's two-tab Stats
// screen (StatsView.tsx): a 貢獻度 contribution pie and a 進度表 per-member
// progress table with expandable task lists. Derived purely from tasks +
// members via StatsViewModel (no commits — the prototype has none).
class StatsViewPage extends StatelessWidget {
  const StatsViewPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProxyProvider2<TasksBoardViewModel, MembersViewModel,
        StatsViewModel>(
      create: (_) => StatsViewModel(repoId: repoId),
      update: (_, tasks, members, prev) =>
          (prev ?? StatsViewModel(repoId: repoId))
            ..updateFromUpstream(tasks: tasks, members: members),
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('統計'),
            bottom: const TabBar(
              tabs: [
                Tab(text: '貢獻度'),
                Tab(text: '進度表'),
              ],
            ),
          ),
          body: Consumer<StatsViewModel>(
            builder: (ctx, vm, _) {
              return TabBarView(
                children: [
                  _ContributionTab(vm: vm),
                  _ProgressTab(progress: vm.memberProgress),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---- Tab 1: 貢獻度 (contribution pie) --------------------------------------

/// Which basis the 貢獻度 pie is computed from.
enum _ContributionBasis { commit, task }

class _ContributionTab extends StatefulWidget {
  const _ContributionTab({required this.vm});
  final StatsViewModel vm;

  @override
  State<_ContributionTab> createState() => _ContributionTabState();
}

class _ContributionTabState extends State<_ContributionTab> {
  // Default to the commit basis — the all-history commit share is the headline
  // the user asked for.
  _ContributionBasis _basis = _ContributionBasis.commit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vm = widget.vm;

    final isCommit = _basis == _ContributionBasis.commit;
    final contributions =
        isCommit ? vm.commitContributions : vm.contributions;
    final caption = isCommit
        ? '全部 commit 累計的貢獻度'
        : '已完成的任務累計的貢獻度';

    final toggle = Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.spacingMd),
      child: Center(
        child: SegmentedButton<_ContributionBasis>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: _ContributionBasis.commit,
              label: Text('commit'),
            ),
            ButtonSegment(
              value: _ContributionBasis.task,
              label: Text('任務'),
            ),
          ],
          selected: {_basis},
          onSelectionChanged: (s) => setState(() => _basis = s.first),
        ),
      ),
    );

    // Commit basis is still loading its one-shot fetch.
    if (isCommit && vm.commitsLoading) {
      return ListView(
        padding: const EdgeInsets.all(AppDimens.spacingMd),
        children: [
          toggle,
          const Padding(
            padding: EdgeInsets.all(AppDimens.spacingLg),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (contributions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppDimens.spacingMd),
        children: [
          toggle,
          _EmptyHint(isCommit ? '尚無 commit 紀錄' : '尚無已完成的任務'),
        ],
      );
    }

    final palette = _categoricalPalette(scheme);
    final colored = [
      for (var i = 0; i < contributions.length; i++)
        (item: contributions[i], color: palette[i % palette.length]),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppDimens.spacingMd),
      children: [
        toggle,
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.spacingMd),
            child: Column(
              children: [
                SizedBox(
                  height: 240,
                  width: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 28,
                          sections: [
                            for (final c in colored)
                              PieChartSectionData(
                                value: c.item.doneCount.toDouble(),
                                color: c.color,
                                radius: 90,
                                title: c.item.label,
                                titlePositionPercentageOffset: 0.6,
                                titleStyle: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _onSliceColor(scheme),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '貢獻度',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          Text(
                            '圓餅圖',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
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
                    for (final c in colored)
                      _LegendDot(
                        color: c.color,
                        label: '${c.item.label} — ${c.item.pct}%',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppDimens.spacingMd),
        _CaptionCard(caption),
      ],
    );
  }
}

// ---- Tab 2: 進度表 (per-member progress + task lists) -----------------------

class _ProgressTab extends StatelessWidget {
  const _ProgressTab({required this.progress});
  final List<MemberProgress> progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (progress.isEmpty) {
      return const _EmptyHint('尚無已指派的任務');
    }

    final palette = _categoricalPalette(scheme);

    return ListView(
      padding: const EdgeInsets.all(AppDimens.spacingMd),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.spacingMd),
            child: Column(
              children: [
                for (var i = 0; i < progress.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppDimens.spacingMd),
                  _MemberProgressRow(
                    member: progress[i],
                    color: palette[i % palette.length],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppDimens.spacingMd),
        const _CaptionCard('每個人當前未完成任務的進度'),
      ],
    );
  }
}

class _MemberProgressRow extends StatefulWidget {
  const _MemberProgressRow({required this.member, required this.color});
  final MemberProgress member;
  final Color color;

  @override
  State<_MemberProgressRow> createState() => _MemberProgressRowState();
}

class _MemberProgressRowState extends State<_MemberProgressRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = widget.member;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              m.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${m.pct}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.spacingSm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          child: LinearProgressIndicator(
            value: m.pct / 100,
            minHeight: 8,
            color: widget.color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: AppDimens.spacingXs),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingXs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppDimens.spacingXs),
                Text(
                  '詳細情形',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: AppDimens.spacingSm,
              top: AppDimens.spacingXs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in m.tasks) _TaskLine(task: t),
              ],
            ),
          ),
      ],
    );
  }
}

class _TaskLine extends StatelessWidget {
  const _TaskLine({required this.task});
  final ProgressTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: AppDimens.spacingSm),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: task.done
                    ? scheme.outlineVariant
                    : scheme.onSurfaceVariant,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              task.title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: task.done
                    ? scheme.onSurfaceVariant
                    : scheme.onSurface,
                decoration:
                    task.done ? TextDecoration.lineThrough : TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Shared bits ------------------------------------------------------------

// A small colored dot + label, used by the pie legend.
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
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppDimens.spacingXs + 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// The caption container under each tab (e.g. 已完成的任務累計的貢獻度).
class _CaptionCard extends StatelessWidget {
  const _CaptionCard(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingMd,
        vertical: AppDimens.spacingSm + AppDimens.spacingXs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

// Full-tab empty-state hint when there are no members/tasks for a tab.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.spacingLg),
        child: Text(
          message,
          textAlign: TextAlign.center,
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

// Ordered categorical palette derived from the theme, cycled for >N members.
// Mirrors the prototype's intent (light: a blue family; dark: the warm accent +
// blues) by sourcing from colorScheme rather than hardcoded hexes.
List<Color> _categoricalPalette(ColorScheme scheme) => [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.primaryContainer,
      scheme.tertiaryContainer,
      scheme.secondaryContainer,
    ];

// Contrast color for the member name drawn inside a pie slice.
Color _onSliceColor(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark ? scheme.onPrimaryContainer : Colors.white;
