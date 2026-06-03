import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/daily_report.dart';
import '../repositories/daily_report_repo.dart';
import '../services/functions_service.dart';

/// Streams the AI report for the selected period (a single day by default,
/// today) and triggers regeneration. The user can widen the period via
/// [setRange] — multi-day reports live under the `{start}_{end}` doc id
/// (see functions/src/flows/summarizeDay.ts `reportDocId`).
class DailyReportViewModel with ChangeNotifier {
  DailyReportViewModel({
    required String repoId,
    DateTime? date,
    DailyReportRepository? reportRepository,
    FunctionsService? functionsService,
  })  : _repoId = repoId,
        _start = date ?? DateTime.now(),
        _end = date ?? DateTime.now(),
        _repo = reportRepository ?? DailyReportRepository(),
        _functions = functionsService ?? FunctionsService() {
    _subscribe();
  }

  final String _repoId;
  DateTime _start;
  DateTime _end;
  final DailyReportRepository _repo;
  final FunctionsService _functions;
  StreamSubscription<DailyReport?>? _sub;

  DailyReport? _report;
  DailyReport? get report => _report;

  bool _loading = true;
  bool get loading => _loading;

  bool _regenerating = false;
  bool get regenerating => _regenerating;

  DateTime get rangeStart => _start;
  DateTime get rangeEnd => _end;

  /// True when the selected period is a single calendar day.
  bool get isSingleDay => _dayKey(_start) == _dayKey(_end);

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String get startKey => _dayKey(_start);
  String get endKey => _dayKey(_end);

  /// Report doc id for the current period (mirrors the backend's contract).
  String get docKey => isSingleDay ? startKey : '${startKey}_$endKey';

  void _subscribe() {
    _sub?.cancel();
    _loading = true;
    _report = null;
    _sub = _repo.streamReport(_repoId, docKey).listen((report) {
      _report = report;
      _loading = false;
      notifyListeners();
    });
  }

  /// Re-points the stream at the report for [start]..[end] (inclusive days).
  void setRange(DateTime start, DateTime end) {
    _start = start;
    _end = end;
    _subscribe();
    notifyListeners();
  }

  // Manual trigger for the AI-generated period report.
  Future<void> regenerate() async {
    if (_regenerating) return;
    _regenerating = true;
    notifyListeners();
    try {
      await _functions.summarizeDay(
        repoId: _repoId,
        startDate: startKey,
        endDate: endKey,
      );
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
