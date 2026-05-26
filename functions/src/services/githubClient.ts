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
