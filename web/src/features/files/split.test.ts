import { describe, expect, it } from "vitest";
import { resolveZipPath, splitPages, stripFileName } from "./extract";

describe("splitPages", () => {
  it("returns a single page when there is no separator", () => {
    expect(splitPages("apenas um texto")).toEqual(["apenas um texto"]);
  });

  it("splits on \\n---\\n", () => {
    expect(splitPages("primeira\n---\nsegunda")).toEqual(["primeira", "segunda"]);
  });

  it("accepts longer separators", () => {
    expect(splitPages("a\n------\nb")).toEqual(["a", "b"]);
  });

  it("does not split inline dashes without surrounding newlines", () => {
    expect(splitPages("a --- b\n--\nc")).toHaveLength(1);
  });

  it("splits multiple pages preserving order", () => {
    const text = ["p1", "p2", "p3"].join("\n---\n");
    expect(splitPages(text)).toEqual(["p1", "p2", "p3"]);
  });
});

describe("stripFileName", () => {
  it("removes known extensions case-insensitively", () => {
    expect(stripFileName("Aula 01.PDF")).toBe("Aula 01");
    expect(stripFileName("resumo.md")).toBe("resumo");
    expect(stripFileName("livro.epub")).toBe("livro");
  });

  it("keeps names without extension", () => {
    expect(stripFileName("sem extensao")).toBe("sem extensao");
  });
});

describe("resolveZipPath", () => {
  it("joins the OPF directory with the href", () => {
    expect(resolveZipPath("OEBPS/", "cap1.xhtml")).toBe("OEBPS/cap1.xhtml");
  });

  it("resolves ../ segments", () => {
    expect(resolveZipPath("OEBPS/textos/", "../estilos/estilo.css")).toBe("OEBPS/estilos/estilo.css");
  });

  it("handles root-level OPF", () => {
    expect(resolveZipPath("", "content.xhtml")).toBe("content.xhtml");
  });

  it("collapses duplicate slashes and dots", () => {
    expect(resolveZipPath("OEBPS//", "./cap1.xhtml")).toBe("OEBPS/cap1.xhtml");
  });
});
