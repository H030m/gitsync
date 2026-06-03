import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/discord_digest.dart';
import '../models/discord_message.dart';
import '../repositories/discord_digest_repo.dart';
import '../repositories/discord_message_repo.dart';
import '../services/functions_service.dart';

class DiscordMessagesViewModel with ChangeNotifier {
  DiscordMessagesViewModel({
    required String repoId,
    DateTime? date,
    DiscordMessageRepository? messageRepository,
    DiscordDigestRepository? digestRepository,
    FunctionsService? functionsService,
  })  : _repoId = repoId,
        _date = date ?? DateTime.now(),
        _repo = messageRepository ?? DiscordMessageRepository(),
        _digestRepo = digestRepository ?? DiscordDigestRepository(),
        _functions = functionsService ?? FunctionsService() {
    _sub = _repo.streamRecent(_repoId).listen((messages) {
      _messages = messages;
      _loading = false;
      notifyListeners();
    });
    _digestSub = _digestRepo.streamDigest(_repoId, _dateKey).listen((digest) {
      _digest = digest;
      notifyListeners();
    });
  }

  final String _repoId;
  final DateTime _date;
  final DiscordMessageRepository _repo;
  final DiscordDigestRepository _digestRepo;
  final FunctionsService _functions;
  StreamSubscription<List<DiscordMessage>>? _sub;
  StreamSubscription<DiscordDigest?>? _digestSub;

  List<DiscordMessage> _messages = [];
  List<DiscordMessage> get messages => _messages;

  DiscordDigest? _digest;
  DiscordDigest? get digest => _digest;

  bool _loading = true;
  bool get loading => _loading;

  bool _refreshing = false;
  bool get refreshing => _refreshing;

  bool _settingStartDate = false;
  bool get settingStartDate => _settingStartDate;

  String get _dateKey =>
      '${_date.year.toString().padLeft(4, '0')}-'
      '${_date.month.toString().padLeft(2, '0')}-'
      '${_date.day.toString().padLeft(2, '0')}';

  // Triggers an on-demand Discord backfill for the day. The bot ingests the
  // messages and the backend writes a digest, which arrives via the stream.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      await _functions.requestDiscordFetch(repoId: _repoId, date: _dateKey);
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  String _keyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // Sets the backfill start date for this repo's Discord channels. After this,
  // the next refresh re-pulls from [date] (already-ingested messages dedupe).
  Future<void> setStartDate(DateTime date) async {
    if (_settingStartDate) return;
    _settingStartDate = true;
    notifyListeners();
    try {
      await _functions.setDiscordStartDate(
        repoId: _repoId,
        startDate: _keyOf(date),
      );
    } finally {
      _settingStartDate = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _digestSub?.cancel();
    super.dispose();
  }
}
