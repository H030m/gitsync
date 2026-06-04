// getCommitGraphFlow — assembles the Commits tab's branch-topology graph
// on demand from the GitHub API (PRD D1: no Firestore commit-schema change,
// no backfill; the push webhook payload carries no parent SHAs).
//
// Pipeline: short-TTL Firestore cache → single GraphQL fetch (githubClient)
// → dedupe commits seen from multiple branches → attribute each commit to a
// "primary" branch via first-parent walks → label merge commits with their
// PR number. The client stays a dumb painter.
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';

import { db } from '../admin';
import {
  fetchCommitGraph,
  type GraphBranchRaw,
  type GraphCommitRaw,
} from '../services/githubClient';
import { taipeiRangeBounds } from '../tools/dailyIntel';

export interface GetCommitGraphInput {
  repoId: string;
  owner: string;
  repo: string;
  accessToken: string;
  /** YYYY-MM-DD, inclusive Asia/Taipei days. Omit both for "recent". */
  startDate?: string;
  endDate?: string;
}

export interface GraphCommit {
  sha: string;
  message: string;
  committedAt: string; // ISO 8601
  parents: string[]; // a SHA not present in commits[] = off-screen parent
  author: {
    login: string | null;
    name: string;
    avatarUrl: string | null;
  };
  primaryBranch: string;
  isMerge: boolean;
  prNumber: number | null;
}

export interface GraphBranch {
  name: string;
  tipSha: string;
  isDefault: boolean;
}

export interface CommitGraphResult {
  /** Newest first (same ordering as the Commits tab list). */
  commits: GraphCommit[];
  branches: GraphBranch[];
  cached: boolean;
  /** True when the branch cap or a per-branch history page limit was hit. */
  truncated: boolean;
}

/** Cache TTL — long enough to absorb view toggles, short enough that a fresh
 * push shows up quickly. */
const CACHE_TTL_MS = 90_000;

const MERGE_PR_RE = /^Merge pull request #(\d+)\b/;

export async function getCommitGraphFlow(
  input: GetCommitGraphInput,
): Promise<CommitGraphResult> {
  const { repoId, owner, repo, accessToken, startDate, endDate } = input;

  const hasRange = Boolean(startDate && endDate);
  const cacheKey = hasRange ? `${startDate}_${endDate}` : 'recent';
  const cacheRef = db.doc(`apps/gitsync/repos/${repoId}/graphCache/${cacheKey}`);

  // ---- Cache hit ------------------------------------------------------------
  const cacheSnap = await cacheRef.get();
  const cacheData = cacheSnap.data();
  if (cacheData) {
    const age = Date.now() - ((cacheData.generatedAtMs as number) ?? 0);
    if (age < CACHE_TTL_MS) {
      const payload = cacheData.payload as Omit<CommitGraphResult, 'cached'>;
      return { ...payload, cached: true };
    }
  }

  // ---- Fetch ---------------------------------------------------------------
  let since: string | undefined;
  let until: string | undefined;
  if (hasRange) {
    // Same inclusive-Taipei-day semantics as the report range queries.
    const bounds = taipeiRangeBounds(startDate!, endDate!);
    since = bounds.start.toDate().toISOString();
    until = bounds.end.toDate().toISOString();
  }

  let branchesRaw: GraphBranchRaw[];
  let branchesTruncated: boolean;
  try {
    const fetched = await fetchCommitGraph(owner, repo, accessToken, {
      since,
      until,
    });
    branchesRaw = fetched.branches;
    branchesTruncated = fetched.branchesTruncated;
  } catch (err) {
    logger.error('fetchCommitGraph failed', { repoId, err: String(err) });
    throw new HttpsError(
      'unavailable',
      'GitHub API request failed. Check your GitHub authorization and try again.',
    );
  }

  const payload = assembleGraph(branchesRaw);
  payload.truncated = payload.truncated || branchesTruncated;

  // ---- Best-effort cache write (mirror explainCommit) -----------------------
  try {
    await cacheRef.set({ payload, generatedAtMs: Date.now() });
  } catch (err) {
    logger.warn('graphCache write failed (best-effort)', {
      repoId,
      cacheKey,
      err: String(err),
    });
  }

  return { ...payload, cached: false };
}

/**
 * Dedupes per-branch histories into one commit set and attributes each commit
 * to a primary branch:
 *   1. every non-default branch (most recent tip first) claims the commits on
 *      its first-parent chain that the default branch's first-parent chain
 *      doesn't own;
 *   2. the default branch claims its own first-parent chain;
 *   3. leftovers (reachable only through second parents, e.g. merged-and-
 *      deleted branches) fall to the first branch whose history surfaced them.
 *
 * Exported for unit tests.
 */
export function assembleGraph(
  branchesRaw: GraphBranchRaw[],
): Omit<CommitGraphResult, 'cached'> {
  const bySha = new Map<string, GraphCommitRaw>();
  const seenOn = new Map<string, string>(); // sha → first branch that surfaced it
  const truncated = branchesRaw.some((b) => b.truncated);

  const defaultBranch = branchesRaw.find((b) => b.isDefault);
  // Surface order: default branch LAST so feature branches claim the leftovers
  // they surfaced before the trunk sweeps them up.
  const surfaceOrder = [
    ...branchesRaw.filter((b) => !b.isDefault),
    ...(defaultBranch ? [defaultBranch] : []),
  ];
  for (const b of surfaceOrder) {
    for (const c of b.commits) {
      if (!bySha.has(c.sha)) bySha.set(c.sha, c);
      if (!seenOn.has(c.sha)) seenOn.set(c.sha, b.name);
    }
  }

  // First-parent chain of a tip, restricted to the fetched window.
  const firstParentChain = (tipSha: string): string[] => {
    const chain: string[] = [];
    let cur: string | undefined = tipSha;
    while (cur && bySha.has(cur) && !chain.includes(cur)) {
      chain.push(cur);
      cur = bySha.get(cur)!.parents[0];
    }
    return chain;
  };

  const owner = new Map<string, string>(); // sha → primary branch
  const defaultChain = new Set(
    defaultBranch ? firstParentChain(defaultBranch.tipSha) : [],
  );
  const nonDefault = branchesRaw.filter((b) => !b.isDefault);
  for (const b of nonDefault) {
    for (const sha of firstParentChain(b.tipSha)) {
      if (!defaultChain.has(sha) && !owner.has(sha)) owner.set(sha, b.name);
    }
  }
  if (defaultBranch) {
    for (const sha of defaultChain) {
      if (!owner.has(sha)) owner.set(sha, defaultBranch.name);
    }
  }

  const commits: GraphCommit[] = [...bySha.values()]
    .map((c) => {
      const isMerge = c.parents.length >= 2;
      const fromMessage = MERGE_PR_RE.exec(c.message)?.[1];
      return {
        sha: c.sha,
        message: c.message,
        committedAt: c.committedAt,
        parents: c.parents,
        author: {
          login: c.authorLogin,
          name: c.authorName,
          avatarUrl: c.avatarUrl,
        },
        primaryBranch:
          owner.get(c.sha) ?? seenOn.get(c.sha) ?? defaultBranch?.name ?? '',
        isMerge,
        prNumber: isMerge
          ? fromMessage
            ? Number(fromMessage)
            : c.associatedPrNumber
          : null,
      };
    })
    .sort((a, b) => b.committedAt.localeCompare(a.committedAt));

  const branches: GraphBranch[] = branchesRaw.map((b) => ({
    name: b.name,
    tipSha: b.tipSha,
    isDefault: b.isDefault,
  }));

  return { commits, branches, truncated };
}
