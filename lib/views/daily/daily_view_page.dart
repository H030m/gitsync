import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_dimens.dart';
import '../../view_models/commits_vm.dart';
import '../../view_models/daily_report_vm.dart';
import '../../view_models/discord_messages_vm.dart';
import '../../widgets/empty_state.dart';

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
          title: const Text('每日彙整'),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: '日報'),
              Tab(text: 'commit'),
              Tab(text: 'DC群組'),
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
        final scheme = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final cardBg = isDark
            ? const Color(0xFF222630)
            : scheme.surface;
        return ListView(
          padding: const EdgeInsets.all(AppDimens.spacingMd),
          children: [
            Container(
              padding: const EdgeInsets.all(AppDimens.spacingMd),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.3)
                        : const Color(0xFF1565C0).withValues(alpha: 0.14),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '日報',
                    style: TextStyle(fontSize: 14, color: scheme.primary),
                  ),
                  const SizedBox(height: AppDimens.spacingSm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Text(
                      report?.summary ?? '尚無日報',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
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
              label: Text(vm.regenerating ? '生成中…' : '重新生成'),
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
            title: '尚無 commit',
            message: '此 Repo 的近期 commit 將會顯示於此。',
          );
        }
        final scheme = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF222630) : scheme.surface;
        return ListView.builder(
          padding: const EdgeInsets.all(AppDimens.spacingMd),
          itemCount: vm.commits.length,
          itemBuilder: (_, i) {
            final c = vm.commits[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppDimens.spacingSm),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.2)
                          : const Color(0xFF1565C0).withValues(alpha: 0.09),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kvRow('commit:', c.sha.substring(0, 7), scheme),
                    _kvRow('author:', c.author.login, scheme),
                    _kvRow('message:', c.message.split('\n').first, scheme),
                  ],
                ),
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: vm.refreshing ? null : vm.refresh,
                      icon: vm.refreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(vm.refreshing ? '擷取中…' : '重新整理'),
                    ),
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
                Text('Discord 摘要',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: AppDimens.spacingSm),
            Text(markdown, style: theme.textTheme.bodyMedium),
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
        title: '尚無 DC 訊息',
        message: '已匯入的 Discord 訊息將會顯示於此。',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF222630) : scheme.surface;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
      itemCount: vm.messages.length,
      itemBuilder: (_, i) {
        final m = vm.messages[i];
        final isEdge = i == 0 || i == vm.messages.length - 1;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppDimens.spacingSm),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: isEdge ? 0.3 : 0.2)
                      : const Color(0xFF1565C0).withValues(alpha: isEdge ? 0.14 : 0.09),
                  blurRadius: isEdge ? 8 : 3,
                  offset: Offset(0, isEdge ? 2 : 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.authorName,
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    m.content,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurface,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


Widget _kvRow(String label, String value, ColorScheme scheme) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: scheme.onSurface, height: 1.4),
          ),
        ),
      ],
    ),
  );
}
