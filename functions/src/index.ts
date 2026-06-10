// Cloud Functions entry point. Every exported symbol becomes a deployable
// function. Side-effect import of `./admin` initializes firebase-admin.
import './admin';

// ---- Callables ------------------------------------------------------------
export { addRepo } from './handlers/addRepo';
export { removeRepo } from './handlers/removeRepo';
export { breakdownTask } from './handlers/breakdownTask';
export { forceUnlockBreakdown } from './handlers/forceUnlockBreakdown';
export { assignTask } from './handlers/assignTask';
export { generateHandoff } from './handlers/generateHandoff';
export { summarizeDay } from './handlers/summarizeDay';
export { setDiscordWebhook } from './handlers/setDiscordWebhook';
export { subscribeToTopic } from './handlers/subscribeToTopic';
export { requestDiscordFetch } from './handlers/requestDiscordFetch';

// ---- HTTP (webhooks + Cloud Tasks workers) -------------------------------
export { githubWebhook } from './handlers/githubWebhook';
export { discordMessageIngest } from './handlers/discordMessageIngest';
export { dailyReportWorker } from './handlers/dailyReportWorker';
export { claimDiscordFetch } from './handlers/claimDiscordFetch';
export { completeDiscordFetch } from './handlers/completeDiscordFetch';
export { setRepoChannel } from './handlers/setRepoChannel';

// ---- Firestore triggers --------------------------------------------------
export { onTaskCreated } from './triggers/onTaskCreated';
export { onTaskUpdated } from './triggers/onTaskUpdated';
export { onCommitCreated } from './triggers/onCommitCreated';
export { onPRMerged } from './triggers/onPRMerged';
export { onIssueWritten } from './triggers/onIssueWritten';
export { onDiscordMessageCreated } from './triggers/onDiscordMessageCreated';

// ---- Scheduled triggers --------------------------------------------------
export { scheduledDailyReport } from './triggers/scheduledDailyReport';
export { scheduledUnstickBreakdown } from './triggers/scheduledUnstickBreakdown';
