import { createReview } from "./create";
import type { Review, ReviewRating } from "./types";

export interface Flashcard {
  front: string;
  back: string;
}

export function normalizeFlashcardText(text: string): string {
  return text
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLocaleLowerCase("pt-BR")
    .replace(/\s+/gu, " ")
    .trim();
}

/** SHA-256 hex of normalized front + U+001F + normalized back. */
export async function cardIdentity(front: string, back: string): Promise<string> {
  const canonical = `${normalizeFlashcardText(front)}\u001f${normalizeFlashcardText(back)}`;
  const digest = await globalThis.crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/**
 * Parses "Frente:"/"Verso:" blocks (case-insensitive, optional ** bold
 * markers). Incomplete or empty cards are rejected; returns null when no valid
 * card exists.
 */
export function parseFlashcards(text: string): Flashcard[] | null {
  const block =
    /\*{0,2}Frente:\*{0,2}[^\S\n]*(.*?)[^\S\n]*\*{0,2}Verso:\*{0,2}[^\S\n]*(.*?)[^\S\n]*(?=\n[^\S\n]*\*{0,2}Frente:|$)/gis;
  const cards: Flashcard[] = [];
  for (const match of text.matchAll(block)) {
    const front = (match[1] ?? "").trim();
    const back = (match[2] ?? "").trim();
    if (front.length > 0 && back.length > 0) cards.push({ front, back });
  }
  return cards.length === 0 ? null : cards;
}

/**
 * Applies the exact Swift SRS transitions:
 * - hard: repetitions=0, interval=1 day, ease-0.2 floored at 1.3
 * - good: repetitions+1, interval first=1 else max(2, prev*ease)
 * - easy: repetitions+1, ease+0.15, interval first=4 else max(4, prev*ease*1.3)
 */
export function reviewCard(review: Review | undefined, rating: ReviewRating, now: Date): Review {
  const current: Review =
    review ?? createReview("", null, now);

  let intervalDays: number;
  if (rating === "hard") {
    intervalDays = 1;
  } else if (rating === "good") {
    intervalDays = current.repetitions <= 0 ? 1 : Math.max(2, current.intervalDays * current.easeFactor);
  } else {
    intervalDays =
      current.repetitions <= 0 ? 4 : Math.max(4, current.intervalDays * (current.easeFactor + 0.15) * 1.3);
  }

  const easeFactor =
    rating === "hard"
      ? Math.max(1.3, current.easeFactor - 0.2)
      : rating === "easy"
        ? current.easeFactor + 0.15
        : current.easeFactor;

  const reviewedAt = now.toISOString();
  return {
    ...current,
    repetitions: rating === "hard" ? 0 : current.repetitions + 1,
    intervalDays,
    easeFactor,
    lastRating: rating,
    lastReviewedAt: reviewedAt,
    firstReviewedAt: current.firstReviewedAt ?? reviewedAt,
    dueAt: new Date(now.getTime() + intervalDays * 86_400_000).toISOString(),
  };
}
