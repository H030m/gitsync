import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/commit.dart';
import '../repositories/commit_repo.dart';
import '../services/functions_service.dart';

/// Streams the Commits tab's commit list (recent by default, or a user-picked
/// inclusive day range) and serves the tree map's "tap a commit → AI explains
/// the work" action, caching explanations per sha for the session.
class CommitsViewModel with ChangeNotifier {
  CommitsViewModel({
    required String repoId,
    CommitRepository? commitRepository,
    FunctionsService? functionsService,
  })  : _repoId = repoId,
        _repo = commitRepository ?? CommitRepository(),
        _functions = functionsService ?? FunctionsService() {
    _subscribe();
  }

  final String _repoId;
  final CommitRepository _repo;
  final FunctionsService _functions;
  StreamSubscription<List<Commit>>? _sub;

  List<Commit> _commits = [];
  List<Commit> get commits => _commits;

  bool _loading = true;
  bool get loading => _loading;

  // ---- Range filter --------------------------------------------------------

  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  DateTime? get rangeStart => _rangeStart;
  DateTime? get rangeEnd => _rangeEnd;
  bool get hasRange => _rangeStart != null && _rangeEnd != null;

  void _subscribe() {
    _sub?.cancel();
    _loading = true;
    final stream = hasRange
        ? _repo.streamRange(_repoId, _rangeStart!, _rangeEnd!)
        : _repo.streamRecent(_repoId, limit: 50);
    _sub = stream.listen((commits) {
      _commits = commits;
      _loading = false;
      notifyListeners();
    });
  }

  /// Filters the list to commits inside [start]..[end] (inclusive days).
  void setRange(DateTime start, DateTime end) {
    _rangeStart = start;
    _rangeEnd = end;
    _subscribe();
    notifyListeners();
  }

  /// Back to the default "recent commits" stream.
  void clearRange() {
    _rangeStart = null;
    _rangeEnd = null;
    _subscribe();
    notifyListeners();
  }

  // ---- AI work explanations (tree map tap) ---------------------------------

  final Map<String, String> _explanations = {};
  final Set<String> _explaining = {};

  /// The cached AI explanation for [sha], if one was fetched this session.
  String? explanationFor(String sha) => _explanations[sha];

  bool isExplaining(String sha) => _explaining.contains(sha);

  String? _explainError;
  String? get explainError => _explainError;

  /// Fetches (or re-fetches with [force]) the AI work summary for [sha]. The
  /// backend additionally caches on the commit doc, so repeat calls are cheap.
  Future<void> explain(String sha, {bool force = false}) async {
    if (_explaining.contains(sha)) return;
    if (!force && _explanations.containsKey(sha)) return;
    _explaining.add(sha);
    _explainError = null;
    notifyListeners();
    try {
      final markdown = await _functions.explainCommit(
        repoId: _repoId,
        sha: sha,
        force: force,
      );
      _explanations[sha] = markdown;
    } catch (e) {
      _explainError = '$e';
    } finally {
      _explaining.remove(sha);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
