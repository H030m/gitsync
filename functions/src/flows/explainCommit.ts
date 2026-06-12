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
import { getCommit } from '../services/githubClient';
import { explainCommitSystemPrompt, explainCommitContext } from '../prompts/explainCommit';

export interface ExplainCommitInput {
  repoId: string;
  sha: string;
  /** Regenerate even when a cached workSummary exists. */
  force?: boolean;
  /**
   * W6: optional human-readable English language NAME (e.g. "Traditional
   * Chinese") that forces the work summary into the user's app language on an
   * explicit recompute. Applies to both the doc path and the GitHub fallback
   * path. Absent/empty → unchanged behavior (the auto/first tap omits it).
   */
  language?: string;
  /**
   * Optional GitHub fallback (06-05 D2): when the commit doc is missing (e.g. a
   * branch-graph commit predating all-branch ingest), fetch the commit from the
   * GitHub API instead of 404ing. Requires all three; the cache is NOT written
   * on this path (no doc to cache on).
   */
  owner?: string;
  repo?: string;
  accessToken?: string;
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
  const { repoId, sha, force, language, owner, repo, accessToken } = input;

  const ref = db.doc(`apps/gitsync/repos/${repoId}/commits/${sha}`);
  const snap = await ref.get();
  if (!snap.exists) {
    // ---- GitHub fallback (06-05 D2) -----------------------------------------
    // No Firestore doc (branch-graph / historical commit predating all-branch
    // ingest). If we have GitHub creds, fetch the commit and summarize it from
    // that context — no linked tasks, no neighbors, no cache write-back.
    if (owner && repo && accessToken) {
      return explainFromGitHub({ repoId, sha, owner, repo, accessToken, language });
    }
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
      { role: 'system', content: explainCommitSystemPrompt(language) },
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

/**
 * Fallback summary path (06-05 D2): generates an explanation from the GitHub
 * API when no Firestore commit doc exists. Simpler context than the doc path —
 * just message + files (no linked tasks, no neighbor commits) — and never writes
 * a cache (there is no doc to cache on).
 */
async function explainFromGitHub(input: {
  repoId: string;
  sha: string;
  owner: string;
  repo: string;
  accessToken: string;
  /** W6: forces the fallback explanation into the user's app language. */
  language?: string;
}): Promise<ExplainCommitResult> {
  const { repoId, sha, owner, repo, accessToken, language } = input;
  const detail = await getCommit(owner, repo, accessToken, sha);

  const completion = await getOpenAI().chat.completions.create({
    model: MODELS.fast,
    messages: [
      { role: 'system', content: explainCommitSystemPrompt(language) },
      {
        role: 'user',
        content: explainCommitContext({
          sha,
          message: detail.message,
          authorName: detail.authorName || detail.authorLogin || 'unknown',
          filesChanged: detail.files,
          additions: detail.additions,
          deletions: detail.deletions,
          aiSummary: null,
          linkedTasks: [],
          neighborCommits: [],
        }),
      },
    ],
  });
  const markdown = completion.choices[0]?.message?.content?.trim() ?? '';
  if (!markdown) {
    throw new HttpsError('internal', 'OpenAI returned an empty explanation');
  }

  logger.info('explainCommit: generated via GitHub fallback', { repoId, sha });
  return { markdown, cached: false };
}
