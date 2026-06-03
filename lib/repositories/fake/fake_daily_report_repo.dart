import '../../config/app_config.dart';
import '../../data/dummy_data.dart';
import '../../models/daily_report.dart';
import '../daily_report_repo.dart';

class FakeDailyReportRepository implements DailyReportRepository {
  factory FakeDailyReportRepository() => _instance;
  FakeDailyReportRepository._internal();
  static final FakeDailyReportRepository _instance =
      FakeDailyReportRepository._internal();

  // Serves today's demo report for today's key AND for any `{start}_{end}`
  // range key (so the range picker shows content in fake mode). Other single
  // days have no report — mirrors live, where most days are ungenerated.
  DailyReport? _lookup(String repoId, String date) {
    if (repoId != DummyData.demoRepoId) return null;
    if (date == DummyData.todayReport.date) return DummyData.todayReport;
    if (date.contains('_')) return DummyData.todayReport;
    return null;
  }

  @override
  Stream<DailyReport?> streamReport(String repoId, String date) async* {
    yield _lookup(repoId, date);
  }

  @override
  Future<DailyReport?> getReport(String repoId, String date) async {
    await Future.delayed(AppConfig.simulatedLatency);
    return _lookup(repoId, date);
  }
}
