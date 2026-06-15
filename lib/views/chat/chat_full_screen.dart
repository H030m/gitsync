import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/agent_run.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';
import 'chat_input_bar.dart';
import 'chat_live_trace.dart';

/// A generic full-screen chat page used by both Ask GitSync and Discord Chat.
///
/// Displays a scrollable list of conversation turns, a live trace strip while
/// the AI is working, and a pinned input bar at the bottom. The caller provides
/// turn widgets via [turnWidgets] and the live-trace data via [liveSteps].
///
/// Pushed as a full-page route from the Summary/Discord tab when the user taps
/// the chat preview bar, and popped via the back button in the AppBar.
class ChatFullScreen extends StatefulWidget {
  const ChatFullScreen({
    super.key,
    required this.title,
    required this.turnWidgets,
    required this.emptyHint,
    required this.sending,
    required this.liveSteps,
    required this.controller,
    required this.onSend,
    this.onNewSession,
  });

  /// Title shown in the AppBar (e.g. "Ask GitSync" or "Discord Chat").
  final String title;

  /// Pre-built turn widgets (the caller maps its turns to widgets).
  final List<Widget> turnWidgets;

  /// Widget shown when there are no turns yet.
  final Widget emptyHint;

  /// Whether a question is currently in flight.
  final bool sending;

  /// Live agent trace steps (streamed while callable is running).
  final List<AgentStep> liveSteps;

  /// Text controller for the input bar (shared with the parent so text is
  /// preserved across push/pop).
  final TextEditingController controller;

  /// Called when the user presses send.
  final VoidCallback onSend;

  /// Called when the user presses "new session". Null hides the button.
  final VoidCallback? onNewSession;

  @override
  State<ChatFullScreen> createState() => _ChatFullScreenState();
}

class _ChatFullScreenState extends State<ChatFullScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: AppMotion.medium,
        curve: AppMotion.emphasizedDecel,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final hasTurns = widget.turnWidgets.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.onNewSession != null)
            IconButton(
              tooltip: s.askRepoNewSession,
              onPressed: widget.sending ? null : widget.onNewSession,
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppDimens.spacingMd),
              children: [
                if (!hasTurns) widget.emptyHint,
                ...widget.turnWidgets,
                if (widget.sending)
                  ChatLiveTrace(steps: widget.liveSteps),
              ],
            ),
          ),
          ChatInputBar(
            controller: widget.controller,
            sending: widget.sending,
            onSend: () {
              widget.onSend();
              _scrollToBottom();
            },
          ),
        ],
      ),
    );
  }
}
