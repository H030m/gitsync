import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/commit.dart';
import '../models/commit_graph.dart';
import '../repositories/commit_repo.dart';
import '../services/functions_service.dart';

/// The Commits tab's two visualizations: real branch topology vs the
/// per-author rail map.
enum CommitsViewMode { branch, author }

/// Streams the Commits tab's commit list (recent by default, or a user-picked
/// inclusive day range) and serves the tree map's "tap a commit → AI explains
/// the work" action, caching explanations per sha for the session.
class CommitsViewModel with ChangeNotifier {
  CommitsViewModel({
    required String repoId,
    CommitRepository? commitRepository,
    FunctionsService? functionsService,
  }) : _repoId = repoId,
       _repo = commitRepository ?? CommitRepository(),
       _functions = functionsService ?? FunctionsService() {
    _subscribe();
    // The branch view is the default visualization — fetch its data up front.
    loadGraph();
  }

  final String _repoId;
  final CommitRepository _repo;
  final FunctionsService _functions;
  StreamSubscription<List<Commit>>? _sub;

  List<Commit> _commits = [];
  List<Commit> get commits => _commits;

  bool _loading = true;
  bool get loading => _loading;

  String? _streamError;

  /// Non-null when the commit stream itself failed (parse error, permission,
  /// missing index, offline). The tab shows an error state with a retry.
  String? get streamError => _streamError;

  // ---- Range filter --------------------------------------------------------

  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  DateTime? get rangeStart => _rangeStart;
  DateTime? get rangeEnd => _rangeEnd;
  bool get hasRange => _rangeStart != null && _rangeEnd != null;

  void _subscribe() {
    _sub?.cancel();
    _loading = true;
    _streamError = null;
    final stream = hasRange
        ? _repo.streamRange(_repoId, _rangeStart!, _rangeEnd!)
        : _repo.streamRecent(_repoId, limit: 50);
    _sub = stream.listen(
      (commits) {
        _commits = commits;
        _loading = false;
        _streamError = null;
        notifyListeners();
      },
      onError: (Object e) {
        // Without this handler a stream error would leave `loading` true
        // forever (an eternal spinner). Surface it instead.
        _streamError = '$e';
        _loading = false;
        notifyListeners();
      },
    );
  }

  /// Re-subscribes after a stream error (the "Retry" button).
  void retry() {
    _subscribe();
    notifyListeners();
  }

  /// Filters the list to commits inside [start]..[end] (inclusive days).
  void setRange(DateTime start, DateTime end) {
    _rangeStart = start;
    _rangeEnd = end;
    _subscribe();
    _invalidateGraph();
    notifyListeners();
  }

  /// Back to the default "recent commits" stream.
  void clearRange() {
    _rangeStart = null;
    _rangeEnd = null;
    _subscribe();
    _invalidateGraph();
    notifyListeners();
  }

  // ---- Branch graph (real topology via getCommitGraph) ----------------------

  CommitsViewMode _viewMode = CommitsViewMode.branch;
  CommitsViewMode get viewMode => _viewMode;

  CommitGraph? _graph;
  CommitGraph? get graph => _graph;

  bool _graphLoading = false;
  bool get graphLoading => _graphLoading;

  String? _graphError;
  String? get graphError => _graphError;

  void setViewMode(CommitsViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    if (mode == CommitsViewMode.branch && _graph == null && !_graphLoading) {
      loadGraph();
    }
    notifyListeners();
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Fetches the branch topology for the current range (or "recent"). The
  /// backend caches briefly, so re-toggling the view is cheap; pass [force] to
  /// bypass that cache (pull-to-refresh / the refresh button). On a refresh the
  /// existing graph stays visible — `_graph` is not cleared — so the view only
  /// shows the full-screen spinner on the very first load (`graph == null`).
  Future<void> loadGraph({bool force = false}) async {
    _graphLoading = true;
    _graphError = null;
    notifyListeners();
    try {
      _graph = await _functions.getCommitGraph(
        repoId: _repoId,
        startDate: hasRange ? _ymd(_rangeStart!) : null,
        endDate: hasRange ? _ymd(_rangeEnd!) : null,
        force: force,
      );
    } catch (e) {
      _graphError = '$e';
    } finally {
      _graphLoading = false;
      notifyListeners();
    }
  }

  // A range change makes the cached graph stale; refetch eagerly only when
  // the branch view is the one on screen.
  void _invalidateGraph() {
    _graph = null;
    _graphError = null;
    if (_viewMode == CommitsViewMode.branch) loadGraph();
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
