import type { PDFPageProxy } from "pdfjs-dist";
import { pdfjsLib } from "./pdf.js";

// 2x já fica nítido em Retina e evita canvases gigantes em PDFs longos/pesados.
const MAX_DPR = 2;

export interface RenderedPdfPage {
  cssWidth: number;
  cssHeight: number;
  spans: TextSpan[];
}

export interface TextSpan {
  left: number;
  top: number;
  width: number;
  height: number;
  text: string;
  fontSize: number;
  angle: number;
}

export function buildTextSpans(
  items: Awaited<ReturnType<PDFPageProxy["getTextContent"]>>["items"],
  viewport: ReturnType<PDFPageProxy["getViewport"]>,
): TextSpan[] {
  const spans: TextSpan[] = [];
  for (const item of items) {
    if (!("str" in item) || item.str.length === 0) continue;
    const tx = pdfjsLib.Util.transform(viewport.transform, item.transform);
    const fontSize = Math.hypot(tx[0], tx[1]);
    if (fontSize <= 0) continue;
    const angle = Math.atan2(tx[1], tx[0]);
    spans.push({
      left: tx[4],
      top: tx[5] - fontSize,
      width: (item.width * fontSize) / (item.height || fontSize),
      height: fontSize * 1.2,
      text: item.str,
      fontSize,
      angle,
    });
  }
  return spans;
}

/** Renderiza num canvas offscreen e copia — evita “canvas em uso” no pdf.js com React Strict Mode. */
export async function renderPdfPageToCanvas(
  page: PDFPageProxy,
  target: HTMLCanvasElement,
  cssWidth: number,
  zoom = 1,
  includeText = true,
): Promise<RenderedPdfPage> {
  const base = page.getViewport({ scale: 1 });
  const scale = cssWidth > 0 ? (cssWidth / base.width) * zoom : zoom;
  const viewport = page.getViewport({ scale: Math.max(scale, 0.1) });
  const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);

  const cssW = Math.floor(viewport.width);
  const cssH = Math.floor(viewport.height);
  const pixelW = Math.floor(cssW * dpr);
  const pixelH = Math.floor(cssH * dpr);

  const scratch = document.createElement("canvas");
  scratch.width = pixelW;
  scratch.height = pixelH;

  const context = scratch.getContext("2d", { alpha: false });
  if (context === null) throw new Error("Canvas 2D indisponível");

  const renderTask = page.render({
    canvas: scratch,
    canvasContext: context,
    viewport,
    transform: dpr !== 1 ? [dpr, 0, 0, dpr, 0, 0] : undefined,
  });

  try {
    await renderTask.promise;
  } catch (err) {
    const name = (err as { name?: string } | null)?.name ?? "";
    if (name !== "RenderingCancelledException") throw err;
    throw err;
  }

  target.width = pixelW;
  target.height = pixelH;
  target.style.width = `${cssW}px`;
  target.style.height = `${cssH}px`;

  const targetCtx = target.getContext("2d", { alpha: false });
  if (targetCtx === null) throw new Error("Canvas 2D indisponível");
  targetCtx.drawImage(scratch, 0, 0);

  let spans: TextSpan[] = [];
  if (includeText) {
    try {
      const content = await page.getTextContent();
      spans = buildTextSpans(content.items, viewport);
    } catch {
      spans = [];
    }
  }

  return { cssWidth: cssW, cssHeight: cssH, spans };
}
