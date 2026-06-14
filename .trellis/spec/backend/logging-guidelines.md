# Logging Guidelines (Cloud Functions)

> Use the Firebase structured logger, never `console.log`.

---

## Logger

```ts
import { logger } from 'firebase-functions/v2';
```

Logs surface in the Firebase console / Cloud Logging with structured fields. Pass context as
a second-argument object, not via string interpolation:

```ts
logger.info('Skipping commit embedding (filter hit)', { sha: event.params.sha });
logger.info('onCommitCreated stub', { ids: event.params });
logger.error('breakdownTaskFlow failed', { repoId, err });
```

---

## Levels

| Level | When |
|---|---|
| `logger.debug` | Verbose local-only detail; off by default in prod |
| `logger.info` | Normal milestones: flow steps, "already processed, skipping", stub markers |
| `logger.warn` | Recoverable anomalies (e.g. external call failed, falling back to null) |
| `logger.error` | Unexpected failures, caught exceptions you can't recover from |

The AI-flow step logging style (`logger.info('Step 1: fetch project context')`) from
[`COURSE_METHODS.md §8.6`](../../../docs/COURSE_METHODS.md) is the expected pattern inside `flows/`.

### Agentic-loop per-round observability (counts only)

For agentic function-calling flows (e.g. `incrementalBreakdown` in `flows/breakdownTask.ts`),
log enough to reconstruct what the agent did each round WITHOUT dumping content — so cloud logs
answer "did the agent call the explore tools and what came back?". Established field shapes:

- **Per tool call** — one `logger.info` per `tool_call` the model makes, at the dispatch site:
  `{ message: 'incrementalBreakdown: tool call', repoId, round, tool, args: <compact summary>, resultCount }`.
  `args` carries only the meaningful bits (`{ query, limit }`, `{ status, hasCursor }`), never full
  content; `resultCount` is the array/page length the tool returned.
- **Terminator submit** — `{ message: 'incrementalBreakdown: submit', repoId, round, subtaskCount,
  totalDependsOnNew, totalDependsOnExisting }` (sum the dep-array lengths) so "did new tasks depend
  on existing ones" is directly visible.
- **Tool success path** — read tools log their own `count` on success too
  (`listExistingTaskTitles: page` → `{ repoId, count, hasMore }`; `searchExistingTasks: results` →
  `{ repoId, query, count }`), keeping the existing failure `logger.warn`.

These logs are **best-effort**: counts/summaries only (never task lists, descriptions, or commit
content), wrapped so they can never throw or change control flow.

---

## What to log

- Trigger entry/skip decisions (idempotency hit, filter hit).
- Flow step boundaries and round counts in agentic loops.
- External call failures (with the identifier, not the whole payload).

## What NOT to log

- **Never log secrets**: `OPENAI_API_KEY`, `DISCORD_INGEST_SECRET`, `webhookSecret`,
  `githubAccessToken`.
- Don't dump full request bodies or large payloads — log the id (`sha`, `messageId`, `repoId`).
- Don't log user PII beyond the ids already in the schema.
