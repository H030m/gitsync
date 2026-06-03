import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/discord_chat.dart';
import '../../models/discord_digest.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/commits_vm.dart';
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
                    _DigestCard(digest: vm.digest!, vm: vm),
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
                        MarkdownView(data: digest.markdown),
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
          if (turn.sources.isNotEmpty) ...[
            const SizedBox(height: AppDimens.spacingSm),
            _SourcesPanel(sources: turn.sources),
          ],
        ],
      ),
    );
  }
}

// Scrollable panel of the Discord messages the AI surfaced for an answer —
// the "relevant chat content in the middle that the user can scroll" (D4).
class _SourcesPanel extends StatelessWidget {
  const _SourcesPanel({required this.sources});
  final List<DiscordChatSource> sources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
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
                  'Related messages (${sources.length})',
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
              itemCount: sources.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppDimens.spacingSm),
              itemBuilder: (_, i) {
                final s = sources[i];
                final time = _sourceTime(s.timestamp);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            s.authorName.isEmpty ? 'Unknown' : s.authorName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
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
                    Text(s.content, style: theme.textTheme.bodySmall),
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
