// explainCommitFlow — "tap a commit on the tree map, get an AI explanation of
// the work". Reads the commit doc plus its linked tasks and the author's
// neighboring commits, asks the model for a short markdown work summary, and
// caches the result on the commit doc (`workSummary`) so repeat taps are
// instant and cost nothing. Only Cloud Functions can write commits (clients
// are read-only), so the cache write happens here.
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';

import { db } from '../admin';
import { getOpenAI, MODELS } from '../config';
import { explainCommitSystem, explainCommitContext } from '../prompts/explainCommit';

export interface ExplainCommitInput {
  repoId: string;
  sha: string;
  /** Regenerate even when a cached workSummary exists. */
  force?: boolean;
}

export interface ExplainCommitResult {
  markdown: string;
  cached: boolean;
}

/** How many of the author's neighboring commits we show the model. */
const NEIGHBOR_LIMIT = 10;
/** How many linked tasks we resolve. */
const TASK_LIMIT = 5;

export async function explainCommitFlow(
  input: ExplainCommitInput,
): Promise<ExplainCommitResult> {
  const { repoId, sha, force } = input;

  const ref = db.doc(`apps/gitsync/repos/${repoId}/commits/${sha}`);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'commit not found');
  }
  const commit = snap.data() ?? {};

  // ---- Cache hit: return the stored summary without an OpenAI call --------
  const cachedSummary = commit.workSummary as string | undefined;
  if (cachedSummary && !force) {
    return { markdown: cachedSummary, cached: true };
  }

  // ---- Gather context (all best-effort) ------------------------------------
  const author = (commit.author as Record<string, unknown> | undefined) ?? {};
  const authorLogin = (author.login as string | undefined) ?? '';

  const linkedTaskIds = (
    (commit.linkedTaskIds as string[] | undefined) ?? []
  ).slice(0, TASK_LIMIT);
  const tasks = await Promise.all(
    linkedTaskIds.map(async (id) => {
      try {
        const t = await db.doc(`apps/gitsync/repos/${repoId}/tasks/${id}`).get();
        const data = t.data() ?? {};
        return t.exists
          ? {
              title: (data.title as string | undefined) ?? '',
              status: (data.status as string | undefined) ?? '',
            }
          : null;
      } catch {
        return null;
      }
    }),
  );

  // The author's most recent commits around this one, for narrative context.
  let neighbors: Array<{ sha: string; message: string }> = [];
  if (authorLogin) {
    try {
      const ns = await db
        .collection(`apps/gitsync/repos/${repoId}/commits`)
        .where('author.login', '==', authorLogin)
        .orderBy('committedAt', 'desc')
        .limit(NEIGHBOR_LIMIT + 1)
        .get();
      neighbors = ns.docs
        .filter((d) => d.id !== sha)
        .slice(0, NEIGHBOR_LIMIT)
        .map((d) => ({
          sha: d.id.slice(0, 7),
          message: ((d.data()?.message as string | undefined) ?? '').split('\n')[0],
        }));
    } catch (err) {
      logger.warn('explainCommit: neighbor query failed (best-effort)', {
        repoId,
        sha,
        err: String(err),
      });
    }
  }

  // ---- One OpenAI call ------------------------------------------------------
  const completion = await getOpenAI().chat.completions.create({
    model: MODELS.fast,
    messages: [
      { role: 'system', content: explainCommitSystem },
      {
        role: 'user',
        content: explainCommitContext({
          sha,
          message: (commit.message as string | undefined) ?? '',
          authorName:
            (author.name as string | undefined) ?? authorLogin ?? 'unknown',
          filesChanged: (commit.filesChanged as string[] | undefined) ?? [],
          additions: (commit.additions as number | undefined) ?? 0,
          deletions: (commit.deletions as number | undefined) ?? 0,
          aiSummary: (commit.aiSummary as string | undefined) ?? null,
          linkedTasks: tasks.filter(
            (t): t is { title: string; status: string } => t !== null,
          ),
          neighborCommits: neighbors,
        }),
      },
    ],
  });
  const markdown = completion.choices[0]?.message?.content?.trim() ?? '';
  if (!markdown) {
    throw new HttpsError('internal', 'OpenAI returned an empty explanation');
  }

  // ---- Cache write-back (best-effort — a failed write must not fail the call)
  try {
    await ref.update({
      workSummary: markdown,
      workSummaryGeneratedAt: FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.warn('explainCommit: cache write failed (best-effort)', {
      repoId,
      sha,
      err: String(err),
    });
  }

  logger.info('explainCommit: generated', { repoId, sha });
  return { markdown, cached: false };
}
