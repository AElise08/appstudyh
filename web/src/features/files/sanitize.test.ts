// @vitest-environment jsdom
import { describe, expect, it } from "vitest";
import { htmlChapterToText, sanitizeChapterHtml } from "./extract";

describe("sanitizeChapterHtml", () => {
  it("removes script and style elements entirely", () => {
    const out = sanitizeChapterHtml(
      "<p>texto</p><script>alert(1)</script><style>p{color:red}</style>",
    );
    expect(out).not.toContain("script");
    expect(out).not.toContain("alert");
    expect(out).not.toContain("color:red");
    expect(out).toContain("<p>texto</p>");
  });

  it("removes on* event handler attributes", () => {
    const out = sanitizeChapterHtml('<p onclick="evil()" onmouseover="evil()">oi</p>');
    expect(out).not.toContain("onclick");
    expect(out).not.toContain("onmouseover");
  });

  it("removes javascript: URLs", () => {
    const out = sanitizeChapterHtml('<a href="javascript:alert(1)">link</a><img src="javascript:x">');
    expect(out).not.toContain("javascript:");
  });

  it("keeps safe links and formatting", () => {
    const out = sanitizeChapterHtml(
      '<a href="https://exemplo.com">link</a><em>ênfase</em>',
    );
    expect(out).toContain('href="https://exemplo.com"');
    expect(out).toContain("<em>ênfase</em>");
  });

  it("removes iframe/embed/object", () => {
    const out = sanitizeChapterHtml("<iframe src=\"x\"></iframe><object></object><embed><p>ok</p>");
    expect(out).not.toMatch(/iframe|object|embed/i);
    expect(out).toContain("ok");
  });
});

describe("htmlChapterToText", () => {
  it("strips scripts/styles/nav and converts block tags to newlines", () => {
    const text = htmlChapterToText(
      "<html><head><title>t</title><style>s{}</style></head>" +
        "<body><nav>índice</nav><h1>Capítulo</h1><p>Primeiro parágrafo.</p><p>Segundo.</p>" +
        "<script>x()</script></body></html>",
    );
    expect(text).not.toContain("índice");
    expect(text).not.toContain("x()");
    expect(text.split("\n")).toEqual(["Capítulo", "Primeiro parágrafo.", "Segundo."]);
  });

  it("collapses whitespace runs", () => {
    const text = htmlChapterToText("<p>   muito    espaço\t\taqui   </p>");
    expect(text).toBe("muito espaço aqui");
  });
});
