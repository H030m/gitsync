import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/agent_run.dart';
import '../../theme/app_dimens.dart';

/// While a question is in flight, the live agent trace: each streamed step on
/// its own line, the latest carrying a spinner.
class ChatLiveTrace extends StatelessWidget {
  const ChatLiveTrace({super.key, required this.steps});
  final List<AgentStep> steps;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Localize each backend step label to a descriptive, app-language line.
    final labels = steps.map((e) => s.traceStep(e.label)).toList();
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

/// Backward-compatible alias.
typedef AskRepoLiveTraceStrip = ChatLiveTrace;
