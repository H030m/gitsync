import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../view_models/commits_vm.dart';
import '../../view_models/daily_report_vm.dart';
import '../../view_models/discord_messages_vm.dart';

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
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(report?.summary ?? 'No report yet'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: vm.regenerating ? null : vm.regenerate,
                icon: const Icon(Icons.refresh),
                label: Text(vm.regenerating ? 'Generating…' : 'Regenerate'),
              ),
            ],
          ),
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
          return const Center(child: Text('No commits yet'));
        }
        return ListView.builder(
          itemCount: vm.commits.length,
          itemBuilder: (_, i) {
            final c = vm.commits[i];
            return ListTile(
              title: Text(
                c.message.split('\n').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${c.author.login} · ${c.sha.substring(0, 7)}'),
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
        if (vm.messages.isEmpty) {
          return const Center(child: Text('No Discord messages yet'));
        }
        return ListView.builder(
          itemCount: vm.messages.length,
          itemBuilder: (_, i) {
            final m = vm.messages[i];
            return ListTile(
              title: Text(m.authorName),
              subtitle: Text(m.content),
            );
          },
        );
      },
    );
  }
}
