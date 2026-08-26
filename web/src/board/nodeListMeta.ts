import type { CanvasNode } from "../domain/types.js";
import { pickBestCoverFromChapters, splitPages } from "../features/files/extract.js";

/** Retorna a capa do EPUB para usar na lousa. */
export function epubCoverDataUrl(node: CanvasNode): string | null {
  if (node.kind !== "epub") return null;
  if (node.epubCoverDataUrl !== null && node.epubCoverDataUrl !== undefined && node.epubCoverDataUrl.length > 0) {
    return node.epubCoverDataUrl;
  }
  if (node.epubText === null || node.epubText === undefined) return null;
  return pickBestCoverFromChapters(splitPages(node.epubText));
}

/** Detecta texto extraído de PDF com letras espaçadas (ex.: "d i A gr A m A ção"). */
export function isGarbledText(text: string): boolean {
  const words = text.trim().split(/\s+/).filter(Boolean);
  if (words.length < 6) return false;
  const isolatedLetters = words.filter((word) => /^[A-Za-zÀ-ÿ]$/.test(word)).length;
  return isolatedLetters / words.length > 0.18;
}

function firstMeaningfulLine(text: string): string {
  for (const line of text.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.length === 0) continue;
    if (isGarbledText(trimmed)) continue;
    return trimmed;
  }
  return "";
}

export function nodeListSubtitle(node: CanvasNode): string {
  switch (node.kind) {
    case "pdf": {
      const pages = node.pdfPageCount;
      if (pages !== null && pages !== undefined && pages > 0) {
        return `${pages} página${pages === 1 ? "" : "s"}`;
      }
      return "Documento PDF";
    }
    case "epub": {
      const chapters = node.epubPageCount;
      if (chapters !== null && chapters !== undefined && chapters > 0) {
        return `${chapters} capítulo${chapters === 1 ? "" : "s"}`;
      }
      return "Livro EPUB";
    }
    case "note": {
      const line = firstMeaningfulLine(node.noteBody);
      return line.length > 0 ? line.slice(0, 96) : "Nota vazia";
    }
    case "calc": {
      const line = firstMeaningfulLine(node.calcBody);
      return line.length > 0 ? line.slice(0, 96) : "Resolução em branco";
    }
    case "web": {
      try {
        return new URL(node.webURL).hostname.replace(/^www\./, "");
      } catch {
        return node.webURL || "Pesquisa web";
      }
    }
    case "slides":
      return "Apresentação";
    default:
      return "Toque para abrir";
  }
}
