import type { CanvasNode } from "../domain/types.js";

const KIND_LABELS: Record<CanvasNode["kind"], string> = {
  note: "Nota",
  pdf: "PDF",
  epub: "EPUB",
  web: "Pesquisa",
  calc: "Resolução",
  slides: "Slides",
};

export function nodeContextExcerpt(node: CanvasNode): string {
  switch (node.kind) {
    case "note":
      return node.noteBody;
    case "pdf": {
      const selected = node.pdfSelectedText.trim();
      if (selected.length > 0) return selected;
      if (node.pdfVisibleText.trim().length > 0) return node.pdfVisibleText;
      return node.pdfText?.slice(0, 4000) ?? "";
    }
    case "epub":
      return node.epubVisibleText?.trim() || node.epubText?.slice(0, 4000) || "";
    case "web": {
      const selected = node.webSelectedText.trim();
      if (selected.length > 0) return selected;
      return node.webVisibleText?.trim() || node.webURL;
    }
    case "calc":
      return node.calcBody;
    case "slides":
      return node.slidesSelectedText?.trim() || "";
    default:
      return "";
  }
}

export function joinedNodeContext(nodes: readonly CanvasNode[], limit: number): string {
  let remaining = limit;
  const parts: string[] = [];
  for (const node of nodes) {
    if (remaining <= 0) break;
    const excerpt = nodeContextExcerpt(node).trim();
    if (excerpt.length === 0) continue;
    const heading = `[${KIND_LABELS[node.kind]}] ${node.title}`;
    const allowance = Math.max(0, remaining - heading.length - 1);
    const clipped = excerpt.slice(0, allowance);
    parts.push(`${heading}\n${clipped}`);
    remaining -= heading.length + clipped.length + 6;
  }
  return parts.join("\n\n---\n\n");
}
