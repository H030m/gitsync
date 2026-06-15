// Observation writer for the memory layer.
//
// Writes a single knowledge entry to `repos/{repoId}/observations/{autoId}`.
// Each observation is a short fact (1-3 sentences, ≤500 chars) with a category,
// source lineage, keyword tags, and a 1536-dim embedding for semantic search.
//
// BEST-EFFORT: `writeObservation` swallows all errors (logger.warn) and NEVER
// throws, so callers can fire-and-forget without risking the host flow.
import { logger } from 'firebase-functions/v2';
import { FieldValue } from 'firebase-admin/firestore';

import { db } from '../admin';
import { embedToFieldValue } from './embedding';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ObservationCategory =
  | 'architecture_decision'
  | 'convention'
  | 'blocker'
  | 'lesson'
  | 'team_insight'
  | 'project_state';

export interface WriteObservationInput {
  content: string;
  category: ObservationCategory;
  sourceFlow: string;
  sourceId?: string;
  tags?: string[];
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_CONTENT_CHARS = 500;

// ---------------------------------------------------------------------------
// writeObservation
// ---------------------------------------------------------------------------

/**
 * Write a single observation to Firestore. Embeds the content, writes the doc,
 * and returns the auto-generated doc ID. BEST-EFFORT — swallows all errors and
 * returns null on failure. Callers should `.catch(() => {})` or simply await
 * without checking the result.
 */
export async function writeObservation(
  repoId: string,
  input: WriteObservationInput,
): Promise<string | null> {
  try {
    const content = input.content.trim().slice(0, MAX_CONTENT_CHARS);
    if (!content) return null;

    const embedding = await embedToFieldValue(content);

    const doc = await db
      .collection(`apps/gitsync/repos/${repoId}/observations`)
      .add({
        content,
        category: input.category,
        sourceFlow: input.sourceFlow,
        sourceId: input.sourceId ?? null,
        tags: input.tags ?? [],
        embedding,
        promoted: false,
        repoId,
        createdAt: FieldValue.serverTimestamp(),
      });

    logger.info('writeObservation: created', {
      repoId,
      observationId: doc.id,
      category: input.category,
      sourceFlow: input.sourceFlow,
      chars: content.length,
    });

    return doc.id;
  } catch (err) {
    logger.warn('writeObservation failed (best-effort)', {
      repoId,
      sourceFlow: input.sourceFlow,
      err: String(err),
    });
    return null;
  }
}
