import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          children: [
            _SummaryTab(),
            _CommitsTab(),
            _DiscordTab(),
          ],
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
                Icon(Icons.auto_awesome_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: AppDimens.spacingSm),
                Text('Daily summary',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
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
                  : 'No report generated for today yet. Tap Regenerate to let '
                      'the AI summarize the day’s commits, tasks and chat.',
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
                  Icon(Icons.merge_type_outlined,
                      size: 20, color: scheme.tertiary),
                  const SizedBox(width: AppDimens.spacingSm),
                  Text('Commit rollup',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
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
                            Text(t.theme,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600)),
                            if (t.summary.isNotEmpty)
                              Text(t.summary,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant)),
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
                  Icon(Icons.groups_outlined, size: 20, color: scheme.secondary),
                  const SizedBox(width: AppDimens.spacingSm),
                  Text('Contributions',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
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
                              _initial(e.key),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppDimens.spacingXs),
                          Text(
                            '${e.key}  ·  ${e.value.tasksDone}✓ '
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
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.icon, required this.color, required this.text});
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
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
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
        Text('Ask AI about today',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
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
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
            top: AppDimens.spacingMd, bottom: AppDimens.spacingXs),
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
            child: Text(turn.content,
                style: TextStyle(color: scheme.onPrimaryContainer)),
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
              Icon(Icons.auto_awesome_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: AppDimens.spacingSm),
              Text('AI',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
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
                Text('Source commits (${sources.length})',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
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
                    Text(s.message,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (s.aiSummary != null && s.aiSummary!.isNotEmpty)
                      Text(s.aiSummary!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    Text(
                      '${s.authorName.isEmpty ? s.authorLogin : s.authorName}'
                      ' · ${s.shortSha}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
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

class _CommitsTab extends StatelessWidget {
  const _CommitsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<CommitsViewModel>(
      builder: (ctx, vm, _) {
        if (vm.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.commits.isEmpty) {
          return const EmptyState(
            icon: Icons.commit_outlined,
            title: 'No commits yet',
            message: 'Recent commits on this repo will show up here.',
          );
        }
        final scheme = Theme.of(ctx).colorScheme;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
          itemCount: vm.commits.length,
          itemBuilder: (_, i) {
            final c = vm.commits[i];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.tertiaryContainer,
                  foregroundColor: scheme.onTertiaryContainer,
                  child: const Icon(Icons.commit_outlined, size: 20),
                ),
                title: Text(
                  c.message.split('\n').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${c.author.login} · ${c.sha.substring(0, 7)}'),
              ),
            );
          },
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
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Updated ✓')),
            );
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
                                color:
                                    Theme.of(ctx).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      OutlinedButton.icon(
                        onPressed: vm.settingRange
                            ? null
                            : () async {
                                final now = DateTime.now();
                                // Default the picker to the user's saved range
                                // so it stays at the position they set.
                                final initial = (vm.rangeStart != null &&
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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
                  Icon(Icons.auto_awesome_outlined,
                      size: 20, color: scheme.primary),
                  const SizedBox(width: AppDimens.spacingSm),
                  Text('Discord digest',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
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
                                  turns: anim, child: child),
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
                              Icon(Icons.lock_outline,
                                  size: 16, color: scheme.outline),
                              const SizedBox(width: AppDimens.spacingXs),
                              Expanded(
                                child: Text(
                                  'Locked — unlock to let AI adjust this summary.',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: scheme.outline),
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
                                    hintText:
                                        'Ask AI to adjust this summary…',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppDimens.spacingSm),
                              IconButton.filledTonal(
                                tooltip: 'Adjust with AI',
                                onPressed:
                                    vm.editingDigest ? null : _submitAdjust,
                                icon: vm.editingDigest
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.auto_fix_high),
                              ),
                            ],
                          ),
                        if (vm.digestError != null) ...[
                          const SizedBox(height: AppDimens.spacingXs),
                          Text(
                            'Could not update the digest. Please try again.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.error),
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
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
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
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
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
              Icon(Icons.auto_awesome_outlined,
                  size: 18, color: scheme.primary),
              const SizedBox(width: AppDimens.spacingSm),
              Text('AI',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              if (turn.createdAt != null) ...[
                const SizedBox(width: AppDimens.spacingSm),
                Text(
                  _hhmm(turn.createdAt!),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
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
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
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
                padding:
                    EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
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
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
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
