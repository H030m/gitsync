import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/daily_report.dart';
import '../repositories/daily_report_repo.dart';
import '../services/functions_service.dart';

class DailyReportViewModel with ChangeNotifier {
  DailyReportViewModel({
    required String repoId,
    DateTime? date,
    DailyReportRepository? reportRepository,
    FunctionsService? functionsService,
  })  : _repoId = repoId,
        _date = date ?? DateTime.now(),
        _repo = reportRepository ?? DailyReportRepository(),
        _functions = functionsService ?? FunctionsService() {
    _sub = _repo.streamReport(_repoId, _dateKey).listen((report) {
      _report = report;
      _loading = false;
      notifyListeners();
    });
  }

  final String _repoId;
  final DateTime _date;
  final DailyReportRepository _repo;
  final FunctionsService _functions;
  StreamSubscription<DailyReport?>? _sub;

  DailyReport? _report;
  DailyReport? get report => _report;

  bool _loading = true;
  bool get loading => _loading;

  bool _regenerating = false;
  bool get regenerating => _regenerating;

  String get _dateKey =>
      '${_date.year.toString().padLeft(4, '0')}-'
      '${_date.month.toString().padLeft(2, '0')}-'
      '${_date.day.toString().padLeft(2, '0')}';

  // Manual trigger for AI-generated daily summary.
  Future<void> regenerate() async {
    if (_regenerating) return;
    _regenerating = true;
    notifyListeners();
    try {
      await _functions.summarizeDay(repoId: _repoId, date: _dateKey);
    } finally {
      _regenerating = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
