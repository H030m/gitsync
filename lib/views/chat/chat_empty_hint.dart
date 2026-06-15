import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_dimens.dart';

/// Empty-state hint shown before the first question.
class ChatEmptyHint extends StatelessWidget {
  const ChatEmptyHint({super.key});

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

/// Backward-compatible alias.
typedef AskRepoEmptyHint = ChatEmptyHint;
