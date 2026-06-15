import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_dimens.dart';

/// Pinned input bar for the Ask GitSync chat. [onNewSession] is optional: when
/// non-null a leading "new session" button is shown (used by the Summary tab,
/// whose new-session control lives in the bar rather than a header); the sheet
/// keeps its new-session button in the header and passes null. [bottomInset]
/// adds extra bottom padding (the sheet lifts the bar above the keyboard).
///
/// When [onTap] is provided the text field becomes read-only and tapping
/// anywhere on it invokes [onTap] instead of opening the keyboard. This is
/// used for preview bars that navigate to a full-screen chat.
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.onNewSession,
    this.onTap,
    this.bottomInset = 0,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback? onNewSession;
  final VoidCallback? onTap;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    final textField = TextField(
      controller: controller,
      minLines: 1,
      maxLines: 4,
      textInputAction: TextInputAction.send,
      enabled: !sending && onTap == null,
      readOnly: onTap != null,
      onSubmitted: (_) => onSend(),
      decoration: InputDecoration(
        hintText: s.askRepoHint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );

    return Material(
      elevation: 2,
      color: scheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppDimens.spacingMd,
          AppDimens.spacingSm,
          AppDimens.spacingMd,
          AppDimens.spacingMd + bottomInset,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (onNewSession != null) ...[
              IconButton(
                tooltip: s.askRepoNewSession,
                onPressed: sending ? null : onNewSession,
                icon: const Icon(Icons.restart_alt),
              ),
            ],
            Expanded(
              child: onTap != null
                  ? GestureDetector(
                      onTap: onTap,
                      behavior: HitTestBehavior.opaque,
                      child: AbsorbPointer(child: textField),
                    )
                  : textField,
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

/// Backward-compatible alias.
typedef AskRepoInputBar = ChatInputBar;
