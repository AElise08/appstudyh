// @vitest-environment jsdom
import { describe, expect, it } from "vitest";
import { createCanvasNode } from "../domain/create.js";
import { epubCoverDataUrl, isGarbledText, nodeListSubtitle } from "./nodeListMeta.js";

const LOGO = "data:image/png;base64,QUxPR08=";
const COVER = `data:image/jpeg;base64,${"A".repeat(22_000)}`;

describe("isGarbledText", () => {
  it("detects spaced PDF extraction", () => {
    expect(isGarbledText("Autor: J A zil A ne B A r B os")).toBe(true);
  });

  it("accepts normal prose", () => {
    expect(isGarbledText("Capítulo 1 — Introdução ao estudo")).toBe(false);
  });
});

describe("nodeListSubtitle", () => {
  it("shows page count for PDF instead of raw text", () => {
    const node = createCanvasNode({
      kind: "pdf",
      title: "Livro",
      pdfPageCount: 42,
      pdfText: "Autor: J A zil A ne B A r B os",
    });
    expect(nodeListSubtitle(node)).toBe("42 páginas");
  });

  it("shows first clean note line", () => {
    const node = createCanvasNode({
      kind: "note",
      title: "Nota",
      noteBody: "Ideia principal\nSegunda linha",
    });
    expect(nodeListSubtitle(node)).toBe("Ideia principal");
  });
});

describe("epubCoverDataUrl", () => {
  it("uses the stored cover when available", () => {
    const node = createCanvasNode({
      kind: "epub",
      title: "Livro",
      epubCoverDataUrl: COVER,
      epubText: `<img src="${LOGO}">`,
    });
    expect(epubCoverDataUrl(node)).toBe(COVER);
  });

  it("prefers a large cover image over a small logo in early chapters", () => {
    const node = createCanvasNode({
      kind: "epub",
      title: "Perelandra",
      epubText: [
        `<p>DADOS DE COPYRIGHT</p><img class="logo" alt="Le Livros logo" src="${LOGO}">`,
        `<img class="epub-cover" alt="capa" src="${COVER}">`,
      ].join("\n---\n"),
    });
    expect(epubCoverDataUrl(node)).toBe(COVER);
  });
});
