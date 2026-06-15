import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';
import '../../view_models/members_vm.dart';
import '../../view_models/stats_vm.dart';
import '../../view_models/tasks_board_vm.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/markdown_view.dart';
import '../../widgets/section_card.dart';
import '../../widgets/staggered_entry.dart';

// StatsViewPage — two-tab Stats screen: a contribution pie and a per-member
// progress list with expandable AI work summaries.
class StatsViewPage extends StatelessWidget {
  const StatsViewPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
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
            title: Text(s.statsTitle),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(kTextTabBarHeight + 1),
              child: Column(
                children: [
                  const Divider(height: 1),
                  TabBar(
                    tabs: [
                      Tab(text: s.contributionTab),
                      Tab(text: s.progressTab),
                    ],
                  ),
                ],
              ),
            ),
          ),
          body: Consumer<StatsViewModel>(
            builder: (ctx, vm, _) {
              return TabBarView(
                children: [
                  _ContributionTab(vm: vm),
                  _ProgressTab(vm: vm),
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

enum _ContributionBasis { commit, task }

class _ContributionTab extends StatefulWidget {
  const _ContributionTab({required this.vm});
  final StatsViewModel vm;

  @override
  State<_ContributionTab> createState() => _ContributionTabState();
}

class _ContributionTabState extends State<_ContributionTab> {
  _ContributionBasis _basis = _ContributionBasis.commit;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final vm = widget.vm;

    final isCommit = _basis == _ContributionBasis.commit;
    final contributions =
        isCommit ? vm.commitContributions : vm.contributions;
    final caption =
        isCommit ? s.commitContributionCaption : s.taskContributionCaption;

    final toggle = StaggeredEntry(
      key: const ValueKey('stats-toggle'),
      index: 0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.spacingMd),
        child: Center(
          child: SegmentedButton<_ContributionBasis>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _ContributionBasis.commit,
                label: Text(s.contributionBasisCommit),
              ),
              ButtonSegment(
                value: _ContributionBasis.task,
                label: Text(s.contributionBasisTask),
              ),
            ],
            selected: {_basis},
            onSelectionChanged: (sel) => setState(() => _basis = sel.first),
          ),
        ),
      ),
    );

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
          EmptyState(
            icon: isCommit ? Icons.commit_outlined : Icons.task_alt_outlined,
            title: isCommit ? s.noCommitRecords : s.noDoneTasks,
          ),
        ],
      );
    }

    final totalCount = contributions.fold<int>(0, (a, c) => a + c.doneCount);
    final palette = _categoricalPalette(scheme);
    final colored = [
      for (var i = 0; i < contributions.length; i++)
        (item: contributions[i], color: palette[i % palette.length]),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppDimens.spacingMd),
      children: [
        toggle,
        StaggeredEntry(
          key: const ValueKey('stats-pie'),
          index: 1,
          child: SectionCard(
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
                          centerSpaceRadius: 50,
                          sections: [
                            for (final c in colored)
                              PieChartSectionData(
                                value: c.item.doneCount.toDouble(),
                                color: c.color,
                                radius: 65,
                                showTitle: false,
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 88,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '$totalCount',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                isCommit ? 'commits' : s.contributionBasisTask,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
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
        StaggeredEntry(
          key: const ValueKey('stats-caption'),
          index: 2,
          child: SectionCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.spacingMd,
              vertical: AppDimens.spacingSm + AppDimens.spacingXs,
            ),
            child: Text(
              caption,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Tab 2: 進度表 (per-author AI work summaries) --------------------------

class _ProgressTab extends StatelessWidget {
  const _ProgressTab({required this.vm});
  final StatsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    if (vm.commitsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppDimens.spacingLg),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final authors = vm.authorGroups;
    if (authors.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        title: s.noCommitRecords,
      );
    }

    final palette = _categoricalPalette(scheme);

    return ListView(
      padding: const EdgeInsets.all(AppDimens.spacingMd),
      children: [
        for (var i = 0; i < authors.length; i++) ...[
          StaggeredEntry(
            key: ValueKey('stats-author-${authors[i].key}'),
            index: i,
            child: SectionCard(
              child: _AuthorSummaryRow(
                vm: vm,
                author: authors[i],
                color: palette[i % palette.length],
              ),
            ),
          ),
          if (i < authors.length - 1)
            const SizedBox(height: AppDimens.spacingSm),
        ],
        const SizedBox(height: AppDimens.spacingMd),
        StaggeredEntry(
          key: const ValueKey('stats-progress-caption'),
          index: authors.length,
          child: SectionCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.spacingMd,
              vertical: AppDimens.spacingSm + AppDimens.spacingXs,
            ),
            child: Text(
              s.authorContributionCaption,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthorSummaryRow extends StatefulWidget {
  const _AuthorSummaryRow({
    required this.vm,
    required this.author,
    required this.color,
  });
  final StatsViewModel vm;
  final AuthorGroup author;
  final Color color;

  @override
  State<_AuthorSummaryRow> createState() => _AuthorSummaryRowState();
}

class _AuthorSummaryRowState extends State<_AuthorSummaryRow> {
  bool _expanded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      widget.vm.loadAuthorSummary(widget.author);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final g = widget.author;
    final key = g.key;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                g.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              s.authorCommitStats(g.commitCount, g.pct),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.spacingSm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          child: LinearProgressIndicator(
            value: g.pct / 100,
            minHeight: 8,
            color: widget.color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: AppDimens.spacingXs),
        TextButton.icon(
          onPressed: _toggle,
          icon: AnimatedRotation(
            turns: _expanded ? 0.0 : -0.25,
            duration: AppMotion.short,
            curve: AppMotion.emphasizedDecel,
            child: const Icon(Icons.expand_more, size: 18),
          ),
          label: Text(s.statsDetails),
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            textStyle: theme.textTheme.bodySmall,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.spacingSm),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.medium,
          curve: AppMotion.emphasizedDecel,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(
                    left: AppDimens.spacingSm,
                    top: AppDimens.spacingXs,
                  ),
                  child: _AuthorSummaryBody(
                      vm: widget.vm, author: g, summaryKey: key),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _AuthorSummaryBody extends StatelessWidget {
  const _AuthorSummaryBody({
    required this.vm,
    required this.author,
    required this.summaryKey,
  });
  final StatsViewModel vm;
  final AuthorGroup author;
  final String summaryKey;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (vm.isSummarizing(summaryKey)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppDimens.spacingSm),
            Text(s.aiSummaryGenerating),
          ],
        ),
      );
    }

    final error = vm.summaryError(summaryKey);
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
        child: TextButton.icon(
          onPressed: () => vm.loadAuthorSummary(author, force: true),
          icon: Icon(Icons.refresh, size: 16, color: scheme.error),
          label: Text(
            s.summaryFailedRetry,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
          style: TextButton.styleFrom(
            foregroundColor: scheme.error,
            padding:
                const EdgeInsets.symmetric(horizontal: AppDimens.spacingSm),
          ),
        ),
      );
    }

    final markdown = vm.authorSummary(summaryKey);
    if (markdown == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s.aiWorkSummaryTitle,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            IconButton(
              tooltip: s.regenerate,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 16),
              onPressed: () => vm.loadAuthorSummary(author, force: true),
            ),
          ],
        ),
        MarkdownView(data: markdown),
      ],
    );
  }
}

// ---- Shared bits ------------------------------------------------------------

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
        const SizedBox(width: AppDimens.spacingSm),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// Categorical palette for charts. Uses high-saturation semantic-neutral colors
// and avoids *Container tones which lack contrast in dark mode.
List<Color> _categoricalPalette(ColorScheme scheme) => [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.inversePrimary,
    ];
