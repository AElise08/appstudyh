import type { Workspace, WorkspaceIndexDocument } from "../domain/types.js";
import {
  decodeWorkspace,
  encodeWorkspace,
  decodeWorkspaceIndexDocument,
  encodeWorkspaceIndex,
} from "../domain/schema.js";
import type { DomainDecodeError } from "../domain/schema.js";

const DB_NAME = "studyh-web";
const DB_VERSION = 2;
const WORKSPACES = "workspaces";
const META = "meta";
const SNAPSHOTS = "snapshots";
const ATTACHMENTS = "attachments";

export const INDEX_META_KEY = "index";

export interface StoredSnapshot {
  id?: number;
  createdAt: string;
  reason: string;
  index: string;
  workspaces: string[];
}

export class StorageBlockedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "StorageBlockedError";
  }
}

export function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(WORKSPACES)) db.createObjectStore(WORKSPACES, { keyPath: "id" });
      if (!db.objectStoreNames.contains(META)) db.createObjectStore(META, { keyPath: "key" });
      if (!db.objectStoreNames.contains(SNAPSHOTS)) db.createObjectStore(SNAPSHOTS, { autoIncrement: true });
      if (!db.objectStoreNames.contains(ATTACHMENTS)) db.createObjectStore(ATTACHMENTS, { keyPath: "id" });
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error("IndexedDB open failed"));
  });
}

function requestAsPromise<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error("IndexedDB request failed"));
  });
}

async function withStore<T>(
  storeName: string,
  mode: IDBTransactionMode,
  fn: (store: IDBObjectStore) => IDBRequest<T> | void,
): Promise<T | undefined> {
  const db = await openDB();
  try {
    const tx = db.transaction(storeName, mode);
    const store = tx.objectStore(storeName);
    const req = fn(store);
    const result = req ? await requestAsPromise(req) : undefined;
    await new Promise<void>((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error ?? new Error("transaction failed"));
      tx.onabort = () => reject(tx.error ?? new Error("transaction aborted"));
    });
    return result;
  } finally {
    db.close();
  }
}

interface MetaRecord {
  key: string;
  value: unknown;
}

async function getMeta(key: string): Promise<unknown | undefined> {
  const rec = await withStore<MetaRecord | undefined>(META, "readonly", (s) => s.get(key));
  return rec?.value;
}

async function putMeta(key: string, value: unknown): Promise<void> {
  await withStore(META, "readwrite", (s) => {
    s.put({ key, value } satisfies MetaRecord);
  });
}

async function getAllRawWorkspaces(): Promise<{ id: string; json: string }[]> {
  interface RawRecord {
    id: string;
    json: string;
  }
  return (await withStore<RawRecord[]>(WORKSPACES, "readonly", (s) => s.getAll())) ?? [];
}

function classifyFailure(err: unknown): "future" | "corrupt" {
  const name = (err as Partial<DomainDecodeError>)?.name;
  return name === "DomainDecodeError" ? "future" : "corrupt";
}

export interface LoadResult {
  workspaces: Workspace[];
  index: WorkspaceIndexDocument | null;
  blocked: boolean;
  blockReason: string | null;
}

export class WorkspaceStore {
  private timers = new Map<string, ReturnType<typeof setTimeout>>();
  private dirty = new Set<string>();
  private blockedReason: string | null = null;

  get isBlocked(): boolean {
    return this.blockedReason !== null;
  }

  async loadAll(): Promise<LoadResult> {
    const rawIndex = await getMeta(INDEX_META_KEY).catch(() => undefined);
    let index: WorkspaceIndexDocument | null = null;
    if (rawIndex !== undefined) {
      try {
        index = decodeWorkspaceIndexDocument(rawIndex);
      } catch {
        index = null; // corrupt index -> recover by scan below
      }
    }

    const raws = await getAllRawWorkspaces();
    const byId = new Map(raws.map((r) => [r.id, r.json]));
    const workspaces: Workspace[] = [];
    const failures: string[] = [];

    const idsToLoad = index ? index.workspaceIDs : byId.keys();
    for (const id of idsToLoad) {
      const json = byId.get(id);
      if (json === undefined) continue;
      try {
        workspaces.push(decodeWorkspace(json));
      } catch (err) {
        failures.push(`${id}: ${classifyFailure(err) === "future" ? "versão futura" : "ilegível"}`);
      }
    }

    if (failures.length > 0) {
      this.blockedReason = `Dados incompatíveis encontrados e preservados sem alterações: ${failures.join("; ")}`;
      return { workspaces: [], index, blocked: true, blockReason: this.blockedReason };
    }

    // Recover missing/corrupt index from scan
    if (!index && workspaces.length > 0) {
      workspaces.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
      const recovered: WorkspaceIndexDocument = {
        schemaVersion: 1,
        workspaceIDs: workspaces.map((w) => w.id),
        selectedID: workspaces[0]?.id ?? null,
      };
      try {
        await putMeta(INDEX_META_KEY, JSON.parse(encodeWorkspaceIndex(recovered)));
        index = recovered;
      } catch {
        // keep recovered in-memory only
      }
      workspaces.sort((a, b) => a.name.localeCompare(b.name));
    }

    return { workspaces, index, blocked: false, blockReason: null };
  }

  assertWritable(): void {
    if (this.blockedReason) throw new StorageBlockedError(this.blockedReason);
  }

  save(workspace: Workspace, debounceMs = 350): void {
    this.assertWritable();
    this.dirty.add(workspace.id);
    clearTimeout(this.timers.get(workspace.id));
    this.timers.set(
      workspace.id,
      setTimeout(() => {
        void this.flushOne(workspace.id);
      }, debounceMs),
    );
  }

  private async flushOne(id: string): Promise<void> {
    if (!this.dirty.has(id)) return;
    this.timers.delete(id);
    this.dirty.delete(id);
    await this.writeNow(await this.resolveForWrite(id));
  }

  private pendingDocs = new Map<string, Workspace>();

  private async resolveForWrite(id: string): Promise<Workspace> {
    const doc = this.pendingDocs.get(id);
    if (doc) {
      this.pendingDocs.delete(id);
      return doc;
    }
    const raws = await getAllRawWorkspaces();
    const rec = raws.find((r) => r.id === id);
    return rec ? decodeWorkspace(rec.json) : (() => { throw new Error(`workspace ${id} não encontrado para salvar`); })();
  }

  /** Queue latest in-memory document and persist it (debounced or forced). */
  queue(workspace: Workspace): void {
    this.pendingDocs.set(workspace.id, workspace);
    this.save(workspace);
  }

  async writeNow(workspace: Workspace): Promise<void> {
    this.assertWritable();
    const json = encodeWorkspace(workspace);
    await withStore(WORKSPACES, "readwrite", (s) => {
      s.put({ id: workspace.id, json });
    });
    await this.writeIndexFor(workspace);
  }

  private async writeIndexFor(workspace: Workspace): Promise<void> {
    const current = (await getMeta(INDEX_META_KEY).catch(() => undefined)) as string | object | undefined;
    let ids: string[] = [];
    let selected: string | null = null;
    if (current !== undefined) {
      try {
        const decoded = decodeWorkspaceIndexDocument(current);
        ids = decoded.workspaceIDs;
        selected = decoded.selectedID ?? null;
      } catch {
        ids = [];
      }
    }
    if (!ids.includes(workspace.id)) ids = [...ids, workspace.id];
    selected = selected ?? workspace.id;
    await putMeta(INDEX_META_KEY, JSON.parse(encodeWorkspaceIndex({ schemaVersion: 1, workspaceIDs: ids, selectedID: selected })));
  }

  async flush(): Promise<void> {
    const ids = [...new Set([...this.timers.keys(), ...this.dirty])];
    for (const id of ids) {
      clearTimeout(this.timers.get(id));
      this.timers.delete(id);
      this.dirty.delete(id);
      await this.writeNow(await this.resolveForWrite(id));
    }
  }

  async createWorkspace(name: string): Promise<Workspace> {
    const { createWorkspace } = await import("../domain/create.js");
    const ws = createWorkspace({ name });
    await this.writeNow(ws);
    return ws;
  }

  async deleteWorkspace(id: string): Promise<void> {
    this.assertWritable();
    const raws = await getAllRawWorkspaces();
    const target = raws.find((r) => r.id === id);
    if (!target) return;
    const ws = decodeWorkspace(target.json);
    await this.takeManualSnapshot(ws, "antes de excluir matéria");
    await withStore(WORKSPACES, "readwrite", (s) => {
      s.delete(id);
    });
    const current = (await getMeta(INDEX_META_KEY)) as string | object | undefined;
    if (current !== undefined) {
      try {
        const decoded = decodeWorkspaceIndexDocument(current);
        const next: WorkspaceIndexDocument = {
          ...decoded,
          workspaceIDs: decoded.workspaceIDs.filter((x) => x !== id),
          selectedID:
            decoded.selectedID === id ? (decoded.workspaceIDs.filter((x) => x !== id)[0] ?? null) : decoded.selectedID,
        };
        await putMeta(INDEX_META_KEY, JSON.parse(encodeWorkspaceIndex(next)));
      } catch {
        // leave index untouched when corrupt
      }
    }
  }

  async takeManualSnapshot(ws: Workspace, reason: string): Promise<void> {
    const snapshot: StoredSnapshot = {
      createdAt: new Date().toISOString(),
      reason,
      index: "",
      workspaces: [encodeWorkspace(ws)],
    };
    await withStore(SNAPSHOTS, "readwrite", (s) => {
      s.add(snapshot);
    });
  }

  async listSnapshots(): Promise<StoredSnapshot[]> {
    const all = (await withStore<StoredSnapshot[]>(SNAPSHOTS, "readonly", (s) => s.getAll())) ?? [];
    return all.sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 20);
  }

  async restoreLatestSnapshot(): Promise<boolean> {
    const snaps = await this.listSnapshots();
    const snap = snaps[0];
    if (!snap || snap.workspaces.length === 0) return false;
    for (const json of snap.workspaces) {
      const ws = decodeWorkspace(json);
      await this.writeNow(ws);
    }
    return true;
  }

  async saveAttachment(id: string, blob: Blob): Promise<void> {
    this.assertWritable();
    await withStore(ATTACHMENTS, "readwrite", (s) => {
      s.put({ id, blob });
    });
  }

  async getAttachment(id: string): Promise<Blob | null> {
    const rec = await withStore<{ id: string; blob: Blob } | undefined>(ATTACHMENTS, "readonly", (s) =>
      s.get(id),
    );
    return rec?.blob ?? null;
  }

  exportPackage(workspaces: Workspace[]): Record<string, unknown> {
    return {
      format: "studyh-package",
      packageVersion: 1,
      createdAt: new Date().toISOString(),
      workspaces: workspaces.map((w) => JSON.parse(encodeWorkspace(w))),
    };
  }

  static decodePackage(pkg: unknown): Workspace[] {
    if (typeof pkg !== "object" || pkg === null) throw new Error("pacote inválido");
    const p = pkg as { format?: unknown; packageVersion?: unknown; workspaces?: unknown };
    if (p.format !== "studyh-package") throw new Error("formato de pacote desconhecido");
    if (p.packageVersion !== 1) throw new Error("versão de pacote não suportada");
    if (!Array.isArray(p.workspaces)) throw new Error("pacote sem matérias");
    return p.workspaces.map((w) => decodeWorkspace(w));
  }

  async importPackage(pkg: unknown): Promise<number> {
    this.assertWritable();
    const incoming = WorkspaceStore.decodePackage(pkg); // throws before any write
    const all = await getAllRawWorkspaces();
    await withStore(SNAPSHOTS, "readwrite", (s) => {
      s.add({
        createdAt: new Date().toISOString(),
        reason: "antes de importar pacote",
        index: "",
        workspaces: all.map((r) => r.json),
      } satisfies StoredSnapshot);
    });
    for (const ws of incoming) {
      await this.writeNow(ws);
    }
    return incoming.length;
  }
}
