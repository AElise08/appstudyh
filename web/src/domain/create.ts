import {
  WORKSPACE_INDEX_SCHEMA_VERSION,
  WORKSPACE_SCHEMA_VERSION,
  type CanvasNode,
  type CanvasRect,
  type NodeKind,
  type Review,
  type Task,
  type UUID,
  type Workspace,
  type WorkspaceIndexDocument,
} from "./types";

export { WORKSPACE_SCHEMA_VERSION, WORKSPACE_INDEX_SCHEMA_VERSION };

const NODE_TITLES: Record<NodeKind, string> = {
  note: "Nota",
  pdf: "PDF",
  epub: "EPUB",
  web: "Pesquisa",
  calc: "Resolução",
  slides: "Slides",
};

const NODE_SIZES: Record<NodeKind, readonly [width: number, height: number]> = {
  note: [280, 220],
  pdf: [420, 560],
  epub: [420, 560],
  web: [480, 420],
  calc: [380, 360],
  slides: [520, 390],
};

export const DEFAULT_WORKSPACE_NAME = "Minha primeira matéria";
export const DEFAULT_WEB_URL = "https://www.google.com";

export function newUUID(): UUID {
  return globalThis.crypto.randomUUID();
}

export function defaultCanvasRect(kind: NodeKind, origin: { x: number; y: number } = { x: 0, y: 0 }): CanvasRect {
  const [width, height] = NODE_SIZES[kind];
  return { x: origin.x, y: origin.y, width, height };
}

export interface NewCanvasNode extends Partial<Omit<CanvasNode, "kind" | "frame">> {
  kind: NodeKind;
  frame?: CanvasRect;
  x?: number;
  y?: number;
}

export function createCanvasNode(input: NewCanvasNode): CanvasNode {
  const { x, y, frame, ...rest } = input;
  return {
    id: newUUID(),
    title: NODE_TITLES[input.kind],
    frame: frame ?? defaultCanvasRect(input.kind, { x: x ?? 0, y: y ?? 0 }),
    zIndex: 0,
    noteBody: "",
    pdfPageIndex: 0,
    pdfSelectedText: "",
    pdfVisibleText: "",
    webURL: DEFAULT_WEB_URL,
    webSelectedText: "",
    calcBody: "",
    ...rest,
    ...(frame === undefined ? {} : { frame }),
  };
}

export type NewWorkspace = Partial<Omit<Workspace, "schemaVersion" | "name">> & { name?: string };

export function createWorkspace(input: NewWorkspace | string = {}): Workspace {
  const values = typeof input === "string" ? { name: input } : input;
  return {
    id: newUUID(),
    name: DEFAULT_WORKSPACE_NAME,
    nodes: [],
    cameraX: 0,
    cameraY: 0,
    cameraScale: 1,
    updatedAt: new Date().toISOString(),
    ...values,
    schemaVersion: WORKSPACE_SCHEMA_VERSION,
  };
}

export function createWorkspaceIndexDocument(
  workspaceIDs: Iterable<UUID>,
  selectedID: UUID | null = null,
): WorkspaceIndexDocument {
  return {
    schemaVersion: WORKSPACE_INDEX_SCHEMA_VERSION,
    workspaceIDs: [...workspaceIDs],
    selectedID,
  };
}

/** Swift defaults: intervalDays 0, easeFactor 2.5, repetitions 0. */
export function createReview(key: string, sourceNodeID: UUID | null = null, now = new Date()): Review {
  return {
    key,
    sourceNodeID,
    deckID: null,
    dueAt: now.toISOString(),
    intervalDays: 0,
    easeFactor: 2.5,
    repetitions: 0,
    lastRating: null,
    lastReviewedAt: null,
    firstReviewedAt: null,
  };
}

export function createTask(
  title: string,
  dueDate: string | Date = new Date(),
  priority: Task["priority"] = "normal",
  now = new Date(),
): Task {
  return {
    id: newUUID(),
    title,
    dueDate: (dueDate instanceof Date ? dueDate : new Date(dueDate)).toISOString(),
    priority,
    isCompleted: false,
    createdAt: now.toISOString(),
  };
}
