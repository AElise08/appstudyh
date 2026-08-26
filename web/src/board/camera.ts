import type { CanvasRect } from "../domain/types.js";

export interface Camera {
  x: number;
  y: number;
  scale: number;
}

export interface Bounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export const MIN_SCALE = 0.25;
export const MAX_SCALE = 3;
export const ZOOM_STEP = 1.2;
export const FIT_PADDING = 48;
export const DOT_SIZE = 24;

export function clampScale(scale: number): number {
  return Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale));
}

export function nodeBounds(nodes: readonly { frame: CanvasRect }[]): Bounds | null {
  if (nodes.length === 0) return null;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const node of nodes) {
    minX = Math.min(minX, node.frame.x);
    minY = Math.min(minY, node.frame.y);
    maxX = Math.max(maxX, node.frame.x + node.frame.width);
    maxY = Math.max(maxY, node.frame.y + node.frame.height);
  }
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

export function fitCameraToBounds(
  bounds: Bounds | null,
  viewport: { width: number; height: number },
): Camera {
  if (
    bounds === null ||
    bounds.width <= 0 ||
    bounds.height <= 0 ||
    viewport.width === 0 ||
    viewport.height === 0
  ) {
    return { x: 0, y: 0, scale: 1 };
  }
  const scale = clampScale(
    Math.min(
      (viewport.width - FIT_PADDING * 2) / bounds.width,
      (viewport.height - FIT_PADDING * 2) / bounds.height,
    ),
  );
  const centerX = bounds.x + bounds.width / 2;
  const centerY = bounds.y + bounds.height / 2;
  return {
    scale,
    x: centerX - viewport.width / (2 * scale),
    y: centerY - viewport.height / (2 * scale),
  };
}

export function rectsIntersect(a: CanvasRect, b: CanvasRect): boolean {
  return (
    a.x < b.x + b.width &&
    a.x + a.width > b.x &&
    a.y < b.y + b.height &&
    a.y + a.height > b.y
  );
}
