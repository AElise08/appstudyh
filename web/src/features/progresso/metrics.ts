import type { CanvasNode, Review, Task, Workspace } from "../../domain/types";
import { parseFlashcards } from "../../domain/flashcards";

export interface FlashcardRef {
  /** Stable source key: `${artifactID}:${cardIndex}`. */
  sourceKey: string;
  front: string;
  back: string;
}

export type NextAction = "flashcards" | "task" | "material";

/**
 * Parses every flashcard artifact into flat card references. Synchronous; the
 * (async) identity hashes are joined later through a precomputed map.
 */
export function collectFlashcardRefs(workspace: Workspace): FlashcardRef[] {
  const refs: FlashcardRef[] = [];
  for (const artifact of workspace.studyArtifacts ?? []) {
    if (artifact.kind !== "flashcards") continue;
    const cards = parseFlashcards(artifact.body);
    if (cards === null) continue;
    cards.forEach((card, index) => {
      refs.push({ sourceKey: `${artifact.id}:${index}`, front: card.front, back: card.back });
    });
  }
  return refs;
}

function endOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 999);
}

/**
 * Counts distinct flashcards due by end of `now`'s day. Cards without a review
 * are immediately due; cards join reviews through the precomputed
 * sourceKey -> identity map. Identities missing from the map are skipped.
 */
export function dueTodayCount(
  refs: readonly FlashcardRef[],
  identities: ReadonlyMap<string, string>,
  reviews: readonly Review[],
  now: Date,
): number {
  const limit = endOfDay(now).getTime();
  const reviewByKey = new Map(reviews.map((review) => [review.key, review]));
  const dueIdentities = new Set<string>();

  for (const ref of refs) {
    const identity = identities.get(ref.sourceKey);
    if (identity === undefined || dueIdentities.has(identity)) continue;
    const review = reviewByKey.get(identity);
    const dueAt = review !== undefined ? Date.parse(review.dueAt) : Number.NEGATIVE_INFINITY;
    if (Number.isNaN(dueAt) || dueAt <= limit) dueIdentities.add(identity);
  }

  return dueIdentities.size;
}

const PRIORITY_RANK: Record<Task["priority"], number> = { high: 0, normal: 1, low: 2 };

/** Open tasks sorted by priority then due date. */
export function openTasks(tasks: readonly Task[]): Task[] {
  return tasks
    .filter((task) => !task.isCompleted)
    .sort(
      (a, b) =>
        PRIORITY_RANK[a.priority] - PRIORITY_RANK[b.priority] ||
        a.dueDate.localeCompare(b.dueDate),
    );
}

/** Nearest valid exam or presentation date, or null. */
export function nearestDeadline(workspace: Workspace): string | null {
  const dates = [workspace.examDate, workspace.presentationDate]
    .filter((date): date is string => typeof date === "string" && !Number.isNaN(Date.parse(date)))
    .sort();
  return dates[0] ?? null;
}

/** Pages estimate from the note body: one unit per non-empty paragraph. */
export function estimateUnitCount(node: CanvasNode): number {
  const paragraphs = node.noteBody
    .split(/\n{2,}/)
    .map((part) => part.trim())
    .filter((part) => part.length > 0).length;
  return Math.max(1, paragraphs);
}

/** Visited coverage clamped to 0..1 against the estimated unit count. */
export function coverageRatio(node: CanvasNode): number {
  const visited = node.visitedUnitIndices?.length ?? 0;
  const total = estimateUnitCount(node);
  if (total <= 0) return 0;
  return Math.min(1, visited / total);
}

/** Priority order for the primary action: due cards > open task > material. */
export function nextAction(input: {
  refs: readonly FlashcardRef[];
  identities: ReadonlyMap<string, string>;
  reviews: readonly Review[];
  tasks: readonly Task[];
  now: Date;
}): NextAction {
  if (dueTodayCount(input.refs, input.identities, input.reviews, input.now) > 0) return "flashcards";
  if (openTasks(input.tasks).length > 0) return "task";
  return "material";
}
