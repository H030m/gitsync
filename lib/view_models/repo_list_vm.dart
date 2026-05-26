import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/repo.dart';
import '../repositories/repo_repo.dart';

// Streams the repos the current user is a member of (RepoListPage).
class RepoListViewModel with ChangeNotifier {
  RepoListViewModel({
    required String userId,
    RepoRepository? repoRepository,
  })  : _userId = userId,
        _repo = repoRepository ?? RepoRepository() {
    _sub = _repo.streamReposOfUser(_userId).listen((repos) {
      _repos = repos;
      _loading = false;
      notifyListeners();
    });
  }

  final String _userId;
  final RepoRepository _repo;
  StreamSubscription<List<Repo>>? _sub;

  List<Repo> _repos = [];
  List<Repo> get repos => _repos;

  bool _loading = true;
  bool get loading => _loading;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
