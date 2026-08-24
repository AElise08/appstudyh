import { describe, expect, it } from "vitest";
import {
  DEFAULT_WEB_URL,
  createCanvasNode,
  createReview,
  createTask,
  createWorkspace,
  createWorkspaceIndexDocument,
  defaultCanvasRect,
} from "./create";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

describe("workspace defaults", () => {
  it("creates a new workspace named 'Minha primeira matéria'", () => {
    const workspace = createWorkspace();
    expect(workspace.name).toBe("Minha primeira matéria");
    expect(workspace.schemaVersion).toBe(1);
    expect(workspace.id).toMatch(uuidPattern);
    expect(workspace.nodes).toEqual([]);
    expect(workspace.cameraX).toBe(0);
    expect(workspace.cameraY).toBe(0);
    expect(workspace.cameraScale).toBe(1);
    expect(new Date(workspace.updatedAt).toISOString()).toBe(workspace.updatedAt);
    expect(createWorkspace("Cálculo").name).toBe("Cálculo");
  });

  it("creates an index document at the current version", () => {
    const id = createWorkspace().id;
    expect(createWorkspaceIndexDocument([id], id)).toEqual({
      schemaVersion: 1,
      workspaceIDs: [id],
      selectedID: id,
    });
  });
});

describe("node defaults", () => {
  it("uses the Swift default sizes per kind", () => {
    expect(defaultCanvasRect("note")).toEqual({ x: 0, y: 0, width: 280, height: 220 });
    expect(defaultCanvasRect("pdf")).toMatchObject({ width: 420, height: 560 });
    expect(defaultCanvasRect("epub")).toMatchObject({ width: 420, height: 560 });
    expect(defaultCanvasRect("web")).toMatchObject({ width: 480, height: 420 });
    expect(defaultCanvasRect("calc")).toMatchObject({ width: 380, height: 360 });
    expect(defaultCanvasRect("slides")).toMatchObject({ width: 520, height: 390 });
  });

  it("applies kind titles and field defaults like the Swift init", () => {
    const node = createCanvasNode({ kind: "web" });
    expect(node.title).toBe("Pesquisa");
    expect(node.webURL).toBe(DEFAULT_WEB_URL);
    expect(node.webURL).toBe("https://www.google.com");
    expect(node.zIndex).toBe(0);
    expect(node.noteBody).toBe("");
    expect(node.pdfPageIndex).toBe(0);
    expect(node.pdfSelectedText).toBe("");
    expect(node.calcBody).toBe("");
    expect(node.linkedNoteID ?? null).toBeNull();
    expect(node.sourceMaterialID ?? null).toBeNull();
    expect(createCanvasNode({ kind: "note" }).title).toBe("Nota");
    expect(createCanvasNode({ kind: "slides" }).title).toBe("Slides");
  });
});

describe("review and task defaults", () => {
  it("creates a review with interval 0, ease 2.5, repetitions 0", () => {
    const now = new Date("2026-08-24T12:00:00.000Z");
    const review = createReview("key", null, now);
    expect(review).toMatchObject({
      key: "key",
      sourceNodeID: null,
      deckID: null,
      intervalDays: 0,
      easeFactor: 2.5,
      repetitions: 0,
    });
    expect(review.dueAt).toBe(now.toISOString());
  });

  it("creates a task with normal priority by default", () => {
    const due = new Date("2026-09-01T10:00:00.000Z");
    const task = createTask("Resolver lista", due);
    expect(task.priority).toBe("normal");
    expect(task.isCompleted).toBe(false);
    expect(task.dueDate).toBe(due.toISOString());
    expect(createTask("Urgente", due, "high").priority).toBe("high");
  });
});
