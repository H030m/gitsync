// generateHandoffFlow — produces an AI handoff document for the engineer picking
// up `taskId`, grounded in the REAL project signals behind its now-finished
// prerequisites: their commits, the Discord discussion, and the team roster.
// See ARCHITECTURE.md §5.3 and prd.md (06-06-rich-task-cards-ai-handoff).
//
// Design: like explainCommit / discordDailyDigest, this pre-gathers context
// deterministically and makes ONE OpenAI call (no agentic tool loop). That keeps
// it cheap and predictable enough to run best-effort from onTaskUpdated when a
// downstream task becomes ready. The result is cached on the task doc
// (`handoffDoc` + `handoffGeneratedAt`); the manual callable passes force=true to
// always regenerate, the auto trigger passes force=false to skip if one exists.
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';

import { db } from '../admin';
import { getOpenAI, MODELS } from '../config';
import { readTeamState } from '../tools/assignTools';
import { searchDiscordMessages } from '../tools/discordSearch';
import {
  generateHandoffSystem,
  generateHandoffContext,
} from '../prompts/generateHandoff';

export interface GenerateHandoffInput {
  repoId: string;
  /** The task being handed TO (its prerequisites just finished). */
  taskId: string;
  /** Regenerate even when the task already has a handoffDoc. */
  force?: boolean;
}

export interface GenerateHandoffResult {
  handoffMarkdown: string;
  cached: boolean;
}

/** Caps so the prompt stays bounded regardless of repo size. */
const COMMITS_PER_PREREQ = 6;
const MAX_COMMITS = 15;
const MAX_DISCORD_MESSAGES = 20;

export async function generateHandoffFlow(
  input: GenerateHandoffInput,
): Promise<GenerateHandoffResult> {
  const { repoId, taskId, force = false } = input;

  const taskRef = db.doc(`apps/gitsync/repos/${repoId}/tasks/${taskId}`);
  const taskSnap = await taskRef.get();
  if (!taskSnap.exists) {
    throw new HttpsError('not-found', 'task not found');
  }
  const task = taskSnap.data() ?? {};

  // Cache: don't regenerate unless asked (the auto trigger relies on this to
  // avoid redoing work every time another prerequisite lands).
  const existing = task.handoffDoc as string | undefined;
  if (existing && !force) {
    return { handoffMarkdown: existing, cached: true };
  }

  const dependsOn = (task.dependsOn as string[] | undefined) ?? [];

  // ---- Prerequisites (the finished upstream tasks) -------------------------
  const prerequisites = (
    await Promise.all(
      dependsOn.map(async (id) => {
        try {
          const s = await db
            .doc(`apps/gitsync/repos/${repoId}/tasks/${id}`)
            .get();
          if (!s.exists) return null;
          const d = s.data() ?? {};
          return {
            title: (d.title as string | undefined) ?? '',
            description: (d.description as string | undefined) ?? '',
            status: (d.status as string | undefined) ?? '',
          };
        } catch {
          return null;
        }
      }),
    )
  ).filter((p): p is NonNullable<typeof p> => p !== null);

  // ---- Commits linked to the prerequisites (and this task) -----------------
  // Commits carry `linkedTaskIds` (parsed from `#N` refs by onCommitCreated).
  const commitIds = [...dependsOn, taskId];
  const seenSha = new Set<string>();
  const commits: Array<{
    sha: string;
    subject: string;
    aiSummary: string | null;
    author: string;
    filesChanged: number;
  }> = [];
  for (const id of commitIds) {
    if (commits.length >= MAX_COMMITS) break;
    try {
      const snap = await db
        .collection(`apps/gitsync/repos/${repoId}/commits`)
        .where('linkedTaskIds', 'array-contains', id)
        .orderBy('committedAt', 'desc')
        .limit(COMMITS_PER_PREREQ)
        .get();
      for (const doc of snap.docs) {
        if (seenSha.has(doc.id) || commits.length >= MAX_COMMITS) continue;
        seenSha.add(doc.id);
        const c = doc.data() ?? {};
        const author = (c.author as Record<string, unknown> | undefined) ?? {};
        commits.push({
          sha: doc.id.slice(0, 7),
          subject: ((c.message as string | undefined) ?? '').split('\n')[0],
          aiSummary: (c.aiSummary as string | undefined) ?? null,
          author:
            (author.name as string | undefined) ??
            (author.login as string | undefined) ??
            'unknown',
          filesChanged: ((c.filesChanged as string[] | undefined) ?? []).length,
        });
      }
    } catch (err) {
      // array-contains + orderBy may need a composite index that isn't deployed
      // — degrade gracefully rather than failing the whole handoff (Rule D).
      logger.warn('generateHandoff: commit query failed (best-effort)', {
        repoId,
        taskId: id,
        err: String(err),
      });
    }
  }

  // ---- Discord discussion around this work ---------------------------------
  const query = [
    task.title as string | undefined,
    ...prerequisites.map((p) => p.title),
  ]
    .filter(Boolean)
    .join(' ');
  let discord: Array<{ author: string; content: string }> = [];
  try {
    const snippets = await searchDiscordMessages(repoId, query);
    discord = snippets
      .flatMap((s) => s.messages)
      .map((m) => ({ author: m.authorName, content: m.content }))
      .slice(0, MAX_DISCORD_MESSAGES);
  } catch (err) {
    logger.warn('generateHandoff: discord search failed (best-effort)', {
      repoId,
      err: String(err),
    });
  }

  // ---- Team roster (to name people) ----------------------------------------
  let roster: Array<{ name: string | null; githubLogin: string | null }> = [];
  try {
    roster = (await readTeamState(repoId)).map((m) => ({
      name: m.name,
      githubLogin: m.githubLogin,
    }));
  } catch (err) {
    logger.warn('generateHandoff: roster read failed (best-effort)', {
      repoId,
      err: String(err),
    });
  }

  // ---- One OpenAI call ------------------------------------------------------
  const completion = await getOpenAI().chat.completions.create({
    model: MODELS.fast,
    messages: [
      { role: 'system', content: generateHandoffSystem },
      {
        role: 'user',
        content: generateHandoffContext({
          task: {
            title: (task.title as string | undefined) ?? '',
            description: (task.description as string | undefined) ?? '',
            acceptanceCriteria:
              (task.acceptanceCriteria as string[] | undefined) ?? [],
          },
          prerequisites,
          commits,
          discord,
          roster,
        }),
      },
    ],
  });
  const markdown = completion.choices[0]?.message?.content?.trim() ?? '';
  if (!markdown) {
    throw new HttpsError('internal', 'OpenAI returned an empty handoff');
  }

  // ---- Persist on the task doc (best-effort) -------------------------------
  try {
    await taskRef.update({
      handoffDoc: markdown,
      handoffGeneratedAt: FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.warn('generateHandoff: write-back failed (best-effort)', {
      repoId,
      taskId,
      err: String(err),
    });
  }

  logger.info('generateHandoff: generated', { repoId, taskId });
  return { handoffMarkdown: markdown, cached: false };
}
