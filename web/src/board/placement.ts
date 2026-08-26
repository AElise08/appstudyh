import type { CanvasNode, CanvasRect, NodeKind } from "../domain/types.js";
import { defaultCanvasRect } from "../domain/create.js";

const PLACEMENT_GAP = 32;
const PLACEMENT_ORIGIN = { x: 80, y: 80 };

function intersects(a: CanvasRect, b: CanvasRect): boolean {
  return (
    a.x < b.x + b.width &&
    a.x + a.width > b.x &&
    a.y < b.y + b.height &&
    a.y + a.height > b.y
  );
}

/** Posição do próximo card para não empilhar em cima dos existentes. */
export function nextNodePlacement(
  nodes: readonly Pick<CanvasNode, "frame">[],
  kind: NodeKind,
): CanvasRect {
  const base = defaultCanvasRect(kind, PLACEMENT_ORIGIN);
  if (nodes.length === 0) return base;

  return {
    ...base,
    x: Math.max(...nodes.map(({ frame }) => frame.x + frame.width)) + PLACEMENT_GAP,
    y: Math.min(...nodes.map(({ frame }) => frame.y)),
  };
}

/** Corrige cards antigos que foram salvos sobrepostos, preservando os que já estão livres. */
export function spreadOverlappingNodes(nodes: readonly CanvasNode[]): {
  nodes: CanvasNode[];
  changed: boolean;
} {
  const placed: CanvasNode[] = [];
  let changed = false;

  for (const node of nodes) {
    if (!placed.some((other) => intersects(node.frame, other.frame))) {
      placed.push(node);
      continue;
    }

    const frame = {
      ...node.frame,
      x: Math.max(...placed.map((other) => other.frame.x + other.frame.width)) + PLACEMENT_GAP,
      y: Math.min(...placed.map((other) => other.frame.y)),
    };
    placed.push({ ...node, frame });
    changed = true;
  }

  return { nodes: placed, changed };
}
