import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/daily_report.dart';
import 'firestore_paths.dart';

// NOTE: `dailyReports` is write-blocked for clients (the
// `scheduledDailyReport` worker writes it server-side).
class DailyReportRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _timeout = Duration(seconds: 10);

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
