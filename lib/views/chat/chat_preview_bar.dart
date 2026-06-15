import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_dimens.dart';

/// A compact preview bar pinned to the bottom of a tab, showing a one-line
/// hint or the last AI answer, plus a fake input field that opens the
/// full-screen chat when tapped.
///
/// Used in Summary tab (Ask GitSync) and Discord tab (Discord Chat) so the
/// chat doesn't compete with the report/digest panel for vertical space.
class ChatPreviewBar extends StatelessWidget {
  const ChatPreviewBar({
    super.key,
    required this.title,
    required this.onTap,
    this.lastMessage,
    this.sending = false,
  });

  /// Section label (e.g. "Ask GitSync").
  final String title;

  /// Called when the user taps the bar — should push [ChatFullScreen].
  final VoidCallback onTap;

  /// The last assistant message (shown as a one-line preview). Null = empty hint.
  final String? lastMessage;

  /// Whether a question is currently in flight.
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Material(
        elevation: 4,
        color: scheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.spacingMd,
            AppDimens.spacingSm,
            AppDimens.spacingMd,
            AppDimens.spacingMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
                  const SizedBox(width: AppDimens.spacingSm),
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.open_in_full,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.spacingSm),
              // Preview or hint
              if (lastMessage != null && lastMessage!.isNotEmpty)
                Text(
                  lastMessage!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: AppDimens.spacingSm),
              // Fake input field
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.spacingMd,
                  vertical: AppDimens.spacingSm + 2,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outline),
                  borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        sending ? s.askRepoThinking : s.askRepoHint,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (sending)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      )
                    else
                      Icon(Icons.send, size: 18, color: scheme.primary),
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
