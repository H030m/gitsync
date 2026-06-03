import 'package:flutter/foundation.dart';

import '../models/daily_brief.dart';
import '../services/functions_service.dart';

/// Drives the Summary tab's "ask AI about today" chat: holds the transcript and
/// calls the `dailyBrief` callable (an agentic loop over the day's commits /
/// tasks / Discord digest). Each assistant turn carries the commits the AI
/// surfaced, rendered as sources under the answer. Mirrors
/// [DiscordChatViewModel] but is scoped to a single report date.
class DailyBriefChatViewModel with ChangeNotifier {
  DailyBriefChatViewModel({
    required String repoId,
    DateTime? date,
    FunctionsService? functionsService,
  })  : _repoId = repoId,
        _date = date ?? DateTime.now(),
        _functions = functionsService ?? FunctionsService();

  final String _repoId;
  final DateTime _date;
  final FunctionsService _functions;

  final List<DailyBriefTurn> _turns = [];
  List<DailyBriefTurn> get turns => List.unmodifiable(_turns);

  bool _sending = false;
  bool get sending => _sending;

  String? _error;
  String? get error => _error;

  String get _dateKey =>
      '${_date.year.toString().padLeft(4, '0')}-'
      '${_date.month.toString().padLeft(2, '0')}-'
      '${_date.day.toString().padLeft(2, '0')}';

  /// Sends [question] to the AI. Appends a user turn immediately, then an
  /// assistant turn once the callable returns. No-ops on empty input or while a
  /// previous question is still in flight.
  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _sending) return;

    // Snapshot history (oldest first) BEFORE adding the new user turn.
    final history = List<DailyBriefTurn>.from(_turns);

    _turns.add(DailyBriefTurn(
      role: 'user',
      content: trimmed,
      createdAt: DateTime.now(),
    ));
    _sending = true;
    _error = null;
    notifyListeners();

    try {
      final reply = await _functions.dailyBrief(
        repoId: _repoId,
        date: _dateKey,
        question: trimmed,
        history: history,
      );
      _turns.add(DailyBriefTurn(
        role: 'assistant',
        content: reply.answer,
        sources: reply.sources,
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      _error = '$e';
      _turns.add(DailyBriefTurn(
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
