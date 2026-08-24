import { describe, expect, it } from "vitest";
import { createCanvasNode, createReview, createWorkspace } from "./create";
import { deleteMaterials } from "./deletion";

const materialID = "11111111-2222-3333-4444-555555555555";
const otherMaterialID = "22222222-3333-4444-5555-666666666666";
const derivedID = "33333333-4444-5555-6666-777777777777";
const recordID = "44444444-5555-6666-7777-888888888888";
const date = "2026-08-24T12:00:00.000Z";

function sampleWorkspace() {
  const material = createCanvasNode({ id: materialID, kind: "pdf", frame: defaultRect("pdf") });
  const other = createCanvasNode({ id: otherMaterialID, kind: "epub", frame: defaultRect("pdf") });
  const derived = createCanvasNode({
    id: derivedID,
    kind: "note",
    frame: defaultRect("note"),
    sourceMaterialID: materialID,
  });
  return createWorkspace({
    name: "Remoção",
    nodes: [material, other, derived],
    studyArtifacts: [
      { id: recordID, kind: "flashcards", body: "Frente: A\nVerso: B", sourceNodeID: materialID, createdAt: date },
      {
        id: "aaaaaaaa-0000-0000-0000-000000000001",
        kind: "summary",
        body: "sem vínculo",
        sourceNodeID: null,
        createdAt: date,
      },
    ],
    flashcardReviews: [createReview("a", materialID, new Date(date))],
    studyHistory: [{ id: recordID, nodeID: materialID, openedAt: date }],
    studyActivityEvents: [{ id: recordID, kind: "openedMaterial", nodeID: materialID, occurredAt: date }],
    focusSessions: [
      { id: recordID, startedAt: date, endedAt: date, plannedMinutes: 25, completedMinutes: 25, intention: "", materialID },
    ],
    notebooks: [
      {
        id: recordID,
        title: "Caderno",
        plainText: "mantido",
        createdAt: date,
        updatedAt: date,
        sourceMaterialID: materialID,
        sourcePageIndex: 4,
      },
    ],
    connections: [
      { id: recordID, fromNodeID: materialID, toNodeID: otherMaterialID, kind: "canvas" as const },
      {
        id: "aaaaaaaa-0000-0000-0000-000000000002",
        fromNodeID: otherMaterialID,
        toNodeID: derivedID,
        kind: "wikilink" as const,
      },
    ],
  });
}

function defaultRect(kind: "pdf" | "note") {
  if (kind === "pdf") return { x: 0, y: 0, width: 420, height: 560 };
  return { x: 0, y: 0, width: 280, height: 220 };
}

describe("deleteMaterials impact counts", () => {
  it("counts every dependent record category", () => {
    expect(deleteMaterials(sampleWorkspace(), [materialID]).impact).toEqual({
      artifacts: 1,
      derivedNodes: 1,
      reviews: 1,
      historyEntries: 1,
      activityEvents: 1,
      focusSessions: 1,
      notebooks: 1,
      linkedRecordCount: 7,
    });
  });

  it("does not count a removed node as its own derived dependent", () => {
    const workspace = createWorkspace({
      nodes: [createCanvasNode({ id: materialID, kind: "note", sourceMaterialID: materialID })],
    });
    expect(deleteMaterials(workspace, [materialID]).impact.derivedNodes).toBe(0);
  });
});

describe("deleteMaterials rules", () => {
  it("removes the nodes and incident connections but keeps other materials", () => {
    const result = deleteMaterials(sampleWorkspace(), [materialID]);
    expect(result.workspace.nodes.map((node) => node.id)).toEqual([otherMaterialID, derivedID]);
    expect(result.workspace.connections).toHaveLength(1);
    expect(result.workspace.connections?.[0]).toMatchObject({ fromNodeID: otherMaterialID, toNodeID: derivedID });
  });

  it("preserves derived content and clears every stale source link", () => {
    const result = deleteMaterials(sampleWorkspace(), [materialID]);
    expect(result.workspace.nodes.find((node) => node.id === derivedID)?.sourceMaterialID).toBeNull();
    expect(result.workspace.studyArtifacts?.[0]).toMatchObject({ sourceNodeID: null });
    // The unlinked artifact is untouched.
    expect(result.workspace.studyArtifacts?.[1]).toMatchObject({ body: "sem vínculo", sourceNodeID: null });
    expect(result.workspace.flashcardReviews?.[0]).toMatchObject({ key: "a", sourceNodeID: null });
    expect(result.workspace.studyActivityEvents?.[0]).toMatchObject({ nodeID: null });
    expect(result.workspace.focusSessions?.[0]).toMatchObject({ materialID: null });
    expect(result.workspace.notebooks?.[0]).toMatchObject({
      plainText: "mantido",
      sourceMaterialID: null,
      sourcePageIndex: null,
    });
  });

  it("deletes orphaned history entries for the removed materials", () => {
    expect(deleteMaterials(sampleWorkspace(), [materialID]).workspace.studyHistory).toEqual([]);
  });

  it("is pure and accepts multiple ids at once", () => {
    const workspace = sampleWorkspace();
    const result = deleteMaterials(workspace, [materialID, otherMaterialID]);
    expect(result.workspace.nodes).toHaveLength(1);
    expect(result.workspace.nodes[0]?.id).toBe(derivedID);
    expect(result.workspace.connections).toEqual([]);
    expect(result.impact.linkedRecordCount).toBe(7);
    expect(workspace.nodes).toHaveLength(3);
  });
});
