import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/discord_message.dart';
import '../repositories/discord_message_repo.dart';

class DiscordMessagesViewModel with ChangeNotifier {
  DiscordMessagesViewModel({
    required String repoId,
    DiscordMessageRepository? messageRepository,
  })  : _repoId = repoId,
        _repo = messageRepository ?? DiscordMessageRepository() {
    _sub = _repo.streamRecent(_repoId).listen((messages) {
      _messages = messages;
      _loading = false;
      notifyListeners();
    });
  }

  final String _repoId;
  final DiscordMessageRepository _repo;
  StreamSubscription<List<DiscordMessage>>? _sub;

  List<DiscordMessage> _messages = [];
  List<DiscordMessage> get messages => _messages;

  bool _loading = true;
  bool get loading => _loading;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
