import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/discord_digest.dart';
import '../models/discord_message.dart';
import '../models/repo.dart';
import '../repositories/discord_digest_repo.dart';
import '../repositories/discord_message_repo.dart';
import '../repositories/repo_repo.dart';
import '../services/functions_service.dart';

class DiscordMessagesViewModel with ChangeNotifier {
  DiscordMessagesViewModel({
    required String repoId,
    DateTime? date,
    DiscordMessageRepository? messageRepository,
    DiscordDigestRepository? digestRepository,
    RepoRepository? repoRepository,
    FunctionsService? functionsService,
  })  : _repoId = repoId,
        _date = date ?? DateTime.now(),
        _repo = messageRepository ?? DiscordMessageRepository(),
        _digestRepo = digestRepository ?? DiscordDigestRepository(),
        _repoRepo = repoRepository ?? RepoRepository(),
        _functions = functionsService ?? FunctionsService() {
    _sub = _repo.streamRecent(_repoId).listen((messages) {
      _messages = messages;
      _loading = false;
      notifyListeners();
    });
    // The digest follows the range's end date (latest day), defaulting to
    // today until the repo doc (and its range) arrives.
    _digestDateKey = _keyOf(_date);
    _subscribeDigest(_digestDateKey);
    _repoSub = _repoRepo.streamRepo(_repoId).listen(_onRepo);
  }

  final String _repoId;
  final DateTime _date;
  final DiscordMessageRepository _repo;
  final DiscordDigestRepository _digestRepo;
  final RepoRepository _repoRepo;
  final FunctionsService _functions;
  StreamSubscription<List<DiscordMessage>>? _sub;
  StreamSubscription<DiscordDigest?>? _digestSub;
  StreamSubscription<Repo?>? _repoSub;

  // The day the digest stream is currently subscribed to (YYYY-MM-DD). Follows
  // the range's end date; starts at today.
  late String _digestDateKey;

  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  /// Range start parsed from the repo doc's `discordStartDate`, null if unset.
  DateTime? get rangeStart => _rangeStart;

  /// Range end parsed from the repo doc's `discordEndDate`, null if unset.
  DateTime? get rangeEnd => _rangeEnd;

  List<DiscordMessage> _messages = [];
  List<DiscordMessage> get messages => _messages;

  DiscordDigest? _digest;
  DiscordDigest? get digest => _digest;

  bool _loading = true;
  bool get loading => _loading;

  bool _refreshing = false;
  bool get refreshing => _refreshing;

  bool _settingRange = false;
  bool get settingRange => _settingRange;

  bool _editingDigest = false;
  bool get editingDigest => _editingDigest;

  bool _togglingLock = false;
  bool get togglingLock => _togglingLock;

  String? _digestError;
  String? get digestError => _digestError;

  String _keyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // Parses a YYYY-MM-DD key into a local DateTime, null if absent/unparseable.
  DateTime? _parseKey(String? key) {
    if (key == null || key.isEmpty) return null;
    return DateTime.tryParse(key);
  }

  void _subscribeDigest(String dateKey) {
    _digestSub?.cancel();
    _digestSub = _digestRepo.streamDigest(_repoId, dateKey).listen((digest) {
      _digest = digest;
      notifyListeners();
    });
  }

  // Reacts to repo doc changes: updates the saved range and, when the range's
  // end date changes, re-points the digest stream at that latest day.
  void _onRepo(Repo? repo) {
    _rangeStart = _parseKey(repo?.discordStartDate);
    _rangeEnd = _parseKey(repo?.discordEndDate);

    // Digest follows the end date (latest day), defaulting to today.
    final newKey =
        _rangeEnd != null ? _keyOf(_rangeEnd!) : _keyOf(_date);
    if (newKey != _digestDateKey) {
      _digestDateKey = newKey;
      _subscribeDigest(_digestDateKey);
    }
    notifyListeners();
  }

  // Triggers an on-demand Discord backfill for the range's end date (latest
  // day). The bot ingests the messages and the backend writes a digest, which
  // arrives via the stream.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      await _functions.requestDiscordFetch(
        repoId: _repoId,
        date: _digestDateKey,
      );
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  // Sets the backfill date range for this repo's Discord channels. After this,
  // the next refresh re-pulls the range (already-ingested messages dedupe). The
  // new range arrives via the repo stream, so we don't set it locally.
  Future<void> setRange(DateTime start, DateTime end) async {
    if (_settingRange) return;
    _settingRange = true;
    notifyListeners();
    try {
      await _functions.setDiscordRange(
        repoId: _repoId,
        startDate: _keyOf(start),
        endDate: _keyOf(end),
      );
    } finally {
      _settingRange = false;
      notifyListeners();
    }
  }

  // Asks the AI to adjust the digest for the range's end date. The updated
  // markdown arrives via the digest stream, so we don't set it locally. No-ops
  // if there's no digest yet.
  Future<void> editDigest(String instruction) async {
    if (_editingDigest || _digest == null || instruction.trim().isEmpty) return;
    _editingDigest = true;
    _digestError = null;
    notifyListeners();
    try {
      await _functions.editDiscordDigest(
        repoId: _repoId,
        date: _digestDateKey,
        instruction: instruction.trim(),
      );
    } catch (e) {
      _digestError = '$e';
    } finally {
      _editingDigest = false;
      notifyListeners();
    }
  }

  // Toggles the lock on the digest for the range's end date. When locked, the
  // backend won't change it (auto-regen and AI edits are both refused).
  Future<void> toggleLock() async {
    final digest = _digest;
    if (_togglingLock || digest == null) return;
    _togglingLock = true;
    _digestError = null;
    notifyListeners();
    try {
      await _functions.setDigestLock(
        repoId: _repoId,
        date: _digestDateKey,
        locked: !digest.locked,
      );
    } catch (e) {
      _digestError = '$e';
    } finally {
      _togglingLock = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _digestSub?.cancel();
    _repoSub?.cancel();
    super.dispose();
  }
}
