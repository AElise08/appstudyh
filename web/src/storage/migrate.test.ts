import { describe, expect, it } from "vitest";
import "fake-indexeddb/auto";
import { migratePrototypeV2 } from "./migrate.js";

const proto = {
  settings: { apiKey: "sk-secret", endpoint: "https://api.example.com" },
  workspaces: {
    w1: {
      id: "w1",
      name: "Química",
      materials: [{ id: "m1", title: "Aula 1", text: "Texto da aula" }],
      decks: [{ id: "d1", title: "Deck", cards: [{ front: "O que é X?", back: "É Y" }] }],
      questions: [],
      tasks: [{ id: "t1", title: "Ler capítulo 2", done: false }],
      notebooks: [{ id: "n1", title: "Caderno", html: "<p><b>Resumo</b> livre</p>" }],
    },
  },
};

describe("migratePrototypeV2", () => {
  it("mapeia materiais, decks, tarefas e cadernos", () => {
    const result = migratePrototypeV2(proto);
    expect(result).not.toBeNull();
    const { workspace, stats } = result!;
    expect(workspace.name).toBe("Química");
    expect(stats.materials).toBe(1);
    expect(stats.decks).toBe(1);
    expect(stats.cards).toBe(1);
    expect(stats.tasks).toBe(1);
    expect(stats.notebooks).toBe(1);
    expect(workspace.nodes[0]?.kind).toBe("note");
    expect(workspace.studyArtifacts?.[0]?.body).toContain("Frente: O que é X?");
    expect(workspace.studyTasks?.[0]?.priority).toBe("normal");
    expect(workspace.notebooks?.[0]?.plainText).toContain("Resumo");
  });

  it("nunca importa credenciais", () => {
    const { workspace } = migratePrototypeV2(proto)!;
    const json = JSON.stringify(workspace);
    expect(json).not.toContain("sk-secret");
    expect(json).not.toContain("apiKey");
  });

  it("retorna null para dados inutilizáveis", () => {
    expect(migratePrototypeV2(null)).toBeNull();
    expect(migratePrototypeV2({})).toBeNull();
    expect(migratePrototypeV2({ workspaces: {} })).toBeNull();
    expect(migratePrototypeV2({ workspaces: { w1: { name: "vazio" } } })).toBeNull();
  });
});
