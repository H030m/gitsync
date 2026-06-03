import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_dimens.dart';
import '../../view_models/commits_vm.dart';
import '../../view_models/stats_vm.dart';
import '../../view_models/tasks_board_vm.dart';

/// StatsViewPage — two tabs: 貢獻度 (contribution) and 進度表 (progress).
class StatsViewPage extends StatelessWidget {
  const StatsViewPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProxyProvider2<TasksBoardViewModel, CommitsViewModel,
        StatsViewModel>(
      create: (_) => StatsViewModel(),
      update: (_, tasks, commits, prev) =>
          (prev ?? StatsViewModel())..updateFromUpstream(tasks: tasks, commits: commits),
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('統計'),
            centerTitle: true,
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

Color _cardBg(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF222630)
      : Theme.of(context).colorScheme.surface;
}

// ---------------------------------------------------------------------------
// Tab 1: 貢獻度
// ---------------------------------------------------------------------------
class _ContributionTab extends StatelessWidget {
  const _ContributionTab({required this.vm});
  final StatsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authorMax = vm.commitsPerAuthor.values.fold<int>(0, _max);
    final entries = vm.commitsPerAuthor.entries.toList();

    return ListView(
      padding: const EdgeInsets.all(AppDimens.spacingMd),
      children: [
        Container(
          padding: const EdgeInsets.all(AppDimens.spacingMd),
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : const Color(0xFF1565C0).withValues(alpha: 0.10),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                _ContribRow(
                  name: entries[i].key,
                  value: entries[i].value,
                  max: authorMax,
                  color: _personColor(entries[i].key, isDark),
                  isEdge: i == 0 || i == entries.length - 1,
                ),
                if (i < entries.length - 1)
                  const SizedBox(height: AppDimens.spacingMd),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppDimens.spacingSm),
        // Description
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.spacingMd,
            vertical: AppDimens.spacingSm + 4,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.3)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            '已完成的任務累計的貢獻度',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  static int _max(int a, int b) => a > b ? a : b;
}

class _ContribRow extends StatelessWidget {
  const _ContribRow({
    required this.name,
    required this.value,
    required this.max,
    required this.color,
    required this.isEdge,
  });

  final String name;
  final int value;
  final int max;
  final Color color;
  final bool isEdge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = max == 0 ? 0.0 : value / max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                color: isEdge ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 12,
                color: scheme.primary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: 進度表
// ---------------------------------------------------------------------------
class _ProgressTab extends StatefulWidget {
  const _ProgressTab({required this.vm});
  final StatsViewModel vm;

  @override
  State<_ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<_ProgressTab> {
  final _expanded = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = widget.vm.commitsPerAuthor.entries.toList();

    return ListView(
      padding: const EdgeInsets.all(AppDimens.spacingMd),
      children: [
        Container(
          padding: const EdgeInsets.all(AppDimens.spacingMd),
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : const Color(0xFF1565C0).withValues(alpha: 0.10),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                _ProgressSection(
                  name: entries[i].key,
                  value: entries[i].value,
                  color: _personColor(entries[i].key, isDark),
                  isEdge: i == 0 || i == entries.length - 1,
                  isExpanded: _expanded[entries[i].key] ?? false,
                  onToggle: () => setState(() {
                    _expanded[entries[i].key] =
                        !(_expanded[entries[i].key] ?? false);
                  }),
                ),
                if (i < entries.length - 1)
                  const SizedBox(height: AppDimens.spacingMd),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppDimens.spacingSm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.spacingMd,
            vertical: AppDimens.spacingSm + 4,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.3)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            '每個人當前未完成任務的進度',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({
    required this.name,
    required this.value,
    required this.color,
    required this.isEdge,
    required this.isExpanded,
    required this.onToggle,
  });

  final String name;
  final int value;
  final Color color;
  final bool isEdge;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Mock percentage from value (capped at 100)
    final pct = (value * 15).clamp(0, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                color: isEdge ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: 12,
                color: scheme.primary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onToggle,
          child: Row(
            children: [
              Icon(
                isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '詳細情形',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------
Color _personColor(String name, bool isDark) {
  final lower = name.toLowerCase();
  if (lower.contains('alice')) {
    return isDark ? const Color(0xFFFAB28E) : const Color(0xFF1565C0);
  }
  if (lower.contains('bob')) {
    return isDark ? const Color(0xFF42A5F5) : const Color(0xFF5B9BD5);
  }
  if (lower.contains('charlie')) {
    return isDark ? const Color(0xFF26C6DA) : const Color(0xFF90CAF9);
  }
  // Fallback: use primary-ish color
  return isDark ? const Color(0xFFFAB28E) : const Color(0xFF1565C0);
}
