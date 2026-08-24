import { useEffect, useRef, useState } from "react";
import type { PDFDocumentProxy } from "pdfjs-dist";
import { pdfjsLib } from "./pdf.js";
import "./files.css";

export interface PdfReaderProps {
  file: Blob;
  pageIndex: number;
  onPageChange: (index: number) => void;
  onPageCount: (count: number) => void;
  zoom?: number;
}

interface TextSpan {
  left: number;
  top: number;
  width: number;
  height: number;
  text: string;
}

const MAX_DPR = 3;

export default function PdfReader({
  file,
  pageIndex,
  onPageChange,
  onPageCount,
  zoom = 1,
}: PdfReaderProps) {
  const stageRef = useRef<HTMLDivElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const taskRef = useRef<ReturnType<typeof pdfjsLib.getDocument> | null>(null);

  const [numPages, setNumPages] = useState(0);
  const [doc, setDoc] = useState<PDFDocumentProxy | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [spans, setSpans] = useState<TextSpan[]>([]);
  const [stageWidth, setStageWidth] = useState(0);

  const clampedIndex = Math.max(0, Math.min(pageIndex, Math.max(0, numPages - 1)));

  useEffect(() => {
    const el = stageRef.current;
    if (el === null) return;
    const update = () => setStageWidth(el.clientWidth - 24);
    update();
    const observer = new ResizeObserver(update);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    setSpans([]);
    setDoc(null);
    void (async () => {
      try {
        const data = new Uint8Array(await file.arrayBuffer());
        const loadingTask = pdfjsLib.getDocument({ data });
        taskRef.current = loadingTask;
        const loaded = await loadingTask.promise;
        if (cancelled) {
          void loadingTask.destroy();
          return;
        }
        setDoc(loaded);
        setNumPages(loaded.numPages);
        onPageCount(loaded.numPages);
        setLoading(false);
      } catch (err) {
        if (cancelled) return;
        setError(
          err instanceof Error
            ? `Não foi possível carregar o PDF: ${err.message}`
            : "Não foi possível carregar o PDF.",
        );
        setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
      taskRef.current?.destroy();
      taskRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [file]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (doc === null || canvas === null || stageWidth <= 0) return;
    let cancelled = false;
    let task: { cancel: () => void; promise: Promise<void> } | null = null;
    void (async () => {
      try {
        setLoading(true);
        setSpans([]);
        const page = await doc.getPage(clampedIndex + 1);
        if (cancelled) return;

        const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
        const base = page.getViewport({ scale: 1 });
        const scale = (stageWidth / base.width) * zoom;
        const viewport = page.getViewport({ scale });

        canvas.width = Math.floor(viewport.width * dpr);
        canvas.height = Math.floor(viewport.height * dpr);
        canvas.style.width = `${Math.floor(viewport.width)}px`;
        canvas.style.height = `${Math.floor(viewport.height)}px`;

        const renderTask = page.render({
          canvas,
          viewport,
          transform: dpr !== 1 ? [dpr, 0, 0, dpr, 0, 0] : undefined,
        });
        task = renderTask;
        await renderTask.promise;
        if (cancelled) return;

        const content = await page.getTextContent();
        if (cancelled) return;
        const next: TextSpan[] = [];
        for (const item of content.items) {
          if (!("str" in item) || item.str.length === 0) continue;
          const tx = pdfjsLib.Util.transform(viewport.transform, item.transform);
          const fontHeight = Math.hypot(tx[2], tx[3]);
          next.push({
            left: tx[4],
            top: tx[5] - fontHeight,
            width: item.width * scale,
            height: fontHeight * 1.25,
            text: item.str,
          });
        }
        setSpans(next);
        setLoading(false);
      } catch (err) {
        if (cancelled) return;
        const name = (err as { name?: string } | null)?.name ?? "";
        if (name === "RenderingCancelledException") return;
        setError("Falha ao desenhar a página.");
        setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
      task?.cancel();
    };
  }, [doc, clampedIndex, numPages, zoom, stageWidth]);

  return (
    <div className="pdf-reader">
      <div className="files-bar">
        <button
          type="button"
          className="files-btn"
          onClick={() => onPageChange(clampedIndex - 1)}
          disabled={loading || clampedIndex <= 0}
        >
          ← Anterior
        </button>
        <span className="files-pos">
          pág. {numPages === 0 ? "–" : clampedIndex + 1} de {numPages === 0 ? "–" : numPages}
        </span>
        <button
          type="button"
          className="files-btn"
          onClick={() => onPageChange(clampedIndex + 1)}
          disabled={loading || numPages === 0 || clampedIndex >= numPages - 1}
        >
          Próxima →
        </button>
      </div>

      <div className="pdf-reader__stage" ref={stageRef}>
        <div className="pdf-reader__page">
          <canvas ref={canvasRef} />
          <div className="pdf-reader__textlayer">
            {spans.map((span, index) => (
              <span
                key={index}
                style={{
                  left: `${span.left}px`,
                  top: `${span.top}px`,
                  width: `${span.width}px`,
                  height: `${span.height}px`,
                }}
              >
                {span.text}
              </span>
            ))}
          </div>
        </div>
        {loading && <div className="files-loading">Carregando…</div>}
        {error !== null && <div className="files-error">{error}</div>}
      </div>
    </div>
  );
}
