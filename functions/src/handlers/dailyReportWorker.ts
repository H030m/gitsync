// dailyReportWorker (onRequest) — Cloud Tasks target. Each instance processes
// exactly one repo's daily report. Fanned out from `scheduledDailyReport`.
// See ARCHITECTURE.md §5.4.
import { onRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

import { REGION } from '../admin';
import { openaiKey } from '../config';
import { summarizeDayFlow } from '../flows/summarizeDay';

export const dailyReportWorker = onRequest(
  { region: REGION, secrets: [openaiKey], timeoutSeconds: 300, maxInstances: 50 },
  async (req, res) => {
    const { repoId, date } = (req.body ?? {}) as {
      repoId?: string;
      date?: string;
    };
    if (!repoId || !date) {
      res.status(400).send({ error: 'repoId and date are required' });
      return;
    }
    try {
      const result = await summarizeDayFlow({ repoId, date });
      res.status(200).send({ ok: true, ...result });
    } catch (e) {
      logger.error('dailyReportWorker failed', { repoId, date, error: String(e) });
      res.status(500).send({ error: String(e) });
    }
  },
);
