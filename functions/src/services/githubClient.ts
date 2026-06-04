// Wraps Octokit so every GitHub API call lives in one place
// (ARCHITECTURE.md §6.4).
//
// Any future GitHub interaction (create issue, get PR diff, etc.) belongs in
// this file — keep the rest of the codebase free of `@octokit/rest` imports.
import { Octokit } from '@octokit/rest';

export function getOctokit(userAccessToken: string): Octokit {
  return new Octokit({ auth: userAccessToken });
}

export interface RecentCommit {
  sha: string;
  message: string;
  authorLogin: string;
  authorName: string;
  authorEmail: string;
  url: string;
  committedAt: string;
}

export async function getRecentCommits(
  owner: string,
  repo: string,
  accessToken: string,
  limit = 20,
): Promise<RecentCommit[]> {
  const octokit = getOctokit(accessToken);
  const res = await octokit.repos.listCommits({
    owner,
    repo,
    per_page: limit,
  });
  return res.data.map((c) => ({
    sha: c.sha,
    message: c.commit.message,
    authorLogin: c.author?.login ?? '',
    authorName: c.commit.author?.name ?? '',
    authorEmail: c.commit.author?.email ?? '',
    url: c.html_url,
    committedAt: c.commit.author?.date ?? '',
  }));
}

export interface CommitDetail {
  sha: string;
  message: string;
  authorLogin: string;
  authorName: string;
  committedAt: string;
  files: string[];
  additions: number;
  deletions: number;
}

/**
 * Fetches a single commit (GET /repos/{owner}/{repo}/commits/{sha}) with its
 * message, author, changed file paths and line stats. Used by explainCommit's
 * fallback path when no Firestore commit doc exists (06-05 D2). All GitHub API
 * access stays in this file (ARCHITECTURE.md §6.4).
 */
export async function getCommit(
  owner: string,
  repo: string,
  accessToken: string,
  sha: string,
): Promise<CommitDetail> {
  const octokit = getOctokit(accessToken);
  const res = await octokit.repos.getCommit({ owner, repo, ref: sha });
  const data = res.data;
  return {
    sha: data.sha,
    message: data.commit.message,
    authorLogin: data.author?.login ?? '',
    authorName: data.commit.author?.name ?? '',
    committedAt: data.commit.author?.date ?? '',
    files: (data.files ?? []).map((f) => f.filename),
    additions: data.stats?.additions ?? 0,
    deletions: data.stats?.deletions ?? 0,
  };
}

// ---- Commit graph (branch topology) ----------------------------------------

export interface GraphCommitRaw {
  sha: string;
  message: string;
  committedAt: string; // ISO 8601
  parents: string[];
  authorLogin: string | null; // null when the commit email isn't a GitHub user
  authorName: string;
  avatarUrl: string | null;
  associatedPrNumber: number | null;
}

export interface GraphBranchRaw {
  name: string;
  tipSha: string;
  isDefault: boolean;
  /** History scoped to the since/until window, newest first. */
  commits: GraphCommitRaw[];
  /** True when the branch had more in-window commits than we fetched. */
  truncated: boolean;
}

/** Branch cap — the N most-recently-committed branches (+ default branch). */
const GRAPH_BRANCH_LIMIT = 20;
/** Per-branch history page size (no pagination beyond the first page). */
const GRAPH_HISTORY_LIMIT = 100;

// One round trip: every branch tip + its in-window history with parent SHAs,
// author avatar and the associated PR (squash/rebase merges have no
// "Merge pull request #N" message — associatedPullRequests still resolves
// them). See task research `github-api-commit-graph.md`.
const COMMIT_GRAPH_QUERY = `
  query ($owner: String!, $name: String!, $since: GitTimestamp, $until: GitTimestamp) {
    repository(owner: $owner, name: $name) {
      defaultBranchRef {
        name
        target { ...CommitHistory }
      }
      refs(refPrefix: "refs/heads/", first: ${GRAPH_BRANCH_LIMIT},
           orderBy: { field: TAG_COMMIT_DATE, direction: DESC }) {
        nodes {
          name
          target { ...CommitHistory }
        }
        pageInfo { hasNextPage }
      }
    }
  }
  fragment CommitHistory on GitObject {
    ... on Commit {
      oid
      history(since: $since, until: $until, first: ${GRAPH_HISTORY_LIMIT}) {
        nodes {
          oid
          message
          committedDate
          parents(first: 5) { nodes { oid } }
          author {
            avatarUrl
            name
            user { login }
          }
          associatedPullRequests(first: 1) { nodes { number } }
        }
        pageInfo { hasNextPage }
      }
    }
  }
`;

interface GraphQlCommitNode {
  oid: string;
  message: string;
  committedDate: string;
  parents: { nodes: Array<{ oid: string }> };
  author: {
    avatarUrl: string | null;
    name: string | null;
    user: { login: string } | null;
  } | null;
  associatedPullRequests: { nodes: Array<{ number: number }> };
}

interface GraphQlRefTarget {
  oid?: string;
  history?: {
    nodes: GraphQlCommitNode[];
    pageInfo: { hasNextPage: boolean };
  };
}

interface CommitGraphQueryResult {
  repository: {
    defaultBranchRef: { name: string; target: GraphQlRefTarget | null } | null;
    refs: {
      nodes: Array<{ name: string; target: GraphQlRefTarget | null }>;
      pageInfo: { hasNextPage: boolean };
    };
  } | null;
}

function toGraphCommitRaw(n: GraphQlCommitNode): GraphCommitRaw {
  return {
    sha: n.oid,
    message: n.message,
    committedAt: n.committedDate,
    parents: n.parents.nodes.map((p) => p.oid),
    authorLogin: n.author?.user?.login ?? null,
    authorName: n.author?.name ?? '',
    avatarUrl: n.author?.avatarUrl ?? null,
    associatedPrNumber: n.associatedPullRequests.nodes[0]?.number ?? null,
  };
}

/**
 * Fetches the branch-topology raw data (branch tips + per-branch in-window
 * history with parent SHAs) in a single GraphQL round trip. Dedupe/lane
 * attribution is the flow's job (`flows/getCommitGraph.ts`) — this stays a
 * pure fetch, like every other helper in this file.
 */
export async function fetchCommitGraph(
  owner: string,
  repo: string,
  accessToken: string,
  options: { since?: string; until?: string } = {},
): Promise<{
  branches: GraphBranchRaw[];
  defaultBranch: string | null;
  /** True when the repo has more branches than the cap. */
  branchesTruncated: boolean;
}> {
  const octokit = getOctokit(accessToken);
  const data = await octokit.graphql<CommitGraphQueryResult>(
    COMMIT_GRAPH_QUERY,
    {
      owner,
      name: repo,
      since: options.since ?? null,
      until: options.until ?? null,
    },
  );

  const repository = data.repository;
  if (!repository) {
    return { branches: [], defaultBranch: null, branchesTruncated: false };
  }
  const defaultBranch = repository.defaultBranchRef?.name ?? null;

  const toBranch = (
    name: string,
    target: GraphQlRefTarget | null,
  ): GraphBranchRaw => ({
    name,
    tipSha: target?.oid ?? '',
    isDefault: name === defaultBranch,
    commits: (target?.history?.nodes ?? []).map(toGraphCommitRaw),
    truncated: target?.history?.pageInfo.hasNextPage ?? false,
  });

  const branches: GraphBranchRaw[] = repository.refs.nodes
    .filter((ref) => ref.target?.history)
    .map((ref) => toBranch(ref.name, ref.target));

  // The branch cap is "20 most recently committed" — make sure the trunk every
  // lane forks from / merges to is always present even when it falls outside.
  const dbr = repository.defaultBranchRef;
  if (dbr?.target?.history && !branches.some((b) => b.name === dbr.name)) {
    branches.push(toBranch(dbr.name, dbr.target));
  }

  return {
    branches,
    defaultBranch,
    branchesTruncated: repository.refs.pageInfo.hasNextPage,
  };
}

export interface CreateIssueOptions {
  title: string;
  body: string;
}

/**
 * Creates a GitHub issue (POST /repos/{owner}/{repo}/issues) and returns the
 * created issue number + html url. Used by `onTaskCreated` to mirror a task as
 * an issue so commits/PRs can reference it via `#N`. All GitHub API access stays
 * in this file (ARCHITECTURE.md §6.4).
 */
export async function createIssue(
  owner: string,
  repo: string,
  accessToken: string,
  options: CreateIssueOptions,
): Promise<{ number: number; htmlUrl: string }> {
  const octokit = getOctokit(accessToken);
  const res = await octokit.issues.create({
    owner,
    repo,
    title: options.title,
    body: options.body,
  });
  return { number: res.data.number, htmlUrl: res.data.html_url };
}

export interface RepoAccess {
  githubRepoId: number;
  defaultBranch: string;
  // GitHub permission flags on the repo for the authenticated user.
  // The caller decides whether push/admin is sufficient.
  permissions: {
    admin: boolean;
    push: boolean;
    pull: boolean;
  };
}

/**
 * Verifies the repo exists and is visible to the token holder, returning its
 * id, default branch, and the caller's permission flags. Throws (via Octokit)
 * with `status === 404` when the repo doesn't exist or isn't visible.
 */
export async function verifyRepoAccess(
  owner: string,
  repo: string,
  accessToken: string,
): Promise<RepoAccess> {
  const octokit = getOctokit(accessToken);
  const res = await octokit.repos.get({ owner, repo });
  const perms = res.data.permissions;
  return {
    githubRepoId: res.data.id,
    defaultBranch: res.data.default_branch,
    permissions: {
      admin: perms?.admin ?? false,
      push: perms?.push ?? false,
      pull: perms?.pull ?? false,
    },
  };
}

export interface RegisterWebhookOptions {
  url: string;
  secret: string;
  events: string[];
}

/**
 * Registers a `web` webhook on the repo (POST /repos/{owner}/{repo}/hooks) and
 * returns the created hook id. All GitHub API access stays in this file
 * (ARCHITECTURE.md §6.4).
 */
export async function registerWebhook(
  owner: string,
  repo: string,
  accessToken: string,
  options: RegisterWebhookOptions,
): Promise<number> {
  const octokit = getOctokit(accessToken);
  const res = await octokit.repos.createWebhook({
    owner,
    repo,
    name: 'web',
    active: true,
    events: options.events,
    config: {
      url: options.url,
      secret: options.secret,
      content_type: 'json',
    },
  });
  return res.data.id;
}

/**
 * Deletes a webhook on the repo (DELETE /repos/{owner}/{repo}/hooks/{hook_id}).
 * The inverse of {@link registerWebhook}; requires admin/push permission, same
 * as registration. All GitHub API access stays in this file (ARCHITECTURE.md §6.4).
 */
export async function deleteWebhook(
  owner: string,
  repo: string,
  accessToken: string,
  hookId: number,
): Promise<void> {
  const octokit = getOctokit(accessToken);
  await octokit.repos.deleteWebhook({ owner, repo, hook_id: hookId });
}
