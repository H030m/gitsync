import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_dimens.dart';
import '../../view_models/commits_vm.dart';
import '../../view_models/daily_report_vm.dart';
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

class _SummaryTab extends StatelessWidget {
  const _SummaryTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<DailyReportViewModel>(
      builder: (ctx, vm, _) {
        if (vm.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final report = vm.report;
        final theme = Theme.of(ctx);
        return ListView(
          padding: const EdgeInsets.all(AppDimens.spacingMd),
          children: [
            Card(
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
                      ],
                    ),
                    const SizedBox(height: AppDimens.spacingSm),
                    Text(
                      report?.summary ?? 'No report yet',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimens.spacingMd),
            FilledButton.icon(
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
          ],
        );
      },
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

class _DiscordTab extends StatelessWidget {
  const _DiscordTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<DiscordMessagesViewModel>(
      builder: (ctx, vm, _) {
        if (vm.loading) {
          return const Center(child: CircularProgressIndicator());
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
                    _DigestCard(markdown: vm.digest!.markdown),
                    const SizedBox(height: AppDimens.spacingMd),
                  ],
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppDimens.spacingSm,
                    runSpacing: AppDimens.spacingSm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: vm.settingStartDate
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: now,
                                  firstDate: DateTime(2020),
                                  lastDate: now,
                                );
                                if (picked == null) return;
                                await vm.setStartDate(picked);
                                if (!ctx.mounted) return;
                                final key =
                                    '${picked.year.toString().padLeft(4, '0')}-'
                                    '${picked.month.toString().padLeft(2, '0')}-'
                                    '${picked.day.toString().padLeft(2, '0')}';
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Start date set to $key. Tap Refresh to backfill.',
                                    ),
                                  ),
                                );
                              },
                        icon: vm.settingStartDate
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.event_outlined),
                        label: Text(
                          vm.settingStartDate ? 'Saving…' : 'Start date',
                        ),
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
            Expanded(child: _MessageList(vm: vm)),
          ],
        );
      },
    );
  }
}

class _DigestCard extends StatelessWidget {
  const _DigestCard({required this.markdown});
  final String markdown;

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
                Icon(Icons.auto_awesome_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: AppDimens.spacingSm),
                Text('Discord digest',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: AppDimens.spacingSm),
            MarkdownView(data: markdown),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.vm});
  final DiscordMessagesViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (vm.messages.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: 'No Discord messages yet',
        message: 'Tap Refresh to pull the day\'s chat from Discord.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
      itemCount: vm.messages.length,
      itemBuilder: (_, i) {
        final m = vm.messages[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              child: Text(
                m.authorName.isEmpty
                    ? '?'
                    : m.authorName.substring(0, 1).toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(
              m.authorName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(m.content),
          ),
        );
      },
    );
  }
}
