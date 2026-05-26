import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/member.dart';
import '../repositories/member_repo.dart';

class MembersViewModel with ChangeNotifier {
  MembersViewModel({
    required String repoId,
    MemberRepository? memberRepository,
  })  : _repoId = repoId,
        _repo = memberRepository ?? MemberRepository() {
    _sub = _repo.streamMembers(_repoId).listen((members) {
      _members = members;
      _loading = false;
      notifyListeners();
    });
  }

  final String _repoId;
  final MemberRepository _repo;
  StreamSubscription<List<Member>>? _sub;

  List<Member> _members = [];
  List<Member> get members => _members;

  bool _loading = true;
  bool get loading => _loading;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
