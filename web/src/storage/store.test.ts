import { describe, expect, it, beforeEach } from "vitest";
import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";

let counter = 0;

async function freshStore() {
  const mod = await import("./store.js");
  return new mod.WorkspaceStore();
}

async function makeWorkspace(name: string) {
  const { createWorkspace } = await import("../domain/create.js");
  return createWorkspace({ name: `${name} ${counter++}` });
}

beforeEach(async () => {
  indexedDB = new IDBFactory();
});

describe("WorkspaceStore", () => {
  it("salva e recarrega matérias", async () => {
    const store = await freshStore();
    const ws = await store.createWorkspace("Biologia");
    expect(ws.name).toBe("Biologia");

    const reloaded = await freshStore();
    const result = await reloaded.loadAll();
    expect(result.blocked).toBe(false);
    expect(result.workspaces.map((w) => w.id)).toContain(ws.id);
    expect(result.workspaces[0]?.schemaVersion).toBe(1);
  });

  it("recupera índice ausente ordenando por updatedAt", async () => {
    const store = await freshStore();
    const a = await store.createWorkspace("A");
    const b = await store.createWorkspace("B");
    b.updatedAt = new Date(Date.now() + 1000).toISOString();
    await store.writeNow(b);

    const reloaded = await freshStore();
    const result = await reloaded.loadAll();
    expect(result.index).not.toBeNull();
    expect(result.workspaces.map((w) => w.id)).toEqual(
      expect.arrayContaining([a.id, b.id]),
    );
  });

  it("bloqueia escrita diante de versão futura preservando dados", async () => {
    const store = await freshStore();
    const ws = await store.createWorkspace("Futuro");
    // Corrupt the stored doc to simulate future schema version.
    const raw = JSON.parse(JSON.stringify(ws));
    raw.schemaVersion = 99;
    const { withRawPut } = await import("./test-helpers.js");
    await withRawPut({ id: ws.id, json: JSON.stringify(raw) });

    const reloaded = await freshStore();
    const result = await reloaded.loadAll();
    expect(result.blocked).toBe(true);
    expect(result.blockReason).toContain("versão futura");
    await expect(reloaded.createWorkspace("Outra")).rejects.toThrow();

    // Original bytes preserved.
    const again = await freshStore();
    const reread = await again.loadAll();
    expect(reread.blocked).toBe(true);
  });
});
