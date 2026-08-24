export interface LayoutItem {
  id: string;
  width: number;
  height: number;
}

export interface GridPoint {
  x: number;
  y: number;
}

/**
 * Packs items left-to-right into rows constrained to `areaWidth` world units,
 * with `spacing` gaps between items and between rows. Each row advances below
 * the tallest item of the previous row. The first item of a row is always
 * placed even when wider than the area.
 */
export function computeGridLayout(
  items: readonly LayoutItem[],
  areaWidth = 1000,
  spacing = 24,
): Map<string, GridPoint> {
  const positions = new Map<string, GridPoint>();
  let cursorX = 0;
  let cursorY = 0;
  let rowHeight = 0;

  for (const item of items) {
    if (positions.size > 0 && cursorX + item.width > areaWidth) {
      cursorX = 0;
      cursorY += rowHeight + spacing;
      rowHeight = 0;
    }
    positions.set(item.id, { x: cursorX, y: cursorY });
    cursorX += item.width + spacing;
    rowHeight = Math.max(rowHeight, item.height);
  }

  return positions;
}
