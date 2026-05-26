import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/app_config.dart';
import '../models/daily_report.dart';
import 'fake/fake_daily_report_repo.dart';
import 'firestore_paths.dart';

abstract class DailyReportRepository {
  factory DailyReportRepository() => AppConfig.useFakeBackend
      ? FakeDailyReportRepository()
      : _LiveDailyReportRepository();

  Stream<DailyReport?> streamReport(String repoId, String date);
  Future<DailyReport?> getReport(String repoId, String date);
}

// NOTE: `dailyReports` is write-blocked for clients.
class _LiveDailyReportRepository implements DailyReportRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _timeout = Duration(seconds: 10);

  @override
  Stream<DailyReport?> streamReport(String repoId, String date) {
    return _db
        .doc('${FirestorePaths.dailyReports(repoId)}/$date')
        .snapshots()
        .map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return DailyReport.fromMap(data, snap.id);
    });
  }

  @override
  Future<DailyReport?> getReport(String repoId, String date) async {
    final snap = await _db
        .doc('${FirestorePaths.dailyReports(repoId)}/$date')
        .get()
        .timeout(_timeout);
    final data = snap.data();
    if (data == null) return null;
    return DailyReport.fromMap(data, snap.id);
  }
}
