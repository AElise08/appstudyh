import { describe, expect, it } from "vitest";
import { cardIdentity, normalizeFlashcardText, parseFlashcards, reviewCard } from "./flashcards";
import { createReview } from "./create";

const now = new Date("2026-08-24T12:00:00.000Z");
const day = 86_400_000;

describe("parseFlashcards", () => {
  it("parses plain blocks into trimmed cards", () => {
    const cards = parseFlashcards("Frente: Capital do Brasil?\nVerso: Brasília\n\nFrente: 2+2\nVerso: 4");
    expect(cards).toEqual([
      { front: "Capital do Brasil?", back: "Brasília" },
      { front: "2+2", back: "4" },
    ]);
  });

  it("accepts bold markers and any label casing", () => {
    expect(parseFlashcards("**Frente:** Pergunta\n**Verso:** Resposta")).toEqual([
      { front: "Pergunta", back: "Resposta" },
    ]);
    expect(parseFlashcards("FRENTE: A\nVERSO: B")).toEqual([{ front: "A", back: "B" }]);
    expect(parseFlashcards("frente: a\nverso: b")).toEqual([{ front: "a", back: "b" }]);
  });

  it("rejects incomplete or empty cards and returns null when none are valid", () => {
    expect(parseFlashcards("Frente: só a pergunta")).toBeNull();
    expect(parseFlashcards("Verso: só a resposta")).toBeNull();
    expect(parseFlashcards("Frente: A\nVerso:   \n\nFrente:\nVerso: B")).toBeNull();
    expect(parseFlashcards("sem cartões aqui")).toBeNull();
    expect(parseFlashcards("")).toBeNull();
  });
});

describe("cardIdentity", () => {
  it("is stable across case, accent, and whitespace variants", async () => {
    const base = await cardIdentity("Capital do Brasil?", "Brasília");
    expect(base).toMatch(/^[0-9a-f]{64}$/);
    expect(await cardIdentity("CAPITAL DO BRASIL?", "BRASÍLIA")).toBe(base);
    expect(await cardIdentity("  capital   do brasil? ", " brasilia ")).toBe(base);
    expect(await cardIdentity("Café", "com leite")).toBe(await cardIdentity("cafe", "COM LEITE"));
  });

  it("normalizes '  Café   COM leite ' exactly like the Swift normalization", () => {
    expect(normalizeFlashcardText("  Café   COM leite ")).toBe("cafe com leite");
  });

  it("differs for different cards and for swapped sides", async () => {
    expect(await cardIdentity("A", "B")).not.toBe(await cardIdentity("A", "C"));
    expect(await cardIdentity("A", "B")).not.toBe(await cardIdentity("B", "A"));
  });
});

describe("reviewCard SRS transitions (exact Swift values)", () => {
  it("hard resets repetitions to 0 with interval 1 and an ease floor of 1.3", () => {
    const current = createReview("k", null, now);
    current.repetitions = 4;
    current.intervalDays = 10;
    current.easeFactor = 1.4;
    const rated = reviewCard(current, "hard", now);
    expect(rated).toMatchObject({ repetitions: 0, intervalDays: 1, easeFactor: 1.3, lastRating: "hard" });
    expect(rated.dueAt).toBe(new Date(now.getTime() + day).toISOString());
    expect(reviewCard({ ...current, easeFactor: 1.45 }, "hard", now).easeFactor).toBe(1.3);
    // The input review is not mutated.
    expect(current.repetitions).toBe(4);
  });

  it("good uses 1 day first, then max(2, prev*ease)", () => {
    const first = reviewCard(undefined, "good", now);
    expect(first).toMatchObject({
      repetitions: 1,
      intervalDays: 1,
      easeFactor: 2.5,
      dueAt: new Date(now.getTime() + day).toISOString(),
      firstReviewedAt: now.toISOString(),
      lastReviewedAt: now.toISOString(),
    });
    const second = reviewCard(first, "good", now);
    expect(second).toMatchObject({ repetitions: 2, intervalDays: 2.5 });
    expect(second.dueAt).toBe(new Date(now.getTime() + 2.5 * day).toISOString());
  });

  it("easy starts at 4 days with ease +0.15 applied before the repeated interval", () => {
    const first = reviewCard(undefined, "easy", now);
    expect(first).toMatchObject({
      repetitions: 1,
      intervalDays: 4,
      easeFactor: 2.65,
      dueAt: new Date(now.getTime() + 4 * day).toISOString(),
    });
    const second = reviewCard(first, "easy", now);
    expect(second.repetitions).toBe(2);
    expect(second.easeFactor).toBeCloseTo(2.8);
    expect(second.intervalDays).toBeCloseTo(4 * 2.8 * 1.3);
    expect(second.firstReviewedAt).toBe(first.firstReviewedAt);
  });

  it("keeps deck identity while scheduling", () => {
    const sourceID = "11111111-2222-3333-4444-555555555555";
    const deckID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    const current = { ...createReview("card", sourceID, now), deckID };
    const rated = reviewCard(current, "good", new Date(now.getTime() + day));
    expect(rated.key).toBe("card");
    expect(rated.sourceNodeID).toBe(sourceID);
    expect(rated.deckID).toBe(deckID);
  });
});
