// @vitest-environment jsdom
import JSZip from "jszip";
import { describe, expect, it } from "vitest";
import {
  epubChaptersNeedImageInlining,
  findCoverManifestHref,
  inlineEpubChapterImages,
  pickBestCoverFromChapters,
} from "./extract";

const TINY_PNG =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

async function makeZip(files: Record<string, string | Uint8Array>) {
  const zip = new JSZip();
  for (const [path, content] of Object.entries(files)) {
    zip.file(path, content);
  }
  return zip;
}

describe("inlineEpubChapterImages", () => {
  it("inlines img src with case-insensitive zip paths", async () => {
    const zip = await makeZip({
      "OEBPS/Images/Cover.jpg": Uint8Array.from(atob(TINY_PNG), (c) => c.charCodeAt(0)),
    });
    const html = '<p>capa</p><img src="../Images/cover.jpg" alt="capa">';
    const out = await inlineEpubChapterImages(html, zip, "OEBPS/Text/chapter.xhtml");
    expect(out).toContain("data:image/jpeg;base64,");
    expect(out).not.toContain("../Images/cover.jpg");
  });

  it("promotes CSS background cover into an img tag", async () => {
    const zip = await makeZip({
      "OEBPS/images/cover.jpg": Uint8Array.from(atob(TINY_PNG), (c) => c.charCodeAt(0)),
    });
    const html =
      '<html><head><style>body{background-image:url(../images/cover.jpg);}</style></head>' +
      '<body><div class="cover"></div></body></html>';
    const out = await inlineEpubChapterImages(html, zip, "OEBPS/Text/cover.xhtml");
    expect(out).toContain('<img');
    expect(out).toContain("data:image/jpeg;base64,");
  });

  it("detects chapters that still need image inlining", () => {
    expect(epubChaptersNeedImageInlining(['<img src="../Images/cover.jpg">'])).toBe(true);
    expect(epubChaptersNeedImageInlining(['<img src="data:image/jpeg;base64,abc">'])).toBe(false);
    expect(
      epubChaptersNeedImageInlining(['<style>body{background:url(../img/cover.jpg)}</style>']),
    ).toBe(true);
  });
});

describe("findCoverManifestHref", () => {
  it("reads EPUB3 cover-image from manifest", () => {
    const opf = `<?xml version="1.0"?>
      <package xmlns="http://www.idpf.org/2007/opf">
        <metadata></metadata>
        <manifest>
          <item id="cover" href="Images/cover.jpg" properties="cover-image" media-type="image/jpeg"/>
        </manifest>
        <spine></spine>
      </package>`;
    expect(findCoverManifestHref(opf, "OEBPS/content.opf")).toBe("OEBPS/Images/cover.jpg");
  });
});

describe("pickBestCoverFromChapters", () => {
  const logo = "data:image/png;base64,TE9HTw==";
  const cover = `data:image/jpeg;base64,${"Y".repeat(20_000)}`;

  it("skips tiny logos and picks the real cover", () => {
    const picked = pickBestCoverFromChapters([
      `<p>copyright</p><img class="logo" src="${logo}">`,
      `<img class="epub-cover" src="${cover}">`,
    ]);
    expect(picked).toBe(cover);
  });
});
