import { describe, expect, it } from "vitest";
import type { CanvasNode, Artifact, Review, Task, Workspace } from "../../domain/types";
import { createTask } from "../../domain/create";
import {
  collectFlashcardRefs,
  coverageRatio,
  dueTodayCount,
  estimateUnitCount,
  nearestDeadline,
  nextAction,
  openTasks,
} from "./metrics";

function flashcardsArtifact(id: string, body: string): Artifact {
  return { id, kind: "flashcards", body, createdAt: "2026-01-01T00:00:00.000Z" };
}

const NOW = new Date("2026-08-24T10:00:00.000Z");

function review(key: string, dueAt: string): Review {
  return {
    key,
    sourceNodeID: null,
    deckID: null,
    dueAt,
    intervalDays: 1,
    easeFactor: 2.5,
    repetitions: 1,
    lastRating: "good",
    lastReviewedAt: "2026-08-20T00:00:00.000Z",
    firstReviewedAt: "2026-08-20T00:00:00.000Z",
  };
}

describe("collectFlashcardRefs", () => {
  it("parses flashcard artifacts into flat refs keyed by artifact and index", () => {
    const ws = {
      studyArtifacts: [
        flashcardsArtifact("a1", "Frente: Q1\nVerso: R1\nFrente: Q2\nVerso: R2"),
        { id: "n1", kind: "note", body: "sem cartas", createdAt: NOW.toISOString() },
        flashcardsArtifact("a2", "Frente: Q3\nVerso: R3"),
      ],
    } as Workspace;
    expect(collectFlashcardRefs(ws)).toEqual([
      { sourceKey: "a1:0", front: "Q1", back: "R1" },
      { sourceKey: "a1:1", front: "Q2", back: "R2" },
      { sourceKey: "a2:0", front: "Q3", back: "R3" },
    ]);
  });

  it("returns empty for missing or invalid artifacts", () => {
    expect(collectFlashcardRefs({} as Workspace)).toEqual([]);
    expect(
      collectFlashcardRefs({
        studyArtifacts: [flashcardsArtifact("x", "texto sem cartas")],
      } as Workspace),
    ).toEqual([]);
  });
});

describe("dueTodayCount", () => {
  const refs = [
    { sourceKey: "a:0", front: "q1", back: "r1" },
    { sourceKey: "a:1", front: "q2", back: "r2" },
    { sourceKey: "b:0", front: "q1", back: "r1" },
  ];
  const identities = new Map([
    ["a:0", "id-1"],
    ["a:1", "id-2"],
    ["b:0", "id-1"],
  ]);

  it("counts cards without reviews as due today", () => {
    expect(dueTodayCount(refs, identities, [], NOW)).toBe(2);
  });

  it("joins reviews by identity and skips cards not yet due", () => {
    const reviews = [
      review("id-1", "2026-08-30T00:00:00.000Z"),
      review("id-2", "2026-08-24T23:59:59.999Z"),
    ];
    expect(dueTodayCount(refs, identities, reviews, NOW)).toBe(1);
  });

  it("counts the same identity only once across decks", () => {
    const duplicatedRefs = [...refs, { sourceKey: "c:0", front: "q1", back: "r1" }];
    const identitiesWithDup = new Map([...identities, ["c:0", "id-1"]]);
    expect(dueTodayCount(duplicatedRefs, identitiesWithDup, [], NOW)).toBe(2);
  });

  it("skips refs missing from the identity map", () => {
    expect(dueTodayCount(refs, new Map(), [], NOW)).toBe(0);
  });

  it("treats invalid review dates as due", () => {
    expect(dueTodayCount(refs.slice(0, 1), identities, [review("id-1", "não é data")], NOW)).toBe(1);
  });
});

describe("openTasks", () => {
  it("filters completed tasks and sorts by priority then due date", () => {
    const tasks: Task[] = [
      createTask("baixa", "2026-09-01", "low"),
      createTask("alta tarde", "2026-09-02", "high"),
      { ...createTask("feita", "2026-08-01"), isCompleted: true },
      createTask("alta cedo", "2026-09-01", "high"),
      createTask("normal", "2026-09-03"),
    ];
    expect(openTasks(tasks).map((task) => task.title)).toEqual([
      "alta cedo",
      "alta tarde",
      "normal",
      "baixa",
    ]);
  });

  it("returns empty for no tasks", () => {
    expect(openTasks([])).toEqual([]);
  });
});

describe("nearestDeadline", () => {
  it("returns the earliest of exam and presentation dates", () => {
    expect(
      nearestDeadline({
        examDate: "2026-12-10T00:00:00.000Z",
        presentationDate: "2026-11-01T00:00:00.000Z",
      } as Workspace),
    ).toBe("2026-11-01T00:00:00.000Z");
  });

  it("ignores invalid dates and returns null when none are valid", () => {
    expect(nearestDeadline({ examDate: "inválida" } as Workspace)).toBeNull();
    expect(nearestDeadline({} as Workspace)).toBeNull();
  });
});

describe("estimateUnitCount / coverageRatio", () => {
  it("counts non-empty paragraphs as units with a floor of one", () => {
    expect(estimateUnitCount({ noteBody: "um\n\ndois\n\n\n\ntrês" } as never)).toBe(3);
    expect(estimateUnitCount({ noteBody: "" } as never)).toBe(1);
  });

  it("computes clamped coverage from visited indices", () => {
    const node = {
      noteBody: "a\n\nb\n\nc",
      visitedUnitIndices: [0, 1],
    } as unknown as CanvasNode;
    expect(coverageRatio(node)).toBeCloseTo(2 / 3);
    expect(
      coverageRatio({ ...node, visitedUnitIndices: [0, 1, 2, 3] } as unknown as CanvasNode),
    ).toBe(1);
    expect(coverageRatio({ noteBody: "", visitedUnitIndices: null } as never)).toBe(0);
  });
});

describe("nextAction", () => {
  const refs = [{ sourceKey: "a:0", front: "q", back: "r" }];
  const identities = new Map([["a:0", "id"]]);

  it("prioritizes due flashcards", () => {
    expect(nextAction({ refs, identities, reviews: [], tasks: [createTask("t")], now: NOW })).toBe(
      "flashcards",
    );
  });

  it("falls back to open tasks then material", () => {
    expect(
      nextAction({ refs, identities: new Map(), reviews: [], tasks: [createTask("t")], now: NOW }),
    ).toBe("task");
    expect(
      nextAction({ refs, identities: new Map(), reviews: [], tasks: [], now: NOW }),
    ).toBe("material");
  });
});
