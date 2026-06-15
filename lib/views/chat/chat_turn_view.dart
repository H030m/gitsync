import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/ask_repo.dart';
import '../../models/discord_chat.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/markdown_view.dart';

/// `yyyy/MM/dd HH:mm` in local time for a source timestamp (commit time /
/// Discord message time). Empty string when [dt] is null. Shared by the commit
/// and Discord source panels so every cited source reads the same way.
String formatStamp(DateTime? dt) {
  if (dt == null) return '';
  final d = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// One turn: a right-aligned user bubble, or an AI markdown answer with optional
/// commit + Discord source panels.
class AskRepoTurnView extends StatelessWidget {
  const AskRepoTurnView({super.key, required this.turn});
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
          for (final group in turn.commitGroups) ...[
            const SizedBox(height: AppDimens.spacingSm),
            CommitSourcesPanel(group: group),
          ],
          if (turn.discordSources.isNotEmpty) ...[
            const SizedBox(height: AppDimens.spacingSm),
            DiscordSourcesPanel(snippets: turn.discordSources),
          ],
        ],
      ),
    );
  }
}

/// Backward-compatible alias.
typedef ChatTurnView = AskRepoTurnView;

/// Scrollable panel of one commit window the AI cited. The header is the
/// window's label (a person / task / search); an unlabeled window falls back to
/// the localized "source commits" header. Each card shows the commit time to the
/// hour.
class CommitSourcesPanel extends StatelessWidget {
  const CommitSourcesPanel({super.key, required this.group});
  final AskRepoCommitGroup group;

  /// `yyyy/MM/dd HH:mm` in local time. Empty when absent.
  static String stamp(DateTime? dt) => formatStamp(dt);

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sources = group.commits;
    final header = group.label.isNotEmpty
        ? group.label
        : s.askRepoCommitSources(sources.length);
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
                Expanded(
                  child: Text(
                    header,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
                final ts = stamp(src.committedAt);
                final meta = [
                  src.authorName.isEmpty ? src.authorLogin : src.authorName,
                  if (ts.isNotEmpty) ts,
                  src.shortSha,
                ].join(' · ');
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
                      meta,
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

/// Scrollable panel of the Discord conversation clusters the AI cited.
class DiscordSourcesPanel extends StatelessWidget {
  const DiscordSourcesPanel({super.key, required this.snippets});
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
                              if (formatStamp(
                                      DateTime.tryParse(m.timestamp ?? ''))
                                  .isNotEmpty)
                                TextSpan(
                                  text:
                                      '${formatStamp(DateTime.tryParse(m.timestamp!))}  ',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
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
