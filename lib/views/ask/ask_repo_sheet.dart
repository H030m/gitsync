import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../models/agent_run.dart';
import '../../models/ask_repo.dart';
import '../../models/daily_brief.dart';
import '../../models/discord_chat.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/ask_repo_vm.dart';
import '../../widgets/markdown_view.dart';

/// The global "Ask GitSync" chat — a draggable modal bottom sheet opened from
/// the repo-shell FAB on any tab. Renders the transcript (user bubbles + AI
/// markdown answers with commit + Discord source panels) and, while a question
/// is in flight, a live trace strip fed by the agent tool-trace stream.
///
/// Reads the [AskRepoViewModel] provided at the ShellRoute scope, so the FAB and
/// the sheet share one transcript across tabs.
class AskRepoSheet extends StatelessWidget {
  const AskRepoSheet({super.key});

  /// Opens the sheet as a draggable, full-height-capable modal. The caller must
  /// pass the ShellRoute's [AskRepoViewModel] so the sheet (a separate route
  /// subtree) can read it.
  static Future<void> show(BuildContext context, AskRepoViewModel vm) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: vm,
        child: const AskRepoSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => _AskRepoBody(
        scrollController: scrollController,
      ),
    );
  }
}

class _AskRepoBody extends StatefulWidget {
  const _AskRepoBody({required this.scrollController});
  final ScrollController scrollController;

  @override
  State<_AskRepoBody> createState() => _AskRepoBodyState();
}

class _AskRepoBodyState extends State<_AskRepoBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send(AskRepoViewModel vm) {
    final text = _controller.text;
    if (text.trim().isEmpty || vm.sending) return;
    _controller.clear();
    vm.ask(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients) return;
      widget.scrollController.animateTo(
        widget.scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AskRepoViewModel>(
      builder: (ctx, vm, _) {
        return Column(
          children: [
            _SheetHeader(
              onNewSession: vm.sending ? null : vm.newSession,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.all(AppDimens.spacingMd),
                children: [
                  if (vm.turns.isEmpty) const _EmptyHint(),
                  for (final turn in vm.turns) _AskTurnView(turn: turn),
                  if (vm.sending) _LiveTraceStrip(steps: vm.liveSteps),
                ],
              ),
            ),
            _InputBar(
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

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.onNewSession});
  final VoidCallback? onNewSession;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.spacingMd,
        AppDimens.spacingMd,
        AppDimens.spacingSm,
        AppDimens.spacingSm,
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 22, color: scheme.primary),
          const SizedBox(width: AppDimens.spacingSm),
          Text(
            s.askRepoTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: s.askRepoNewSession,
            onPressed: onNewSession,
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: s.cancel,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppDimens.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        s.askRepoEmptyHint,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// One turn: a right-aligned user bubble, or an AI markdown answer with optional
// commit + Discord source panels (mirrors the Summary tab's _BriefTurnView).
class _AskTurnView extends StatelessWidget {
  const _AskTurnView({required this.turn});
  final AskRepoTurn turn;

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
              Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
              const SizedBox(width: AppDimens.spacingSm),
              Text(
                'GitSync',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.spacingSm),
          MarkdownView(data: turn.content),
          if (turn.commitSources.isNotEmpty) ...[
            const SizedBox(height: AppDimens.spacingSm),
            _CommitSourcesPanel(sources: turn.commitSources),
          ],
          if (turn.discordSources.isNotEmpty) ...[
            const SizedBox(height: AppDimens.spacingSm),
            _DiscordSourcesPanel(snippets: turn.discordSources),
          ],
        ],
      ),
    );
  }
}

// Scrollable panel of the commits the AI cited (mirrors _BriefSourcesPanel).
class _CommitSourcesPanel extends StatelessWidget {
  const _CommitSourcesPanel({required this.sources});
  final List<DailyBriefSource> sources;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
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
                  s.askRepoCommitSources(sources.length),
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
                final src = sources[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      src.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (src.aiSummary != null && src.aiSummary!.isNotEmpty)
                      Text(
                        src.aiSummary!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      '${src.authorName.isEmpty ? src.authorLogin : src.authorName}'
                      ' · ${src.shortSha}',
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

// Scrollable panel of the Discord conversation clusters the AI cited.
class _DiscordSourcesPanel extends StatelessWidget {
  const _DiscordSourcesPanel({required this.snippets});
  final List<DiscordChatSnippet> snippets;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
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
                  s.askRepoDiscordSources(snippets.length),
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
              separatorBuilder: (_, _) => const Divider(height: 16),
              itemBuilder: (_, i) {
                final snippet = snippets[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final m in snippet.messages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: RichText(
                          text: TextSpan(
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: m.isMatch
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                              fontWeight:
                                  m.isMatch ? FontWeight.w600 : FontWeight.w400,
                            ),
                            children: [
                              TextSpan(
                                text: '${m.authorName}: ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(text: m.content),
                            ],
                          ),
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

// While a question is in flight, the live agent trace: each streamed step on its
// own line, the latest carrying a spinner.
class _LiveTraceStrip extends StatelessWidget {
  const _LiveTraceStrip({required this.steps});
  final List<AgentStep> steps;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labels = steps.map((e) => e.label).toList();
    // Until the first step arrives, show a generic "thinking" line.
    final lines = labels.isEmpty ? [s.askRepoThinking] : labels;
    return Padding(
      padding: const EdgeInsets.only(
        top: AppDimens.spacingSm,
        bottom: AppDimens.spacingMd,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppDimens.spacingMd),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    if (i == lines.length - 1)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      )
                    else
                      Icon(
                        Icons.check_circle_outline,
                        size: 14,
                        color: scheme.primary,
                      ),
                    const SizedBox(width: AppDimens.spacingSm),
                    Expanded(
                      child: Text(
                        lines[i],
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: i == lines.length - 1
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Pinned input bar (mirrors the per-tab chat bars).
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      color: scheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppDimens.spacingMd,
          AppDimens.spacingSm,
          AppDimens.spacingMd,
          AppDimens.spacingMd + MediaQuery.of(context).viewInsets.bottom,
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
                decoration: InputDecoration(
                  hintText: s.askRepoHint,
                  border: const OutlineInputBorder(),
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
