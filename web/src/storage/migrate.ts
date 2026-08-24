import type { Workspace } from "../domain/types.js";
import { createCanvasNode } from "../domain/create.js";
import type {
  ActivityEvent,
  Artifact,
  Notebook,
  Task,
  UUID,
} from "../domain/types.js";

export interface MigrationStats {
  materials: number;
  decks: number;
  cards: number;
  questions: number;
  tasks: number;
  notebooks: number;
}

export interface MigrationResult {
  workspace: Workspace;
  stats: MigrationStats;
}

function stripHtml(html: string): string {
  if (typeof DOMParser !== "undefined") {
    return new DOMParser().parseFromString(html, "text/html").body.textContent ?? "";
  }
  return html.replace(/<[^>]*>/g, "");
}

interface ProtoMaterial {
  id?: unknown;
  title?: unknown;
  text?: unknown;
}

interface ProtoCard {
  front?: unknown;
  back?: unknown;
}

interface ProtoDeck {
  id?: unknown;
  title?: unknown;
  cards?: unknown;
}

interface ProtoTask {
  id?: unknown;
  title?: unknown;
  due?: unknown;
  done?: unknown;
  priority?: unknown;
}

interface ProtoNotebook {
  id?: unknown;
  title?: unknown;
  html?: unknown;
  text?: unknown;
}

function asString(v: unknown, fallback = ""): string {
  return typeof v === "string" ? v : fallback;
}

function tomorrowISO(): string {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  return d.toISOString();
}

export function migratePrototypeV2(raw: unknown): MigrationResult | null {
  if (typeof raw !== "object" || raw === null) return null;
  const root = raw as Record<string, unknown>;
  const protoWorkspaces = root.workspaces;
  if (typeof protoWorkspaces !== "object" || protoWorkspaces === null) return null;
  const entries = Object.values(protoWorkspaces as Record<string, unknown>);
  let merged: Record<string, unknown> | null = null;
  for (const entry of entries) {
    if (typeof entry === "object" && entry !== null) {
      merged = entry as Record<string, unknown>;
      break; // single-subject prototype
    }
  }
  if (!merged) return null;

  // Never import settings/credentials.
  const materials = Array.isArray(merged.materials) ? (merged.materials as ProtoMaterial[]) : [];
  const decks = Array.isArray(merged.decks) ? (merged.decks as ProtoDeck[]) : [];
  const protoTasks = Array.isArray(merged.tasks) ? (merged.tasks as ProtoTask[]) : [];
  const protoNotebooks = Array.isArray(merged.notebooks) ? (merged.notebooks as ProtoNotebook[]) : [];

  if (
    materials.length === 0 &&
    decks.length === 0 &&
    protoTasks.length === 0 &&
    protoNotebooks.length === 0
  ) {
    return null;
  }

  const nodes = [];
  const artifacts: Artifact[] = [];
  const tasks: Task[] = [];
  const notebooks: Notebook[] = [];
  const activity: ActivityEvent[] = [];
  const stats: MigrationStats = { materials: 0, decks: 0, cards: 0, questions: 0, tasks: 0, notebooks: 0 };

  const name = asString(merged.name, "Matéria migrada");
  const wsID = typeof merged.id === "string" ? (merged.id as UUID) : crypto.randomUUID();

  for (const m of materials) {
    const id = typeof m.id === "string" ? m.id : undefined;
    const node = createCanvasNode({
      kind: "note",
      id,
      title: asString(m.title, "Material"),
      noteBody: asString(m.text),
    });
    nodes.push(node);
    stats.materials += 1;
  }

  for (const deck of decks) {
    const cards = Array.isArray(deck.cards) ? (deck.cards as ProtoCard[]) : [];
    const valid = cards.filter((c) => asString(c.front).trim() && asString(c.back).trim());
    if (valid.length === 0) continue;
    const body = valid.map((c) => `Frente: ${asString(c.front).trim()}\nVerso: ${asString(c.back).trim()}`).join("\n\n");
    artifacts.push({
      id: crypto.randomUUID(),
      kind: "flashcards",
      body,
      sourceNodeID: null,
      createdAt: new Date().toISOString(),
    });
    stats.decks += 1;
    stats.cards += valid.length;
  }

  for (const t of protoTasks) {
    if (!asString(t.title).trim()) continue;
    const priority = t.priority === "high" || t.priority === "low" ? t.priority : "normal";
    tasks.push({
      id: typeof t.id === "string" ? t.id : crypto.randomUUID(),
      title: asString(t.title),
      dueDate: asString(t.due) || tomorrowISO(),
      priority,
      isCompleted: t.done === true,
      createdAt: new Date().toISOString(),
    });
    stats.tasks += 1;
  }

  for (const nb of protoNotebooks) {
    const text = asString(nb.text) || stripHtml(asString(nb.html));
    if (!text.trim()) continue;
    notebooks.push({
      id: typeof nb.id === "string" ? nb.id : crypto.randomUUID(),
      title: asString(nb.title, "Caderno"),
      plainText: text,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      sourceMaterialID: null,
      sourcePageIndex: null,
    });
    stats.notebooks += 1;
  }

  const workspace: Workspace = {
    schemaVersion: 1,
    id: wsID,
    name,
    nodes,
    cameraX: 0,
    cameraY: 0,
    cameraScale: 1,
    updatedAt: new Date().toISOString(),
    studyArtifacts: artifacts,
    studyTasks: tasks,
    notebooks,
    studyActivityEvents: activity,
  };

  void activity;
  return { workspace, stats };
}
