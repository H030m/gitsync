import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/commit.dart';
import '../../models/daily_brief.dart';
import '../../models/daily_report.dart';
import '../../models/discord_chat.dart';
import '../../models/discord_digest.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/commits_vm.dart';
import '../../view_models/daily_brief_vm.dart';
import '../../view_models/daily_report_vm.dart';
import '../../view_models/discord_chat_vm.dart';
import '../../view_models/discord_messages_vm.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/markdown_view.dart';

// DailyViewPage — three tabs: Summary / Commits / Discord.
// TODO: implement per prototype `daily/DailyView.tsx`.
class DailyViewPage extends StatelessWidget {
  const DailyViewPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Daily'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Summary'),
              Tab(text: 'Commits'),
              Tab(text: 'Discord'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_SummaryTab(), _CommitsTab(), _DiscordTab()],
        ),
      ),
    );
  }
}

// The Summary tab is the developer "intelligence hub": an AI daily report
// (summary + highlights + blockers + commit-message rollup + per-member
// contributions) on top, and an agentic "ask AI about today" chat at the
// bottom. The report streams from `dailyReports/{date}`; the chat hits the
// `dailyBrief` callable. Both areas share one vertical scroll, with the chat
// input bar pinned to the bottom (mirrors the Discord tab).
class _SummaryTab extends StatefulWidget {
  const _SummaryTab();

  @override
  State<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<_SummaryTab> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send(DailyBriefChatViewModel vm) {
    final text = _controller.text;
    if (text.trim().isEmpty || vm.sending) return;
    _controller.clear();
    vm.ask(text);
    // Jump to the latest turn once it's laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<DailyReportViewModel, DailyBriefChatViewModel>(
      builder: (ctx, report, chat, _) {
        if (report.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppDimens.spacingMd),
                children: [
                  _PeriodBar(report: report, chat: chat),
                  const SizedBox(height: AppDimens.spacingSm),
                  _ReportCard(vm: report),
                  if (report.report != null && !report.report!.isEmpty) ...[
                    _HighlightsCard(report: report.report!),
                    _CommitRollupCard(report: report.report!),
                    _ContributionsCard(report: report.report!),
                  ],
                  const SizedBox(height: AppDimens.spacingMd),
                  const _BriefHeader(),
                  const SizedBox(height: AppDimens.spacingSm),
                  if (chat.turns.isEmpty)
                    const _BriefHint()
                  else
                    for (final turn in chat.turns) _BriefTurnView(turn: turn),
                  if (chat.sending) const _ThinkingBubble(),
                ],
              ),
            ),
            _BriefInputBar(
              controller: _controller,
              sending: chat.sending,
              onSend: () => _send(chat),
            ),
          ],
        );
      },
    );
  }
}

// Period picker for the intelligence hub. Re-points BOTH the report stream and
// the "ask AI" chat scope at the picked inclusive day range.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.report, required this.chat});
  final DailyReportViewModel report;
  final DailyBriefChatViewModel chat;

  String get _label => report.isSingleDay
      ? (_dayKey(report.rangeStart) == _dayKey(DateTime.now())
            ? 'Today'
            : _monthDay(report.rangeStart))
      : '${_monthDay(report.rangeStart)} ~ ${_monthDay(report.rangeEnd)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          'Period',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: now,
              initialDateRange: DateTimeRange(
                start: report.rangeStart,
                end: report.rangeEnd,
              ),
            );
            if (picked == null) return;
            report.setRange(picked.start, picked.end);
            chat.setRange(picked.start, picked.end);
          },
          icon: const Icon(Icons.date_range_outlined, size: 18),
          label: Text(_label),
        ),
      ],
    );
  }
}

// AI daily-summary card with the regenerate action. Shows an empty state when
// no report exists yet for the day.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.vm});
  final DailyReportViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = vm.report;
    final hasReport = report != null && !report.isEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppDimens.spacingSm),
                Text(
                  'Daily summary',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (report != null && report.commitCount > 0)
                  _CountChip(
                    icon: Icons.commit_outlined,
                    label: '${report.commitCount}',
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.spacingSm),
            Text(
              hasReport
                  ? report.summary
                  : 'No report generated for this period yet. Tap Regenerate '
                        'to let the AI summarize the period’s commits, tasks '
                        'and chat.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppDimens.spacingMd),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: vm.regenerating ? null : vm.regenerate,
                icon: vm.regenerating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(vm.regenerating ? 'Generating…' : 'Regenerate'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Highlights (wins) + blockers, each a labelled list. Renders nothing for an
// empty section so the card stays compact.
class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard({required this.report});
  final DailyReport report;

  @override
  Widget build(BuildContext context) {
    if (report.highlights.isEmpty && report.blockers.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.spacingMd),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final h in report.highlights)
                _BulletRow(
                  icon: Icons.check_circle_outline,
                  color: scheme.primary,
                  text: h,
                ),
              if (report.highlights.isNotEmpty && report.blockers.isNotEmpty)
                const SizedBox(height: AppDimens.spacingSm),
              for (final b in report.blockers)
                _BulletRow(
                  icon: Icons.report_problem_outlined,
                  color: scheme.error,
                  text: b,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Commit-message rollup: the day's commits grouped into AI-labelled themes.
class _CommitRollupCard extends StatelessWidget {
  const _CommitRollupCard({required this.report});
  final DailyReport report;

  @override
  Widget build(BuildContext context) {
    if (report.commitThemes.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.spacingMd),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.merge_type_outlined,
                    size: 20,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: AppDimens.spacingSm),
                  Text(
                    'Commit rollup',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.spacingSm),
              for (final t in report.commitThemes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppDimens.spacingSm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.theme,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (t.summary.isNotEmpty)
                              Text(
                                t.summary,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (t.commitCount > 0) ...[
                        const SizedBox(width: AppDimens.spacingSm),
                        _CountChip(
                          icon: Icons.commit_outlined,
                          label: '${t.commitCount}',
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Per-member contribution chips (tasks done + commits), keyed as the backend
// reports them (userId, or author login for unmatched commits).
class _ContributionsCard extends StatelessWidget {
  const _ContributionsCard({required this.report});
  final DailyReport report;

  @override
  Widget build(BuildContext context) {
    final entries = report.memberContributions.entries
        .where((e) => e.value.tasksDone > 0 || e.value.commits > 0)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.spacingMd),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 20,
                    color: scheme.secondary,
                  ),
                  const SizedBox(width: AppDimens.spacingSm),
                  Text(
                    'Contributions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.spacingSm),
              Wrap(
                spacing: AppDimens.spacingSm,
                runSpacing: AppDimens.spacingSm,
                children: [
                  for (final e in entries)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.spacingSm,
                        vertical: AppDimens.spacingXs,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: scheme.primaryContainer,
                            child: Text(
                              _initial(_memberLabel(e)),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppDimens.spacingXs),
                          Text(
                            '${_memberLabel(e)}  ·  ${e.value.tasksDone}✓ '
                            '${e.value.commits}⎇',
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initial(String key) =>
      key.isEmpty ? '?' : key.substring(0, 1).toUpperCase();

  /// GitHub username, falling back to display name, then the raw map key
  /// (legacy reports written before the backend persisted names — that key is
  /// a Firebase UID for roster members or a login for unmatched authors).
  static String _memberLabel(MapEntry<String, MemberContribution> e) {
    final login = e.value.githubLogin;
    if (login != null && login.isNotEmpty) return login;
    final name = e.value.displayName;
    if (name != null && name.isNotEmpty) return name;
    return e.key;
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({
    required this.icon,
    required this.color,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppDimens.spacingSm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

// "Ask AI about today" section header.
class _BriefHeader extends StatelessWidget {
  const _BriefHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.forum_outlined, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: AppDimens.spacingSm),
        Text(
          'Ask AI about today',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BriefHint extends StatelessWidget {
  const _BriefHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppDimens.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'e.g. 「今天有哪些 commit 跟 OAuth 有關？」、「有沒有人提到 blocker？」、'
        '「breakdownTask 最近誰改的？」',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// One turn of the daily-brief chat: user bubble, or AI markdown answer with an
// optional commit-sources panel.
class _BriefTurnView extends StatelessWidget {
  const _BriefTurnView({required this.turn});
  final DailyBriefTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (turn.isUser) {
      return Padding(
        padding: const EdgeInsets.only(
          top: AppDimens.spacingMd,
          bottom: AppDimens.spacingXs,
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.spacingMd,
              vertical: AppDimens.spacingSm,
            ),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              turn.content,
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: AppDimens.spacingSm),
              Text(
                'AI',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.spacingSm),
          MarkdownView(data: turn.content),
          if (turn.sources.isNotEmpty) ...[
            const SizedBox(height: AppDimens.spacingSm),
            _BriefSourcesPanel(sources: turn.sources),
          ],
        ],
      ),
    );
  }
}

// Scrollable panel of the commits the AI surfaced for an answer.
class _BriefSourcesPanel extends StatelessWidget {
  const _BriefSourcesPanel({required this.sources});
  final List<DailyBriefSource> sources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.spacingMd,
              AppDimens.spacingSm,
              AppDimens.spacingMd,
              AppDimens.spacingXs,
            ),
            child: Row(
              children: [
                Icon(Icons.commit_outlined, size: 16, color: scheme.tertiary),
                const SizedBox(width: AppDimens.spacingXs),
                Text(
                  'Source commits (${sources.length})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.spacingMd,
                0,
                AppDimens.spacingMd,
                AppDimens.spacingSm,
              ),
              shrinkWrap: true,
              itemCount: sources.length,
              separatorBuilder: (_, _) => const Divider(height: 12),
              itemBuilder: (_, i) {
                final s = sources[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (s.aiSummary != null && s.aiSummary!.isNotEmpty)
                      Text(
                        s.aiSummary!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      '${s.authorName.isEmpty ? s.authorLogin : s.authorName}'
                      ' · ${s.shortSha}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Pinned input bar for the daily-brief chat (mirrors the Discord chat bar).
class _BriefInputBar extends StatelessWidget {
  const _BriefInputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.spacingMd,
          AppDimens.spacingSm,
          AppDimens.spacingMd,
          AppDimens.spacingMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                enabled: !sending,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Ask AI about today…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppDimens.spacingSm),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

// Commits tab — a scrollable commit tree map. One lane (column + color) per
// author, day separators, and tap-a-commit → an AI explanation of the work
// (the `explainCommit` callable, cached per sha). A range button filters the
// map to an inclusive day range.
class _CommitsTab extends StatelessWidget {
  const _CommitsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<CommitsViewModel>(
      builder: (ctx, vm, _) {
        if (vm.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.streamError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.spacingLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: AppDimens.spacingSm),
                  Text(
                    'Could not load commits',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppDimens.spacingXs),
                  Text(
                    vm.streamError!,
                    style: Theme.of(ctx).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppDimens.spacingMd),
                  FilledButton.icon(
                    onPressed: vm.retry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.spacingMd,
                AppDimens.spacingMd,
                AppDimens.spacingMd,
                AppDimens.spacingSm,
              ),
              child: Row(
                children: [
                  Text(
                    'Commit map',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (vm.hasRange)
                    IconButton(
                      tooltip: 'Clear range',
                      onPressed: vm.clearRange,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDateRangePicker(
                        context: ctx,
                        firstDate: DateTime(2020),
                        lastDate: now,
                        initialDateRange: vm.hasRange
                            ? DateTimeRange(
                                start: vm.rangeStart!,
                                end: vm.rangeEnd!,
                              )
                            : DateTimeRange(start: now, end: now),
                      );
                      if (picked == null) return;
                      vm.setRange(picked.start, picked.end);
                    },
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text(
                      vm.hasRange
                          ? '${_monthDay(vm.rangeStart!)} ~ ${_monthDay(vm.rangeEnd!)}'
                          : 'Recent 50',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: vm.commits.isEmpty
                  ? const EmptyState(
                      icon: Icons.commit_outlined,
                      title: 'No commits',
                      message:
                          'No commits in this period. Pick another range or '
                          'clear the filter.',
                    )
                  : _CommitTree(vm: vm),
            ),
          ],
        );
      },
    );
  }
}

// Lane palette for the tree map (index = lane). Wraps around if the team is
// larger than the palette.
const List<Color> _laneColors = [
  Color(0xFF4C9AFF), // blue
  Color(0xFF36B37E), // green
  Color(0xFFFF8B00), // orange
  Color(0xFF9C5FFF), // purple
  Color(0xFFFF5B7A), // pink
  Color(0xFF00B8D9), // teal
];

// One row of the flattened tree: either a day header or a commit with its
// precomputed lane geometry.
class _TreeRow {
  _TreeRow.header(this.dayLabel)
    : commit = null,
      lane = 0,
      activeLanes = const [];
  _TreeRow.commit(Commit this.commit, this.lane, this.activeLanes)
    : dayLabel = null;

  final String? dayLabel;
  final Commit? commit;
  final int lane;

  /// For each lane: whether a vertical line passes through this row.
  final List<bool> activeLanes;

  bool get isHeader => dayLabel != null;
}

// Hard cap on rail lanes — authors beyond this share the last lane so the
// rail never paints over the text column (bots can inflate author counts).
const int _maxLanes = 6;

// Builds the flattened row list: day headers + commits with lane geometry.
// Lanes are assigned per author in order of first (newest) appearance; a
// lane's line spans from its newest to its oldest commit.
List<_TreeRow> _buildTreeRows(List<Commit> commits) {
  final laneOf = <String, int>{};
  for (final c in commits) {
    laneOf.putIfAbsent(
      c.author.login,
      () => laneOf.length.clamp(0, _maxLanes - 1),
    );
  }
  final laneCount = laneOf.isEmpty
      ? 0
      : (laneOf.values.reduce((a, b) => a > b ? a : b) + 1);

  // First/last (newest/oldest) flat index of each lane, over commits only.
  final firstIdx = List<int>.filled(laneCount, -1);
  final lastIdx = List<int>.filled(laneCount, -1);
  for (var i = 0; i < commits.length; i++) {
    final lane = laneOf[commits[i].author.login]!;
    if (firstIdx[lane] == -1) firstIdx[lane] = i;
    lastIdx[lane] = i;
  }

  final rows = <_TreeRow>[];
  String? lastDay;
  for (var i = 0; i < commits.length; i++) {
    final c = commits[i];
    final day = _dayKey(c.committedAt.toDate());
    if (day != lastDay) {
      rows.add(_TreeRow.header(day));
      lastDay = day;
    }
    final active = List<bool>.generate(
      laneCount,
      (l) => firstIdx[l] <= i && i <= lastIdx[l],
    );
    rows.add(_TreeRow.commit(c, laneOf[c.author.login]!, active));
  }
  return rows;
}

class _CommitTree extends StatelessWidget {
  const _CommitTree({required this.vm});
  final CommitsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final rows = _buildTreeRows(vm.commits);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppDimens.spacingMd),
      itemCount: rows.length,
      itemBuilder: (ctx, i) {
        final row = rows[i];
        if (row.isHeader) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.spacingMd,
              AppDimens.spacingSm,
              AppDimens.spacingMd,
              AppDimens.spacingXs,
            ),
            child: Row(
              children: [
                Text(
                  row.dayLabel!,
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppDimens.spacingSm),
                const Expanded(child: Divider(height: 1)),
              ],
            ),
          );
        }
        return _CommitTreeRow(row: row, vm: vm);
      },
    );
  }
}

class _CommitTreeRow extends StatelessWidget {
  const _CommitTreeRow({required this.row, required this.vm});
  final _TreeRow row;
  final CommitsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = row.commit!;
    final color = _laneColors[row.lane % _laneColors.length];
    final laneWidth = 16.0;
    final railWidth =
        (row.activeLanes.length.clamp(1, 6)) * laneWidth + AppDimens.spacingSm;

    return InkWell(
      onTap: () => _showCommitSheet(context, c, vm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.spacingMd),
        // IntrinsicHeight bounds the stretch axis so the rail painter gets the
        // row's real height (a ListView child otherwise has unbounded height).
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: railWidth,
                child: CustomPaint(
                  painter: _LanePainter(
                    lane: row.lane,
                    activeLanes: row.activeLanes,
                    laneWidth: laneWidth,
                    color: color,
                    lineColor: scheme.outlineVariant,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppDimens.spacingSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.message.split('\n').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppDimens.spacingXs),
                          Flexible(
                            child: Text(
                              '${c.author.name.isEmpty ? c.author.login : c.author.name}'
                              ' · ${c.sha.substring(0, 7)}'
                              ' · ${_hhmm(c.committedAt.toDate())}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (c.aiSummary != null) ...[
                            const SizedBox(width: AppDimens.spacingXs),
                            Icon(
                              Icons.auto_awesome_outlined,
                              size: 12,
                              color: scheme.primary,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

// Paints the tree rail for one commit row: a vertical line for every lane
// whose span covers this row, and a node dot on the commit's own lane.
class _LanePainter extends CustomPainter {
  _LanePainter({
    required this.lane,
    required this.activeLanes,
    required this.laneWidth,
    required this.color,
    required this.lineColor,
  });

  final int lane;
  final List<bool> activeLanes;
  final double laneWidth;
  final Color color;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2;
    for (var l = 0; l < activeLanes.length; l++) {
      if (!activeLanes[l]) continue;
      final x = laneWidth / 2 + l * laneWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    // Node dot (ring + fill) on this commit's lane, vertically centered.
    final x = laneWidth / 2 + lane * laneWidth;
    final y = size.height / 2;
    canvas.drawCircle(Offset(x, y), 5.5, Paint()..color = lineColor);
    canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LanePainter old) =>
      old.lane != lane ||
      old.color != color ||
      old.lineColor != lineColor ||
      !listEquals(old.activeLanes, activeLanes);
}

// Bottom sheet: commit details + the AI work explanation (auto-fetched, cached
// by the VM and on the backend commit doc).
void _showCommitSheet(
  BuildContext context,
  Commit commit,
  CommitsViewModel vm,
) {
  // Kick off the explanation fetch before the sheet builds.
  vm.explain(commit.sha);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider<CommitsViewModel>.value(
      value: vm,
      child: _CommitDetailSheet(commit: commit),
    ),
  );
}

class _CommitDetailSheet extends StatelessWidget {
  const _CommitDetailSheet({required this.commit});
  final Commit commit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = commit;
    return Consumer<CommitsViewModel>(
      builder: (ctx, vm, _) {
        final explanation = vm.explanationFor(c.sha);
        final explaining = vm.isExplaining(c.sha);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (_, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              AppDimens.spacingMd,
              0,
              AppDimens.spacingMd,
              AppDimens.spacingMd,
            ),
            children: [
              Text(
                c.message.split('\n').first,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppDimens.spacingXs),
              Text(
                '${c.author.name.isEmpty ? c.author.login : c.author.name}'
                ' · ${c.sha.substring(0, 7)}'
                ' · +${c.additions} −${c.deletions}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (c.filesChanged.isNotEmpty) ...[
                const SizedBox(height: AppDimens.spacingSm),
                Wrap(
                  spacing: AppDimens.spacingXs,
                  runSpacing: AppDimens.spacingXs,
                  children: [
                    for (final f in c.filesChanged.take(8))
                      Chip(
                        label: Text(f, style: theme.textTheme.labelSmall),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppDimens.spacingMd),
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppDimens.spacingSm),
                  Text(
                    'AI work summary',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (explanation != null && !explaining)
                    IconButton(
                      tooltip: 'Regenerate',
                      onPressed: () => vm.explain(c.sha, force: true),
                      icon: const Icon(Icons.refresh, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.spacingSm),
              if (explaining)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppDimens.spacingMd),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (explanation != null)
                MarkdownView(data: explanation)
              else if (vm.explainError != null)
                Text(
                  'Could not generate the summary. Please try again.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        );
      },
    );
  }
}

// `YYYY-MM-DD` key for a date (used in the range SnackBar).
String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// `MM/dd` for a date (used in the compact range button label).
String _monthDay(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

// Date-range button label: shows the saved range, the busy state, or a prompt.
String _rangeLabel(DiscordMessagesViewModel vm) {
  if (vm.settingRange) return 'Saving…';
  final start = vm.rangeStart;
  final end = vm.rangeEnd;
  if (start != null && end != null) {
    return '${_monthDay(start)} ~ ${_monthDay(end)}';
  }
  return 'Date range';
}

class _DiscordTab extends StatelessWidget {
  const _DiscordTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<DiscordMessagesViewModel>(
      builder: (ctx, vm, _) {
        if (vm.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        // Show a one-shot "Updated" toast once a refresh round-trip completes.
        if (vm.justUpdated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!ctx.mounted) return;
            vm.acknowledgeUpdated();
            ScaffoldMessenger.of(
              ctx,
            ).showSnackBar(const SnackBar(content: Text('Updated ✓')));
          });
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.spacingMd,
                AppDimens.spacingMd,
                AppDimens.spacingMd,
                AppDimens.spacingSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (vm.digest != null) ...[
                    _DigestCard(digest: vm.digest!, vm: vm),
                    const SizedBox(height: AppDimens.spacingMd),
                  ],
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppDimens.spacingSm,
                    runSpacing: AppDimens.spacingSm,
                    children: [
                      if (vm.lastUpdatedAt != null)
                        Text(
                          'Updated ${_hhmm(vm.lastUpdatedAt!)}',
                          style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: vm.settingRange
                            ? null
                            : () async {
                                final now = DateTime.now();
                                // Default the picker to the user's saved range
                                // so it stays at the position they set.
                                final initial =
                                    (vm.rangeStart != null &&
                                        vm.rangeEnd != null)
                                    ? DateTimeRange(
                                        start: vm.rangeStart!,
                                        end: vm.rangeEnd!,
                                      )
                                    : DateTimeRange(start: now, end: now);
                                final picked = await showDateRangePicker(
                                  context: ctx,
                                  firstDate: DateTime(2020),
                                  lastDate: now,
                                  initialDateRange: initial,
                                );
                                if (picked == null) return;
                                await vm.setRange(picked.start, picked.end);
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Range set to ${_dayKey(picked.start)} ~ '
                                      '${_dayKey(picked.end)}. '
                                      'Tap Refresh to backfill.',
                                    ),
                                  ),
                                );
                              },
                        icon: vm.settingRange
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.date_range_outlined),
                        label: Text(_rangeLabel(vm)),
                      ),
                      FilledButton.icon(
                        onPressed: vm.refreshing ? null : vm.refresh,
                        icon: vm.refreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(vm.refreshing ? 'Fetching…' : 'Refresh'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Expanded(child: _DiscordChat()),
          ],
        );
      },
    );
  }
}

// Collapsible Discord digest card with a lock toggle (frozen when locked) and
// an "ask AI to adjust this summary" field. The header is tappable to
// collapse/expand; the lock button animates; the card border animates to a
// "frozen" tint when locked.
class _DigestCard extends StatefulWidget {
  const _DigestCard({required this.digest, required this.vm});
  final DiscordDigest digest;
  final DiscordMessagesViewModel vm;

  @override
  State<_DigestCard> createState() => _DigestCardState();
}

class _DigestCardState extends State<_DigestCard> {
  bool _expanded = true;
  final _adjustController = TextEditingController();

  @override
  void dispose() {
    _adjustController.dispose();
    super.dispose();
  }

  void _submitAdjust() {
    final text = _adjustController.text;
    if (text.trim().isEmpty || widget.vm.editingDigest) return;
    _adjustController.clear();
    widget.vm.editDigest(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final digest = widget.digest;
    final vm = widget.vm;
    final locked = digest.locked;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: locked ? scheme.primary : scheme.outlineVariant,
          width: locked ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header (tap to collapse/expand) ----
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.spacingMd,
                AppDimens.spacingSm,
                AppDimens.spacingSm,
                AppDimens.spacingSm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppDimens.spacingSm),
                  Text(
                    'Discord digest',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (locked) ...[
                    const SizedBox(width: AppDimens.spacingSm),
                    Icon(Icons.lock, size: 16, color: scheme.primary),
                  ],
                  const Spacer(),
                  // Animated lock toggle.
                  IconButton(
                    tooltip: locked ? 'Unlock digest' : 'Lock digest',
                    onPressed: vm.togglingLock ? null : vm.toggleLock,
                    icon: vm.togglingLock
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (child, anim) => ScaleTransition(
                              scale: anim,
                              child: RotationTransition(
                                turns: anim,
                                child: child,
                              ),
                            ),
                            child: Icon(
                              locked ? Icons.lock : Icons.lock_open,
                              key: ValueKey(locked),
                              color: locked ? scheme.primary : null,
                            ),
                          ),
                  ),
                  // Animated collapse chevron.
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more),
                  ),
                ],
              ),
            ),
          ),
          // ---- Collapsible body ----
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.spacingMd,
                      0,
                      AppDimens.spacingMd,
                      AppDimens.spacingMd,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Long digests can overflow the card; cap the height
                        // and let the markdown scroll within it.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: SingleChildScrollView(
                            child: MarkdownView(data: digest.markdown),
                          ),
                        ),
                        const SizedBox(height: AppDimens.spacingSm),
                        const Divider(height: 1),
                        const SizedBox(height: AppDimens.spacingSm),
                        if (locked)
                          Row(
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 16,
                                color: scheme.outline,
                              ),
                              const SizedBox(width: AppDimens.spacingXs),
                              Expanded(
                                child: Text(
                                  'Locked — unlock to let AI adjust this summary.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.outline,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _adjustController,
                                  minLines: 1,
                                  maxLines: 3,
                                  enabled: !vm.editingDigest,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _submitAdjust(),
                                  decoration: const InputDecoration(
                                    hintText: 'Ask AI to adjust this summary…',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppDimens.spacingSm),
                              IconButton.filledTonal(
                                tooltip: 'Adjust with AI',
                                onPressed: vm.editingDigest
                                    ? null
                                    : _submitAdjust,
                                icon: vm.editingDigest
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.auto_fix_high),
                              ),
                            ],
                          ),
                        if (vm.digestError != null) ...[
                          const SizedBox(height: AppDimens.spacingXs),
                          Text(
                            'Could not update the digest. Please try again.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// AI chat box over the team's Discord messages. The user asks questions; the
// backend `discordChat` callable searches the ingested messages and answers.
// Each AI answer embeds a scrollable panel of the messages it surfaced.
class _DiscordChat extends StatefulWidget {
  const _DiscordChat();

  @override
  State<_DiscordChat> createState() => _DiscordChatState();
}

class _DiscordChatState extends State<_DiscordChat> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send(DiscordChatViewModel vm) {
    final text = _controller.text;
    if (text.trim().isEmpty || vm.sending) return;
    _controller.clear();
    vm.ask(text);
    // Jump to the latest turn once the frame with it is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DiscordChatViewModel>(
      builder: (ctx, vm, _) {
        final turns = vm.turns;
        return Column(
          children: [
            Expanded(
              // Make the empty state scroll-safe: in a small/short window the
              // chat's Expanded can shrink below the EmptyState's natural
              // height, which would overflow a plain Column. LayoutBuilder +
              // SingleChildScrollView keeps it centered when there's room and
              // scrollable when there isn't.
              child: turns.isEmpty
                  ? LayoutBuilder(
                      builder: (ctx, constraints) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: const Center(
                            child: EmptyState(
                              icon: Icons.auto_awesome_outlined,
                              title: 'Ask AI about the chat',
                              message:
                                  'e.g. "OAuth 的進度討論到哪了？" — AI 會找出相關的 Discord 訊息。',
                            ),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(AppDimens.spacingMd),
                      itemCount: turns.length + (vm.sending ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i >= turns.length) return const _ThinkingBubble();
                        return _ChatTurnView(turn: turns[i]);
                      },
                    ),
            ),
            _ChatInputBar(
              controller: _controller,
              sending: vm.sending,
              onSend: () => _send(vm),
            ),
          ],
        );
      },
    );
  }
}

// Two-digit `HH:mm` for a chat-bubble timestamp.
String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

// `MM/dd HH:mm` from a Discord message's ISO 8601 timestamp (shown local). Falls
// back to the raw string if unparseable, or '' when there is none.
String _sourceTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final t = parsed.toLocal();
  return '${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')} '
      '${_hhmm(t)}';
}

class _ChatTurnView extends StatelessWidget {
  const _ChatTurnView({required this.turn});
  final DiscordChatTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (turn.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.spacingMd,
                vertical: AppDimens.spacingSm,
              ),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                turn.content,
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            ),
            if (turn.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Text(
                  _hhmm(turn.createdAt!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Assistant turn: markdown answer + (optional) scrollable sources panel.
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: AppDimens.spacingSm),
              Text(
                'AI',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (turn.createdAt != null) ...[
                const SizedBox(width: AppDimens.spacingSm),
                Text(
                  _hhmm(turn.createdAt!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppDimens.spacingSm),
          MarkdownView(data: turn.content),
          if (turn.snippets.isNotEmpty) ...[
            const SizedBox(height: AppDimens.spacingSm),
            _SourcesPanel(snippets: turn.snippets),
          ],
        ],
      ),
    );
  }
}

// Scrollable panel of the conversation clusters the AI surfaced for an answer
// — the "relevant chat content in the middle that the user can scroll" (D4).
// Each snippet is one cluster: chronological messages with the matched line(s)
// emphasized and surrounding context dimmed; clusters are split by a divider.
class _SourcesPanel extends StatelessWidget {
  const _SourcesPanel({required this.snippets});
  final List<DiscordChatSnippet> snippets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.spacingMd,
              AppDimens.spacingSm,
              AppDimens.spacingMd,
              AppDimens.spacingXs,
            ),
            child: Row(
              children: [
                Icon(Icons.forum_outlined, size: 16, color: scheme.secondary),
                const SizedBox(width: AppDimens.spacingXs),
                Text(
                  'Related conversations (${snippets.length})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.spacingMd,
                0,
                AppDimens.spacingMd,
                AppDimens.spacingSm,
              ),
              shrinkWrap: true,
              itemCount: snippets.length,
              // Visible divider so distinct conversations read as separate
              // clusters.
              separatorBuilder: (_, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
                child: Divider(height: 1),
              ),
              itemBuilder: (_, i) => _SnippetBlock(snippet: snippets[i]),
            ),
          ),
        ],
      ),
    );
  }
}

// One conversation cluster: its messages in chronological order. Matched
// messages are emphasized (subtle highlight + leading marker); context
// messages are dimmed.
class _SnippetBlock extends StatelessWidget {
  const _SnippetBlock({required this.snippet});
  final DiscordChatSnippet snippet;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < snippet.messages.length; i++) ...[
          if (i > 0) const SizedBox(height: AppDimens.spacingXs),
          _SnippetMessage(source: snippet.messages[i]),
        ],
      ],
    );
  }
}

class _SnippetMessage extends StatelessWidget {
  const _SnippetMessage({required this.source});
  final DiscordChatSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = source;
    final time = _sourceTime(s.timestamp);
    // Matched line: full-strength text with a highlight; context: dimmed.
    final authorColor = s.isMatch ? scheme.primary : scheme.onSurfaceVariant;
    final contentStyle = theme.textTheme.bodySmall?.copyWith(
      color: s.isMatch ? scheme.onSurface : scheme.onSurfaceVariant,
    );

    final row = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (s.isMatch) ...[
              Icon(Icons.arrow_right, size: 14, color: scheme.primary),
              const SizedBox(width: 2),
            ],
            Flexible(
              child: Text(
                s.authorName.isEmpty ? 'Unknown' : s.authorName,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: s.isMatch ? FontWeight.w700 : FontWeight.w600,
                  color: authorColor,
                ),
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(width: AppDimens.spacingSm),
              Text(
                time,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        Text(s.content, style: contentStyle),
      ],
    );

    if (!s.isMatch) return row;
    // Subtle highlighted background for the matched message(s).
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingXs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
      ),
      child: row,
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.spacingMd),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppDimens.spacingSm),
          Text('Thinking…', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.spacingMd,
          AppDimens.spacingSm,
          AppDimens.spacingMd,
          AppDimens.spacingMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                enabled: !sending,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Ask AI about the Discord chat…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppDimens.spacingSm),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
