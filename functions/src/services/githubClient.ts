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
