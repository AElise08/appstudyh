import type { Review } from "../../domain/types";

export const DEFAULT_DAILY_NEW_LIMIT = 20;

export interface QueueCardInput {
  /** "deckID:index" reference into the workspace artifacts. */
  sourceKey: string;
  deckID?: string | null;
  sourceNodeID?: string | null;
  front: string;
  back: string;
}

export interface QueueCard extends QueueCardInput {
  identity: string;
  status: "due" | "new";
}

/** Splits a note body into reader pages on "\n---\n" separators. */
export function pagesFromText(text: string): string[] {
  return text.split(/\n---\n/);
}

function startOfDay(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

function isSameDay(iso: string | null | undefined, now: Date): boolean {
  if (!iso) return false;
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return false;
  return startOfDay(parsed) === startOfDay(now);
}

/**
 * Builds a review session queue: due cards first, then brand-new cards capped
 * by the remaining global daily limit. The limit counts distinct identities
 * first introduced today (approximated by `firstReviewedAt` == today), so
 * cards already studied earlier today reduce today's new-card budget.
 */
export function buildReviewQueue(
  cards: readonly QueueCardInput[],
  reviews: readonly Review[],
  identityMap: ReadonlyMap<string, string>,
  now: Date,
  dailyLimit: number = DEFAULT_DAILY_NEW_LIMIT,
): QueueCard[] {
  const reviewsByIdentity = new Map<string, Review>();
  const introducedTodayKeys = new Set<string>();
  for (const review of reviews) {
    reviewsByIdentity.set(review.key, review);
    if (isSameDay(review.firstReviewedAt, now)) introducedTodayKeys.add(review.key);
  }

  const seenIdentities = new Set<string>();
  const due: QueueCard[] = [];
  const fresh: QueueCard[] = [];
  for (const card of cards) {
    const identity = identityMap.get(card.sourceKey);
    if (identity === undefined || seenIdentities.has(identity)) continue;
    seenIdentities.add(identity);
    const review = reviewsByIdentity.get(identity);
    if (review === undefined) {
      fresh.push({ ...card, identity, status: "new" });
      continue;
    }
    const dueAt = new Date(review.dueAt);
    if (!Number.isNaN(dueAt.getTime()) && dueAt.getTime() <= now.getTime()) {
      due.push({ ...card, identity, status: "due" });
    }
  }

  const remainingNew = Math.max(0, dailyLimit - introducedTodayKeys.size);
  return [...due, ...fresh.slice(0, remainingNew)];
}

/** Counts distinct cards reviewed today (unique review keys, `lastReviewedAt` == today). */
export function countPracticedToday(reviews: readonly Review[], now: Date): number {
  const seen = new Set<string>();
  let count = 0;
  for (const review of reviews) {
    if (seen.has(review.key)) continue;
    seen.add(review.key);
    if (isSameDay(review.lastReviewedAt, now)) count += 1;
  }
  return count;
}

export interface QuestionSplit {
  /** Question body with the "Gabarito:" section removed. */
  prompt: string;
  /** Everything from the first "Gabarito:" line onward, or null when absent. */
  answer: string | null;
}

/** Strips the answer-key section (lines starting with "Gabarito:") for hidden-answer rendering. */
export function splitQuestionBody(body: string): QuestionSplit {
  const lines = body.split("\n");
  const promptLines: string[] = [];
  const answerLines: string[] = [];
  let collectingAnswer = false;
  for (const line of lines) {
    if (!collectingAnswer && line.trimStart().startsWith("Gabarito:")) {
      collectingAnswer = true;
    }
    (collectingAnswer ? answerLines : promptLines).push(line);
  }
  return {
    prompt: promptLines.join("\n").trim(),
    answer: collectingAnswer ? answerLines.join("\n").trim() : null,
  };
}
