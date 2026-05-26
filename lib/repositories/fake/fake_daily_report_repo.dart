import '../../config/app_config.dart';
import '../../data/dummy_data.dart';
import '../../models/daily_report.dart';
import '../daily_report_repo.dart';

class FakeDailyReportRepository implements DailyReportRepository {
  factory FakeDailyReportRepository() => _instance;
  FakeDailyReportRepository._internal();
  static final FakeDailyReportRepository _instance =
      FakeDailyReportRepository._internal();

  @override
  Stream<DailyReport?> streamReport(String repoId, String date) async* {
    if (repoId != DummyData.demoRepoId ||
        date != DummyData.todayReport.date) {
      yield null;
      return;
    }
    yield DummyData.todayReport;
  }

  @override
  Future<DailyReport?> getReport(String repoId, String date) async {
    await Future.delayed(AppConfig.simulatedLatency);
    if (repoId != DummyData.demoRepoId ||
        date != DummyData.todayReport.date) {
      return null;
    }
    return DummyData.todayReport;
  }
}
