import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/commit.dart';
import '../repositories/commit_repo.dart';

class CommitsViewModel with ChangeNotifier {
  CommitsViewModel({
    required String repoId,
    CommitRepository? commitRepository,
  })  : _repoId = repoId,
        _repo = commitRepository ?? CommitRepository() {
    _sub = _repo.streamRecent(_repoId, limit: 50).listen((commits) {
      _commits = commits;
      _loading = false;
      notifyListeners();
    });
  }

  final String _repoId;
  final CommitRepository _repo;
  StreamSubscription<List<Commit>>? _sub;

  List<Commit> _commits = [];
  List<Commit> get commits => _commits;

  bool _loading = true;
  bool get loading => _loading;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
