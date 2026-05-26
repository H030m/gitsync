// breakdownTaskFlow — splits a goal into actionable subtasks using OpenAI
// structured outputs. Pre-generates Firestore taskIds before writing so we
// can translate the LLM's 0-based-index `dependsOn` into real taskIds in a
// single transaction.
//
// Detailed contract: ARCHITECTURE.md §5.1 + MEMORY.md 2026-05-26
// "dependsOn type contract".
import { logger } from 'firebase-functions/v2';
import { zodResponseFormat } from 'openai/helpers/zod';

import { db } from '../admin';
import { getOpenAI, MODELS } from '../config';
import { breakdownTaskSystem, breakdownTaskUser } from '../prompts/breakdownTask';
import { BreakdownOutputSchema, BreakdownOutput } from '../types';

export interface BreakdownTaskInput {
  repoId: string;
  goal: string;
  /** Firebase Auth UID of the requester, for `createdBy`. */
  requestedBy: string;
}

export interface BreakdownTaskResult {
  /** Final subtasks with REAL `taskId` strings (already written to Firestore). */
  subtasks: Array<{
    id: string;
    title: string;
    description: string;
    dependsOn: string[];
    estimatedHours: number;
  }>;
}

export async function breakdownTaskFlow(
  _input: BreakdownTaskInput,
): Promise<BreakdownTaskResult> {
  // TODO: implement Sprint 2 (see ARCHITECTURE.md §5.1 Step 1-6).
  //  - Step 1: fetchProjectContext (Firestore + GitHub recent commits)
  //  - Step 2: openai.chat.completions.parse with zodResponseFormat
  //  - Step 3: detectCycles (pure TS DFS), Step 3b: re-prompt on cycle
  //  - Step 4: pre-generate Firestore doc IDs
  //  - Step 5: translate `dependsOn` indices → taskIds
  //  - Step 6: transactional batch write + unlock `isBreakingDown`
  throw new Error('breakdownTaskFlow not implemented yet');
}

// ---- Helpers (exported so tests can unit-test them in isolation) -----------

/**
 * Returns the indices of every cycle in the dependency graph (DFS).
 * Empty array = no cycles.
 */
export function detectCycles(
  subtasks: Array<{ dependsOn: number[] }>,
): number[][] {
  const cycles: number[][] = [];
  const WHITE = 0,
    GRAY = 1,
    BLACK = 2;
  const color = new Array<number>(subtasks.length).fill(WHITE);
  const stack: number[] = [];

  function dfs(i: number) {
    color[i] = GRAY;
    stack.push(i);
    for (const dep of subtasks[i].dependsOn) {
      if (dep < 0 || dep >= subtasks.length) continue;
      if (color[dep] === GRAY) {
        cycles.push([...stack.slice(stack.indexOf(dep)), dep]);
      } else if (color[dep] === WHITE) {
        dfs(dep);
      }
    }
    color[i] = BLACK;
    stack.pop();
  }

  for (let i = 0; i < subtasks.length; i++) {
    if (color[i] === WHITE) dfs(i);
  }
  return cycles;
}

// Re-exports kept here so handler files have one short import:
export { BreakdownOutputSchema, getOpenAI, MODELS, breakdownTaskSystem, breakdownTaskUser, zodResponseFormat, db, logger };
export type { BreakdownOutput };
