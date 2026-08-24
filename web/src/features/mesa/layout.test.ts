import { describe, expect, it } from "vitest";
import { computeGridLayout } from "./layout";

describe("computeGridLayout", () => {
  it("returns an empty map for no items", () => {
    expect(computeGridLayout([])).toEqual(new Map());
  });

  it("places the first item at the origin", () => {
    const positions = computeGridLayout([{ id: "a", width: 280, height: 220 }]);
    expect(positions.get("a")).toEqual({ x: 0, y: 0 });
  });

  it("packs items left-to-right with spacing", () => {
    const positions = computeGridLayout(
      [
        { id: "a", width: 100, height: 50 },
        { id: "b", width: 100, height: 80 },
      ],
      1000,
      24,
    );
    expect(positions.get("a")).toEqual({ x: 0, y: 0 });
    expect(positions.get("b")).toEqual({ x: 124, y: 0 });
  });

  it("wraps to a new row below the tallest item when the area width is exceeded", () => {
    const positions = computeGridLayout(
      [
        { id: "a", width: 600, height: 100 },
        { id: "b", width: 500, height: 200 },
        { id: "c", width: 100, height: 50 },
      ],
      1000,
      24,
    );
    expect(positions.get("b")).toEqual({ x: 0, y: 124 });
    expect(positions.get("c")).toEqual({ x: 524, y: 124 });
  });

  it("keeps an item wider than the area on its own row origin", () => {
    const positions = computeGridLayout(
      [
        { id: "wide", width: 1200, height: 90 },
        { id: "small", width: 50, height: 40 },
      ],
      1000,
      24,
    );
    expect(positions.get("wide")).toEqual({ x: 0, y: 0 });
    expect(positions.get("small")).toEqual({ x: 0, y: 114 });
  });
});
