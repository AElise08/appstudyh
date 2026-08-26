import { describe, expect, it } from "vitest";
import { createCanvasNode } from "../domain/create.js";
import { nextNodePlacement, spreadOverlappingNodes } from "./placement.js";

describe("nextNodePlacement", () => {
  it("coloca o primeiro card na origem", () => {
    const frame = nextNodePlacement([], "note");
    expect(frame.x).toBe(80);
    expect(frame.y).toBe(80);
  });

  it("não empilha cards no mesmo ponto", () => {
    const first = createCanvasNode({ kind: "pdf", x: 80, y: 80 });
    const second = nextNodePlacement([first], "pdf");
    expect(second.x).toBeGreaterThan(first.frame.x + first.frame.width);
    expect(second.y).toBe(first.frame.y);
  });

  it("posiciona o novo card depois de todos os existentes", () => {
    const first = createCanvasNode({ kind: "pdf", x: 80, y: 80 });
    const second = createCanvasNode({ kind: "note", x: 900, y: 300 });
    const frame = nextNodePlacement([first, second], "pdf");
    expect(frame.x).toBeGreaterThan(second.frame.x + second.frame.width);
  });
});

describe("spreadOverlappingNodes", () => {
  it("separa cards antigos sobrepostos", () => {
    const first = createCanvasNode({ kind: "pdf", x: 0, y: 0 });
    const second = createCanvasNode({ kind: "pdf", x: 100, y: 100 });
    const result = spreadOverlappingNodes([first, second]);
    expect(result.changed).toBe(true);
    expect(result.nodes[1]!.frame.x).toBeGreaterThan(
      result.nodes[0]!.frame.x + result.nodes[0]!.frame.width,
    );
  });

  it("preserva posições que já não colidem", () => {
    const first = createCanvasNode({ kind: "note", x: 0, y: 0 });
    const second = createCanvasNode({ kind: "note", x: 500, y: 0 });
    const result = spreadOverlappingNodes([first, second]);
    expect(result.changed).toBe(false);
    expect(result.nodes).toEqual([first, second]);
  });
});
