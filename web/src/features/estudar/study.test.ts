import { describe, expect, it } from "vitest";
import type { Review } from "../../domain/types";
import {
  buildReviewQueue,
  countPracticedToday,
  pagesFromText,
  splitQuestionBody,
  DEFAULT_DAILY_NEW_LIMIT,
} from "./study";

const NOW = new Date("2026-08-24T10:00:00.000Z");

function review(key: string, overrides: Partial<Review> = {}): Review {
  return {
    key,
    sourceNodeID: null,
    deckID: null,
    dueAt: "2026-08-24T00:00:00.000Z",
    intervalDays: 1,
    easeFactor: 2.5,
    repetitions: 1,
    lastRating: "good",
    lastReviewedAt: null,
    firstReviewedAt: null,
    ...overrides,
  };
}

function card(sourceKey: string) {
  return { sourceKey, front: `F ${sourceKey}`, back: `B ${sourceKey}` };
}

describe("pagesFromText", () => {
  it("splits note bodies on \\n---\\n separators", () => {
    expect(pagesFromText("um\n---\ndois\n---\ntrês")).toEqual(["um", "dois", "três"]);
  });

  it("returns the whole text as a single page without separators", () => {
    expect(pagesFromText("texto único")).toEqual(["texto único"]);
  });

  it("keeps surrounding newlines in segments and ignores non-newline dashes", () => {
    expect(pagesFromText("a\n\n---\n\nb")).toEqual(["a\n", "\nb"]);
    expect(pagesFromText("a --- b")).toEqual(["a --- b"]);
    expect(pagesFromText("")).toEqual([""]);
  });
});

describe("buildReviewQueue", () => {
  const identities = new Map([
    ["a:0", "id-1"],
    ["a:1", "id-2"],
    ["b:0", "id-3"],
    ["b:1", "id-1"],
    ["c:0", "id-4"],
  ]);

  it("orders due cards first, then new cards", () => {
    const cards = [card("c:0"), card("a:1"), card("a:0")];
    const reviews = [review("id-2", { dueAt: "2026-08-24T09:00:00.000Z" })];
    const queue = buildReviewQueue(cards, reviews, identities, NOW);
    expect(queue.map((entry) => entry.sourceKey)).toEqual(["a:1", "c:0", "a:0"]);
    expect(queue.map((entry) => entry.status)).toEqual(["due", "new", "new"]);
  });

  it("excludes reviewed cards that are not yet due", () => {
    const reviews = [review("id-2", { dueAt: "2026-08-30T00:00:00.000Z" })];
    const queue = buildReviewQueue([card("a:0"), card("a:1")], reviews, identities, NOW);
    expect(queue.map((entry) => entry.sourceKey)).toEqual(["a:0"]);
  });

  it("caps new cards by the remaining daily limit after cards introduced today", () => {
    const earlierReviews = [
      review("id-4", { firstReviewedAt: "2026-08-24T08:00:00.000Z", lastReviewedAt: "2026-08-24T08:00:00.000Z" }),
      review("id-9", { firstReviewedAt: "2026-08-23T08:00:00.000Z" }),
    ];
    const cards = [card("a:0"), card("a:1"), card("b:0"), card("c:0")];
    const queue = buildQueueWithLimit(cards, earlierReviews, 3);
    expect(queue.filter((entry) => entry.status === "new")).toHaveLength(2);
  });

  it(`defaults to a daily limit of ${DEFAULT_DAILY_NEW_LIMIT}`, () => {
    const manyCards = Array.from({ length: 30 }, (_, index) => card(`d:${index}`));
    const manyIdentities = new Map(manyCards.map((entry) => [entry.sourceKey, `did-${entry.sourceKey}`]));
    expect(buildReviewQueue(manyCards, [], manyIdentities, NOW)).toHaveLength(20);
    expect(buildReviewQueue(manyCards, [], manyIdentities, NOW, 5)).toHaveLength(5);
  });

  it("deduplicates identical cards across decks via identity", () => {
    const queue = buildReviewQueue([card("a:0"), card("b:1")], [], identities, NOW);
    expect(queue.map((entry) => entry.sourceKey)).toEqual(["a:0"]);
  });

  it("skips cards missing from the identity map", () => {
    expect(buildReviewQueue([card("zzz:9")], [], identities, NOW)).toEqual([]);
  });
});

function buildQueueWithLimit(
  cards: Parameters<typeof buildReviewQueue>[0],
  reviews: readonly Review[],
  limit: number,
) {
  return buildReviewQueue(cards, reviews, identitiesFor(cards), NOW, limit);
}

function identitiesFor(cards: readonly { sourceKey: string }[]) {
  const map = new Map<string, string>();
  for (const entry of cards) map.set(entry.sourceKey, entry.sourceKey.replace(":", "-"));
  return map;
}

describe("countPracticedToday", () => {
  it("counts only reviews with lastReviewedAt today, once per key", () => {
    const reviews = [
      review("k1", { lastReviewedAt: "2026-08-24T09:30:00.000Z" }),
      review("k1", { lastReviewedAt: "2026-08-24T11:30:00.000Z" }),
      review("k2", { lastReviewedAt: "2026-08-23T09:30:00.000Z" }),
      review("k3", { lastReviewedAt: "2026-08-24T23:59:59.999Z" }),
      review("k4"),
    ];
    expect(countPracticedToday(reviews, NOW)).toBe(2);
  });

  it("treats invalid or missing dates as not practiced", () => {
    const reviews = [
      review("k1", { lastReviewedAt: "não é data" }),
      review("k2", { lastReviewedAt: null }),
    ];
    expect(countPracticedToday(reviews, NOW)).toBe(0);
    expect(countPracticedToday([], NOW)).toBe(0);
  });
});

describe("splitQuestionBody", () => {
  it("separates the prompt from the Gabarito section", () => {
    const split = splitQuestionBody("Qual é a capital?\nGabarito: Brasília\nComentário extra.");
    expect(split.prompt).toBe("Qual é a capital?");
    expect(split.answer).toBe("Gabarito: Brasília\nComentário extra.");
  });

  it("returns the body untouched when there is no Gabarito line", () => {
    const split = splitQuestionBody("Somente a pergunta.");
    expect(split.prompt).toBe("Somente a pergunta.");
    expect(split.answer).toBeNull();
  });

  it("detects indented Gabarito lines and keeps later occurrences in the answer", () => {
    const split = splitQuestionBody("Pergunta\n  Gabarito: A\nNota: Gabarito: repetido");
    expect(split.prompt).toBe("Pergunta");
    expect(split.answer).toBe("Gabarito: A\nNota: Gabarito: repetido");
  });
});
