// @vitest-environment jsdom
import { describe, expect, it } from "vitest";
import { findOpfPath, opfTitle, parseSpine } from "./extract";

const CONTAINER_XML = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>`;

const OPF_XML = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Aula de Bioquímica</dc:title>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>
    <item id="c1" href="cap1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="textos/cap2.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="estilos/base.css" media-type="text/css"/>
  </manifest>
  <spine>
    <itemref idref="nav"/>
    <itemref idref="c1"/>
    <itemref idref="c2"/>
    <itemref idref="fantasma"/>
  </spine>
</package>`;

describe("findOpfPath", () => {
  it("reads the rootfile full-path", () => {
    expect(findOpfPath(CONTAINER_XML)).toBe("OEBPS/content.opf");
  });

  it("throws a friendly error when the OPF is missing", () => {
    expect(() => findOpfPath("<container/>")).toThrow(/OPF/);
  });
});

describe("parseSpine", () => {
  it("returns chapters in spine order with hrefs resolved against the OPF dir", () => {
    const spine = parseSpine(CONTAINER_XML, OPF_XML);
    expect(spine.map((item) => item.href)).toEqual([
      "OEBPS/nav.xhtml",
      "OEBPS/cap1.xhtml",
      "OEBPS/textos/cap2.xhtml",
    ]);
  });

  it("flags nav items so callers can skip them", () => {
    const spine = parseSpine(CONTAINER_XML, OPF_XML);
    expect(spine[0]?.isNav).toBe(true);
    expect(spine[1]?.isNav).toBe(false);
  });

  it("skips itemrefs without a manifest entry", () => {
    const spine = parseSpine(CONTAINER_XML, OPF_XML);
    expect(spine).toHaveLength(3);
    expect(spine.some((item) => item.idref === "fantasma")).toBe(false);
  });

  it("throws on malformed XML", () => {
    expect(() => parseSpine("<not closed", OPF_XML)).toThrow(/DRM|inválido/i);
  });
});

describe("opfTitle", () => {
  it("reads dc:title", () => {
    expect(opfTitle(OPF_XML)).toBe("Aula de Bioquímica");
  });

  it("returns null when there is no title", () => {
    expect(opfTitle("<package/>")).toBeNull();
  });
});
