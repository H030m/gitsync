import 'package:flutter/foundation.dart';

import '../models/discord_chat.dart';
import '../services/functions_service.dart';

/// Drives the Discord AI chat box: holds the conversation transcript and calls
/// the `discordChat` callable. Each assistant turn carries the messages the AI
/// surfaced, which the UI renders in a scrollable sources panel.
class DiscordChatViewModel with ChangeNotifier {
  DiscordChatViewModel({
    required String repoId,
    FunctionsService? functionsService,
  })  : _repoId = repoId,
        _functions = functionsService ?? FunctionsService();

  final String _repoId;
  final FunctionsService _functions;

  final List<DiscordChatTurn> _turns = [];
  List<DiscordChatTurn> get turns => List.unmodifiable(_turns);

  bool _sending = false;
  bool get sending => _sending;

  String? _error;
  String? get error => _error;

  /// Sends [question] to the AI. Appends a user turn immediately, then an
  /// assistant turn once the callable returns. No-ops on empty input or while a
  /// previous question is still in flight.
  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _sending) return;

    // Snapshot history (oldest first) BEFORE adding the new user turn.
    final history = List<DiscordChatTurn>.from(_turns);

    _turns.add(DiscordChatTurn(
      role: 'user',
      content: trimmed,
      createdAt: DateTime.now(),
    ));
    _sending = true;
    _error = null;
    notifyListeners();

    try {
      final reply = await _functions.discordChat(
        repoId: _repoId,
        question: trimmed,
        history: history,
      );
      _turns.add(DiscordChatTurn(
        role: 'assistant',
        content: reply.answer,
        snippets: reply.snippets,
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      _error = '$e';
      _turns.add(DiscordChatTurn(
        role: 'assistant',
        content: '抱歉，我這次沒辦法回答，請稍後再試。',
        createdAt: DateTime.now(),
      ));
    } finally {
      _sending = false;
      notifyListeners();
    }
  }
}
