// triagePr — PR triage agent core logic.
//
// Pure flow (no Firestore writes, no Discord call): given a PR's repo +
// metadata + a GitHub access token, returns the triage payload
// (summary + 2 recommended reviewers + risk tags). The trigger
// (`triggers/onPullRequestOpened`) persists the payload on
// `pullRequests/{n}` and dispatches the Discord notification.
//
// Reviewer recommendation answers the question "who has historically touched
// these files?", so it queries GitHub's per-path commit list and tallies
// committers (recency-weighted by GitHub's default newest-first ordering). It
// is deliberately NOT the existing `searchMemberCommits()` (which is semantic
// over commit messages by a *given* author — the wrong direction).
import { logger } from 'firebase-functions/v2';

import { getOpenAI, MODELS } from '../config';
import { readTeamState } from '../tools/assignTools';
import {
  listCommitsForPath,
  listPullRequestFiles,
  type PullRequestFile,
} from '../services/githubClient';

export interface TriagePrInput {
  repoId: string;
  prNumber: number;
  prAuthorLogin: string;
  title: string;
  body: string;
  owner: string;
  repo: string;
  accessToken: string;
}

export interface RecommendedReviewer {
  userId: string;
  githubLogin: string | null;
  discordUserId: string | null;
}

export interface TriagePrResult {
  summary: string;
  recommendedReviewers: RecommendedReviewer[];
  riskTags: string[];
}

/** PR is "large" when total touched lines exceed this. Tag-only, no behavior change. */
const LARGE_DIFF_THRESHOLD = 300;
/** Per-file commit-history page size when ranking reviewers. */
const PATH_HISTORY_PER_PAGE = 10;
/** Cap the per-file GitHub round-trips — top N files by churn. */
const TOP_FILES_FOR_REVIEWERS = 10;
/** Number of reviewer recommendations to return. */
const REVIEWER_PICK_COUNT = 2;
/** Patch chars sent to the LLM per file (keeps prompt under ~2K tokens). */
const PATCH_PREVIEW_CHARS = 600;

/**
 * Deterministic risk tags. Cheap, no LLM cost; high-signal hints for
 * reviewers. Path predicates are intentionally conservative — false positives
 * are fine (a banner tag in a Discord post), false negatives are not.
 */
export function computeRiskTags(files: PullRequestFile[]): string[] {
  const tags: string[] = [];
  const totalChurn = files.reduce(
    (n, f) => n + f.additions + f.deletions,
    0,
  );
  if (totalChurn > LARGE_DIFF_THRESHOLD) tags.push('large-diff');
  if (files.some((f) => f.filename.startsWith('functions/'))) {
    tags.push('touches-functions');
  }
  if (
    files.some(
      (f) =>
        f.filename === 'firestore.rules' ||
        f.filename === 'firestore.indexes.json',
    )
  ) {
    tags.push('touches-rules');
  }
  if (
    files.some(
      (f) =>
        /(^|\/)migrations\//.test(f.filename) ||
        /(^|\/)schema\//.test(f.filename),
    )
  ) {
    tags.push('touches-schema');
  }
  return tags;
}

/**
 * Tally committers across the top-churn files, weighted by recency rank.
 * The `repos.listCommits({path})` API returns newest-first, so a per-file
 * rank-N commit scores `1/(N+1)` — recent contributors dominate, but a
 * long-standing maintainer still surfaces. PR author is excluded.
 */
async function tallyCommittersByPath(
  input: TriagePrInput,
  topFiles: PullRequestFile[],
): Promise<Map<string, number>> {
  const scoreByLogin = new Map<string, number>();
  const lowerAuthor = input.prAuthorLogin.toLowerCase();

  for (const file of topFiles) {
    let commits;
    try {
      commits = await listCommitsForPath(
        input.owner,
        input.repo,
        input.accessToken,
        file.filename,
        PATH_HISTORY_PER_PAGE,
      );
    } catch (err) {
      // A single file's history may 404 (rename / removed). Skip, don't fail
      // the whole triage — we still have signal from the other files.
      logger.warn('triagePr: listCommitsForPath failed (skipping file)', {
        repoId: input.repoId,
        prNumber: input.prNumber,
        path: file.filename,
        err: String(err),
      });
      continue;
    }
    commits.forEach((c, rank) => {
      const login = c.authorLogin.toLowerCase();
      if (!login || login === lowerAuthor) return;
      scoreByLogin.set(login, (scoreByLogin.get(login) ?? 0) + 1 / (rank + 1));
    });
  }
  return scoreByLogin;
}

/**
 * Maps tallied GitHub logins → roster members. Anyone whose login isn't in
 * the repo's members list is dropped (we can't @ a non-member on Discord
 * and won't recommend an outside contributor anyway). Sorted by score desc,
 * ties broken by lower `activeIssueCount` (don't pile work on the busiest).
 */
async function pickReviewers(
  repoId: string,
  prAuthorLogin: string,
  scoreByLogin: Map<string, number>,
): Promise<RecommendedReviewer[]> {
  if (scoreByLogin.size === 0) return [];

  let roster;
  try {
    roster = await readTeamState(repoId);
  } catch (err) {
    logger.warn('triagePr: readTeamState failed (no reviewers)', {
      repoId,
      err: String(err),
    });
    return [];
  }

  const lowerAuthor = prAuthorLogin.toLowerCase();
  const candidates = roster
    .filter((m) => m.githubLogin)
    .filter((m) => m.githubLogin!.toLowerCase() !== lowerAuthor)
    .map((m) => ({
      member: m,
      score: scoreByLogin.get(m.githubLogin!.toLowerCase()) ?? 0,
    }))
    .filter((c) => c.score > 0);

  candidates.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    return a.member.activeIssueCount - b.member.activeIssueCount;
  });

  return candidates.slice(0, REVIEWER_PICK_COUNT).map((c) => ({
    userId: c.member.userId,
    githubLogin: c.member.githubLogin,
    discordUserId: c.member.discordUserId,
  }));
}

/**
 * One LLM call (gpt-4o-mini) — short prompt, deterministic system message,
 * 3–5 line plain summary. Best-effort: returns "" on failure so the rest of
 * the triage (reviewers + tags) still lands.
 */
async function summarizeDiff(
  input: TriagePrInput,
  files: PullRequestFile[],
): Promise<string> {
  // File list with a tiny patch preview each — enough for "what's the intent",
  // not enough to blow the token budget.
  const filesBlock = files
    .slice(0, TOP_FILES_FOR_REVIEWERS)
    .map((f) => {
      const header = `${f.filename}  (+${f.additions} −${f.deletions})`;
      if (!f.patch) return header;
      const preview = f.patch.slice(0, PATCH_PREVIEW_CHARS);
      return `${header}\n${preview}`;
    })
    .join('\n\n');

  const prompt =
    `PR title: ${input.title}\n\n` +
    `PR description:\n${input.body || '(empty)'}\n\n` +
    `Changed files (top ${TOP_FILES_FOR_REVIEWERS} by churn):\n${filesBlock}`;

  try {
    const completion = await getOpenAI().chat.completions.create({
      model: MODELS.fast,
      messages: [
        {
          role: 'system',
          content:
            'You summarize a GitHub pull request for teammates who need to ' +
            'decide whether to review it. Reply with 3–5 short lines (plain ' +
            "text, no bullets, no headers). Focus on the PR's INTENT and any " +
            'unusual concerns. Do NOT restate the file list — the reader ' +
            'already has it.',
        },
        { role: 'user', content: prompt },
      ],
    });
    return completion.choices[0]?.message?.content?.trim() ?? '';
  } catch (err) {
    logger.warn('triagePr: summarizeDiff failed (returning empty)', {
      repoId: input.repoId,
      prNumber: input.prNumber,
      err: String(err),
    });
    return '';
  }
}

/**
 * Top-level entry. Always resolves to a `TriagePrResult` — empty fields
 * on degraded paths rather than throwing, so the trigger can always persist
 * the partial outcome and mark `triagedAt`.
 */
export async function triagePr(input: TriagePrInput): Promise<TriagePrResult> {
  let files: PullRequestFile[];
  try {
    files = await listPullRequestFiles(
      input.owner,
      input.repo,
      input.accessToken,
      input.prNumber,
    );
  } catch (err) {
    // No files = no signal for reviewers + no diff for the summary. We still
    // resolve (empty) so the trigger can mark triagedAt and not loop.
    logger.warn('triagePr: listPullRequestFiles failed (empty result)', {
      repoId: input.repoId,
      prNumber: input.prNumber,
      err: String(err),
    });
    return { summary: '', recommendedReviewers: [], riskTags: [] };
  }

  const riskTags = computeRiskTags(files);

  // Reviewer ranking only needs the high-churn files (per-file GitHub round
  // trip is the rate-limit cost), but the summary should see all files'
  // headers for completeness.
  const topByChurn = [...files]
    .sort(
      (a, b) => b.additions + b.deletions - (a.additions + a.deletions),
    )
    .slice(0, TOP_FILES_FOR_REVIEWERS);

  const [scoreByLogin, summary] = await Promise.all([
    tallyCommittersByPath(input, topByChurn),
    summarizeDiff(input, files),
  ]);

  const recommendedReviewers = await pickReviewers(
    input.repoId,
    input.prAuthorLogin,
    scoreByLogin,
  );

  return { summary, recommendedReviewers, riskTags };
}
