// scheduledDailyReport — fan-out scheduler. Runs at 18:00 Taipei daily,
// scans every repo doc, enqueues one Cloud Task per repo targeting
// `dailyReportWorker`. The scheduler itself returns immediately.
// See ARCHITECTURE.md §5.4.
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions/v2';

import { db, REGION } from '../admin';

export const scheduledDailyReport = onSchedule(
  {
    schedule: '0 18 * * *',
    timeZone: 'Asia/Taipei',
    region: REGION,
  },
  async () => {
    const snap = await db.collection('apps/gitsync/repos').get();
    const ids = snap.docs.map((d) => d.id);
    const today = new Date().toISOString().slice(0, 10);
    logger.info(`scheduledDailyReport: fanning out ${ids.length} repos`, { date: today });
    // TODO Sprint 4:
    //  - For each repoId, enqueue a Cloud Task on `daily-report-queue` with
    //    body { repoId, date: today }, target = dailyReportWorker URL
    //  - The Cloud Tasks queue must be created by a human:
    //      gcloud tasks queues create daily-report-queue --location=us-west1
  },
);
